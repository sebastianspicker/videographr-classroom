import Foundation
import SessionCore
import UIKit

extension LiveStore {
    internal func completeRecordingTransaction(_ transaction: RecordingTransaction, status: String) {
        guard acceptsRecordingEvent(for: transaction) else { return }
        isStartingRecording = false
        isRecording = false
        isFinalizingRecording = false
        stopRequestedDuringStart = false
        cancelWatchdog(.startAcknowledgement, for: transaction)
        cancelWatchdog(.finalization, for: transaction)
        cancelWatchdog(.metadataAttachment, for: transaction)
        expirationRecoveryWorkItem?.cancel()
        expirationRecoveryWorkItem = nil
        recordStatusMessage = status
        activeRecordingTransaction = nil
        clearPreparedRecording(transaction)
        restoreIdleTimer()
        endRecordingBackgroundTask()
    }

    internal func beginRecordingBackgroundTask(for transaction: RecordingTransaction) {
        guard recordingBackgroundTask == .invalid else { return }
        recordingBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finalize recording") { [weak self] in
            self?.handleBackgroundExpiration(for: transaction)
        }
        if recordingBackgroundTask == .invalid, expirationRecoveryWorkItem == nil {
            handleBackgroundExpiration(for: transaction)
        }
    }

    internal func handleBackgroundExpiration(for transaction: RecordingTransaction) {
        guard acceptsRecordingEvent(for: transaction) else { return }
        capture.requestStop(transaction: transaction, reason: "Hintergrundzeit abgelaufen - Finalisierung angefordert.")
        endRecordingBackgroundTask()
        isStartingRecording = false
        isRecording = false
        isFinalizingRecording = true
        canRetryCapture = true
        recordStatusMessage = "Hintergrundzeit abgelaufen - Aufnahme wird beim nächsten Start geprüft."
        scheduleExpirationRecovery(for: transaction)
    }

    internal func scheduleExpirationRecovery(for transaction: RecordingTransaction) {
        expirationRecoveryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.acceptsRecordingEvent(for: transaction) else { return }
            self.releaseExpiredTransactionUI(transaction)
        }
        expirationRecoveryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: workItem)
    }

    internal func releaseExpiredTransactionUI(_ transaction: RecordingTransaction) {
        guard acceptsRecordingEvent(for: transaction) else { return }
        cancelWatchdog(.startAcknowledgement, for: transaction)
        cancelWatchdog(.finalization, for: transaction)
        cancelWatchdog(.metadataAttachment, for: transaction)
        isStartingRecording = false
        isRecording = false
        isFinalizingRecording = false
        stopRequestedDuringStart = false
        recordStatusMessage = "Finalisierung nicht bestätigt. Lokale Aufnahme wird beim nächsten App-Start geprüft."
        activeRecordingTransaction = nil
        restoreIdleTimer()
        deferredArtifactTransactions[transaction] = ()
        clearPreparedRecording(transaction)
        Task { await appStore.recordingCompletionIsUnknown(transaction) }
        canRetryCapture = true
        expirationRecoveryWorkItem = nil
        endRecordingBackgroundTask()
    }

    internal func armStartAcknowledgementWatchdog(for transaction: RecordingTransaction) {
        startAcknowledgementWatchdogWorkItem?.cancel()
        recordingWatchdogs.arm(.startAcknowledgement, for: transaction)
        let workItem = DispatchWorkItem { [weak self] in
            self?.expireStartAcknowledgementWatchdog(for: transaction)
        }
        startAcknowledgementWatchdogWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: workItem)
    }

    internal func armFinalizationWatchdog(for transaction: RecordingTransaction) {
        finalizationWatchdogWorkItem?.cancel()
        recordingWatchdogs.arm(.finalization, for: transaction)
        let workItem = DispatchWorkItem { [weak self] in
            self?.expireFinalizationWatchdog(for: transaction)
        }
        finalizationWatchdogWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: workItem)
    }

    internal func armMetadataAttachmentWatchdog(for transaction: RecordingTransaction, timeout: TimeInterval) {
        metadataAttachmentWatchdogWorkItem?.cancel()
        recordingWatchdogs.arm(.metadataAttachment, for: transaction)
        let workItem = DispatchWorkItem { [weak self] in
            self?.expireMetadataAttachmentWatchdog(for: transaction)
        }
        metadataAttachmentWatchdogWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    internal func cancelWatchdog(
        _ phase: RecordingTransactionWatchdogs<RecordingTransaction>.Phase,
        for transaction: RecordingTransaction
    ) {
        guard recordingWatchdogs.cancel(phase, for: transaction) else { return }
        if phase == .startAcknowledgement {
            startAcknowledgementWatchdogWorkItem?.cancel()
            startAcknowledgementWatchdogWorkItem = nil
            return
        }
        if phase == .finalization {
            finalizationWatchdogWorkItem?.cancel()
            finalizationWatchdogWorkItem = nil
            return
        }
        metadataAttachmentWatchdogWorkItem?.cancel()
        metadataAttachmentWatchdogWorkItem = nil
    }

    internal func expireStartAcknowledgementWatchdog(for transaction: RecordingTransaction) {
        guard recordingWatchdogs.expire(.startAcknowledgement, for: transaction), acceptsRecordingEvent(for: transaction) else { return }
        startAcknowledgementWatchdogWorkItem = nil
        capture.requestStop(transaction: transaction, reason: "Startbestätigung ausstehend - Finalisierung angefordert.")
        releaseExpiredTransactionUI(transaction)
    }

    internal func expireFinalizationWatchdog(for transaction: RecordingTransaction) {
        guard recordingWatchdogs.expire(.finalization, for: transaction), acceptsRecordingEvent(for: transaction) else { return }
        finalizationWatchdogWorkItem = nil
        releaseExpiredTransactionUI(transaction)
    }

    internal func expireMetadataAttachmentWatchdog(for transaction: RecordingTransaction) {
        guard recordingWatchdogs.expire(.metadataAttachment, for: transaction), acceptsRecordingEvent(for: transaction) else { return }
        metadataAttachmentWatchdogWorkItem = nil
        releaseExpiredTransactionUI(transaction)
    }

    internal func endRecordingBackgroundTask() {
        guard recordingBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(recordingBackgroundTask)
        recordingBackgroundTask = .invalid
    }
}
