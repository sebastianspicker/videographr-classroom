import AVFoundation
import Foundation
import SessionCore

extension CaptureSessionController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        sessionQueue.async(execute: DispatchWorkItem { [weak self] in
            guard let self, var recording = self.recording,
                  recording.temporaryURL.standardizedFileURL == fileURL.standardizedFileURL
            else { return }
            recording.didStart = true
            self.recording = recording
            self.emitTransaction(.recordingBegan(recording.transaction))
            self.startCapacityMonitor(for: recording)
            if recording.stopRequested {
                self.finishRecordingIfNeeded()
            }
        })
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        sessionQueue.async(execute: DispatchWorkItem { [weak self] in
            self?.finalizeRecording(outputURL: outputFileURL, error: error)
        })
    }

    private func finalizeRecording(outputURL: URL, error: Error?) {
        guard let recording else { return }
        stopCapacityMonitor()
        self.recording = nil
        if recordingSucceeded(error) {
            finalizeSuccessfulRecording(recording, outputURL: outputURL)
        } else {
            discardFailedRecording(recording, error: error)
        }
        stopPendingSessionIfNeeded(for: recording)
        startQueuedSessionIfNeeded()
    }

    private func finalizeSuccessfulRecording(_ recording: Recording, outputURL: URL) {
        var promoted = false
        do {
            try recording.artifacts.secureFinalizedRecording(at: outputURL)
            guard !promotedArtifacts.isDestinationOwned(recording.destinationURL) else {
                throw CocoaError(.fileWriteFileExists)
            }
            try promoteTemporaryMovie(from: outputURL, to: recording.destinationURL)
            promoted = true
            // Re-verify the local artifact policy under the canonical name.
            try recording.artifacts.secureFinalizedRecording(at: recording.destinationURL)
            guard promotedArtifacts.register(recording.transaction, at: recording.destinationURL) else {
                throw CocoaError(.fileWriteFileExists)
            }
            emitTransaction(.recordingFinished(recording.transaction, recording.destinationURL))
        } catch {
            keepUnverifiedRecording(recording, promoted: promoted, failure: error)
        }
    }

    private func discardFailedRecording(_ recording: Recording, error: Error?) {
        // A non-empty partial movie is often playable; keep it like a take cut off by termination.
        if stagedRecordingHasContent(recording.temporaryURL) {
            emitTransaction(.recordingKeptUnverified(
                recording.transaction,
                error?.localizedDescription ?? "Aufnahme wurde nicht erfolgreich abgeschlossen."
            ))
            return
        }
        try? recording.artifacts.discardStagedRecording(at: recording.temporaryURL)
        emitTransaction(.recordingFailed(
            recording.transaction,
            error?.localizedDescription ?? "Aufnahme wurde nicht erfolgreich abgeschlossen."
        ))
    }

    private func keepUnverifiedRecording(_ recording: Recording, promoted: Bool, failure: Error) {
        if promoted {
            // Only this transaction promoted the canonical path: stage it again so it is never
            // mistaken for a saved take. If the move fails it stays canonical, which is offered too.
            try? FileManager.default.moveItem(at: recording.destinationURL, to: recording.temporaryURL)
        }
        emitTransaction(.recordingKeptUnverified(
            recording.transaction,
            "Aufnahme konnte nicht sicher gespeichert werden: \(failure.localizedDescription)"
        ))
    }

    private func stagedRecordingHasContent(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else { return false }
        return values.isRegularFile == true && (values.fileSize ?? 0) > 0
    }

    private func stopPendingSessionIfNeeded(for recording: Recording) {
        guard pendingStop else { return }
        pendingStop = false
        stopSession(generation: recording.transaction.generation)
    }

    private func startQueuedSessionIfNeeded() {
        guard isActive, let queuedStart else { return }
        self.queuedStart = nil
        activeGeneration = queuedStart.generation
        isActive = true
        pendingStop = false
        videoQueue.async(execute: DispatchWorkItem { [weak self] in self?.videoGeneration = queuedStart.generation })
        audioQueue.async(execute: DispatchWorkItem { [weak self] in
            self?.audioGeneration = queuedStart.generation
            self?.latestAudio = nil
            self?.minimumObservedAudioAverage = nil
            self?.expectedNextAudioPresentationTime = nil
        })
        configureSession(
            generation: queuedStart.generation,
            teachingSituation: queuedStart.teachingSituation,
            rotationAngle: queuedStart.rotationAngle
        )
    }

    private func recordingSucceeded(_ error: Error?) -> Bool {
        guard let error else { return true }
        let nsError = error as NSError
        return (nsError.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == true
    }

    private func promoteTemporaryMovie(from temporaryURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    }
}
