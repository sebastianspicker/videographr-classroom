import Foundation
import GuidanceEngine
import SessionCore
import UIKit

extension LiveStore {
    internal func handleRuntimeEvent(_ event: CaptureSessionController.CaptureRuntimeEvent) {
        if handleRuntimeLifecycleEvent(event) { return }
        if handleRuntimeRecordingEvent(event) { return }
        handleRuntimeSampleEvent(event)
    }

    private func handleRuntimeLifecycleEvent(_ event: CaptureSessionController.CaptureRuntimeEvent) -> Bool {
        if handleRuntimeStartupEvent(event) { return true }
        return handleRuntimeShutdownEvent(event)
    }

    private func handleRuntimeStartupEvent(_ event: CaptureSessionController.CaptureRuntimeEvent) -> Bool {
        if case let .sessionStarted(generation) = event {
            handleSessionStarted(generation: generation)
            return true
        }
        if case let .configuration(generation, videoConfiguration, audioRoute) = event {
            handleSessionConfiguration(generation: generation, videoConfiguration: videoConfiguration, audioRoute: audioRoute)
            return true
        }
        return false
    }

    private func handleRuntimeShutdownEvent(_ event: CaptureSessionController.CaptureRuntimeEvent) -> Bool {
        if case let .sessionStopped(generation) = event {
            handleSessionStopped(generation: generation)
            return true
        }
        if case let .fallback(generation, message) = event {
            startSimulatorFallback(reason: message, generation: generation)
            return true
        }
        return false
    }

    private func handleSessionStarted(generation: Int) {
        guard liveIsActive, generation == lifecycleGeneration else { return }
        isSessionRunning = true
        usingSimulatorFallback = false
        lastError = nil
    }

    private func handleSessionConfiguration(generation: Int, videoConfiguration: String, audioRoute: String) {
        guard liveIsActive, generation == lifecycleGeneration else { return }
        runtimeStatus.videoConfiguration = videoConfiguration
        runtimeStatus.audioRoute = audioRoute
    }

    private func handleSessionStopped(generation: Int) {
        guard generation == lifecycleGeneration else { return }
        isSessionRunning = false
    }

    private func handleRuntimeRecordingEvent(_ event: CaptureSessionController.CaptureRuntimeEvent) -> Bool {
        if case let .recordingCapacityUpdated(transaction, availableBytes) = event {
            updateRecordingCapacity(availableBytes, for: transaction)
            return true
        }
        return false
    }

    private func updateRecordingCapacity(_ availableBytes: Int64?, for transaction: RecordingTransaction) {
        guard acceptsRecordingEvent(for: transaction) else { return }
        runtimeStatus.availableCapacityBytes = availableBytes
    }

    private func handleRecordingStopRequest(_ transaction: RecordingTransaction, reason: String) {
        guard acceptsRecordingEvent(for: transaction) else { return }
        isStartingRecording = false
        isRecording = false
        isFinalizingRecording = true
        recordStatusMessage = reason
        persistOperationalObservation(kind: .transition, note: reason)
    }

    private func handleRuntimeSampleEvent(_ event: CaptureSessionController.CaptureRuntimeEvent) {
        if case let .frame(generation, analysis) = event {
            handleFrame(analysis, generation: generation)
            return
        }
        if case let .audio(generation, sample) = event {
            handleAudioSample(sample, generation: generation)
        }
    }

    private func handleFrame(_ analysis: LiveFrameAnalysis, generation: Int) {
        guard liveIsActive, generation == lifecycleGeneration else { return }
        if isSessionRunning { runtimeRecoveryAttempts = 0 }
        requiresFreshLiveSample = false
        if appIsActive, !captureIsInterrupted { privacyCoverIsVisible = false }
        frameMetrics = analysis.metrics
        cvFeatures = analysis.cv
        if analysis.cvWasRefreshed {
            recomputeGuidanceForNewFrame()
        } else {
            recomputeGuidance()
        }
    }

    private func handleAudioSample(_ sample: AudioLevelSample, generation: Int) {
        guard liveIsActive, generation == lifecycleGeneration else { return }
        audioSample = sample
    }

    internal func handleTransactionEvent(_ event: CaptureSessionController.CaptureTransactionEvent) {
        if case let .recordingStopRequested(transaction, reason) = event {
            handleRecordingStopRequest(transaction, reason: reason)
            return
        }
        if handleRecordingStateEvent(event) { return }
        if handleRecordingCompletionEvent(event) { return }
        if case let .recordingKeptUnverified(transaction, reason) = event {
            handleRecordingKeptUnverified(transaction, reason: reason)
            return
        }
        handleRecordingFailureEvent(event)
    }

    private func handleRecordingStateEvent(_ event: CaptureSessionController.CaptureTransactionEvent) -> Bool {
        if case let .recordingBegan(transaction) = event {
            handleRecordingBegan(transaction)
            return true
        }
        if case let .recordingFinalizing(transaction) = event {
            handleRecordingFinalizing(transaction)
            return true
        }
        return false
    }

    private func handleRecordingBegan(_ transaction: RecordingTransaction) {
        guard acceptsRecordingEvent(for: transaction) else { return }
        cancelWatchdog(.startAcknowledgement, for: transaction)
        Task { await appStore.markRecordingBegan(transaction) }
        let finalizationAlreadyRequested = stopRequestedDuringStart || isFinalizingRecording
        isStartingRecording = false
        isRecording = !finalizationAlreadyRequested
        isFinalizingRecording = finalizationAlreadyRequested
        recordStatusMessage = finalizationAlreadyRequested
            ? "Aufnahme wird finalisiert…"
            : "Kontinuierliche Aufnahme läuft"
        disableIdleTimerForRecording()
        persistCaptureObservation(
            from: guidance,
            force: true,
            kind: .transition,
            note: "AVCaptureFileOutput hat den Aufnahmestart bestätigt."
        )
    }

    private func handleRecordingFinalizing(_ transaction: RecordingTransaction) {
        guard acceptsRecordingEvent(for: transaction) else { return }
        cancelWatchdog(.startAcknowledgement, for: transaction)
        armFinalizationWatchdog(for: transaction)
        isStartingRecording = false
        isRecording = false
        isFinalizingRecording = true
        recordStatusMessage = "Aufnahme wird finalisiert…"
    }

    private func handleRecordingCompletionEvent(_ event: CaptureSessionController.CaptureTransactionEvent) -> Bool {
        if case let .recordingFinished(transaction, url) = event {
            handleRecordingFinished(transaction, url: url)
            return true
        }
        if case let .recordingRollbackCompleted(transaction, rollbackError) = event {
            handleRecordingRollback(transaction, rollbackError: rollbackError)
            return true
        }
        return false
    }

    private func handleRecordingFinished(_ transaction: RecordingTransaction, url: URL) {
        cancelWatchdog(.startAcknowledgement, for: transaction)
        cancelWatchdog(.finalization, for: transaction)
        if acceptsRecordingEvent(for: transaction) {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            // shortcut: assumes ≥250 MB/s read+hash on device, measure on the slowest supported device
            armMetadataAttachmentWatchdog(for: transaction, timeout: 8 + Double(size) / 250_000_000)
        }
        Task { [weak self] in
            await self?.resolveFinishedRecording(transaction: transaction, url: url)
        }
    }

    private func handleRecordingRollback(_ transaction: RecordingTransaction, rollbackError: String?) {
        cancelWatchdog(.finalization, for: transaction)
        cancelWatchdog(.metadataAttachment, for: transaction)
        if acceptsRecordingEvent(for: transaction) {
            completeRecordingTransaction(transaction, status: rollbackStatus(rollbackError))
            return
        }
        guard deferredArtifactTransactions[transaction] != nil else { return }
        deferredArtifactTransactions.removeValue(forKey: transaction)
        if let rollbackError {
            artifactRecoveryDiagnostic = "Lokale Aufnahmebereinigung fehlgeschlagen: \(rollbackError). Beim nächsten App-Start wird sie erneut geprüft."
        }
    }

    private func rollbackStatus(_ rollbackError: String?) -> String {
        if let rollbackError {
            return "Aufnahme-Metadaten konnten nicht gesichert werden; lokale Bereinigung fehlgeschlagen: \(rollbackError)"
        }
        return "Aufnahme-Metadaten konnten nicht gesichert werden; Datei wurde zurückgerollt."
    }

    private func handleRecordingFailureEvent(_ event: CaptureSessionController.CaptureTransactionEvent) {
        guard case let .recordingFailed(transaction, message) = event, let transaction else { return }
        cancelWatchdog(.startAcknowledgement, for: transaction)
        cancelWatchdog(.finalization, for: transaction)
        cancelWatchdog(.metadataAttachment, for: transaction)
        if acceptsRecordingEvent(for: transaction) {
            Task { await appStore.recordingDidFail(transaction, reason: message) }
            completeRecordingTransaction(transaction, status: message)
            return
        }
        if deferredArtifactTransactions.removeValue(forKey: transaction) != nil {
            Task { await appStore.recordingDidFail(transaction, reason: message) }
        }
    }

    /// Written media that could not be secured is kept for an operator decision, never failed.
    private func handleRecordingKeptUnverified(_ transaction: RecordingTransaction, reason: String) {
        cancelWatchdog(.startAcknowledgement, for: transaction)
        cancelWatchdog(.finalization, for: transaction)
        cancelWatchdog(.metadataAttachment, for: transaction)
        let isActive = acceptsRecordingEvent(for: transaction)
        guard isActive || deferredArtifactTransactions.removeValue(forKey: transaction) != nil else { return }
        Task { await appStore.keepUnresolvedTake(transaction, reason: reason) }
        if isActive { completeRecordingTransaction(transaction, status: Self.keptRecordingStatus) }
    }

    static let keptRecordingStatus = "Aufnahme aufbewahrt – in Reflektieren prüfen oder verwerfen."

    internal func acceptsRecordingEvent(for transaction: RecordingTransaction) -> Bool {
        activeRecordingTransaction == transaction
    }

    internal func resolveFinishedRecording(transaction: RecordingTransaction, url: URL) async {
        guard acceptsRecordingEvent(for: transaction) || deferredArtifactTransactions[transaction] != nil else { return }
        let outcome = await appStore.attachRecording(
            for: transaction,
            finalizedURL: url,
            runtimeStatus: runtimeStatus
        )
        cancelWatchdog(.metadataAttachment, for: transaction)
        if acceptsRecordingEvent(for: transaction) {
            resolveActiveFinishedRecording(transaction, url: url, outcome: outcome)
            return
        }
        resolveDeferredFinishedRecording(transaction, url: url, outcome: outcome)
    }

    private func resolveActiveFinishedRecording(
        _ transaction: RecordingTransaction,
        url: URL,
        outcome: RecordingAttachmentOutcome
    ) {
        switch outcome {
        case .attached:
            break
        case .refused:
            isStartingRecording = false
            isRecording = false
            isFinalizingRecording = true
            recordStatusMessage = "Aufnahme-Metadaten werden zurückgerollt…"
            capture.rollbackPromotedRecording(url, for: transaction)
            return
        case .kept:
            capture.confirmPromotedRecording(for: transaction)
            completeRecordingTransaction(transaction, status: Self.keptRecordingStatus)
            return
        }
        isRecording = false
        isStartingRecording = false
        isFinalizingRecording = false
        lastRecordingURL = url
        capture.confirmPromotedRecording(for: transaction)
        completeRecordingTransaction(transaction, status: "Aufnahme gespeichert")
    }

    internal func resolveDeferredFinishedRecording(
        _ transaction: RecordingTransaction,
        url: URL,
        outcome: RecordingAttachmentOutcome
    ) {
        guard deferredArtifactTransactions[transaction] != nil else { return }
        switch outcome {
        case .attached:
            capture.confirmPromotedRecording(for: transaction)
            deferredArtifactTransactions.removeValue(forKey: transaction)
            // Replaces the watchdog's "not confirmed" text unless a newer take owns the status.
            if activeRecordingTransaction == nil { recordStatusMessage = "Aufnahme gespeichert" }
        case .refused:
            capture.rollbackPromotedRecording(url, for: transaction)
        case .kept:
            capture.confirmPromotedRecording(for: transaction)
            deferredArtifactTransactions.removeValue(forKey: transaction)
        }
    }

}
