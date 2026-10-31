@preconcurrency import AVFoundation
import SwiftUI
import SessionCore

/// Records one ephemeral pre-roll speech sample and counts the check only after
/// the operator has played it to completion. Amplitude metrics alone never set
/// this acknowledgement.
@MainActor
final class SpokenAudioCheckModel: NSObject, ObservableObject {
    static let recordingDuration: TimeInterval = 4
    static let authorizationWindow: TimeInterval = 4.5

    enum Phase: Equatable {
        case idle
        case preparing
        case recording
        case ready
        case playing
        case completed
        case failed(String)
    }

    @Published var phase: Phase = .idle
    var recorder: AVAudioRecorder?
    var player: AVAudioPlayer?
    var fileURL: URL?
    var preparationTask: Task<Void, Never>?
    var authorizationExpiryTask: Task<Void, Never>?
    var resumeCapture: (() -> Void)?
    /// Capture paused by a check that inactivity cut short; restarted by `resumeAfterInactivity()`.
    var captureResumeAfterInactivity: (() -> Void)?
    var playbackCompletion: (() -> Void)?
    var authorization: SpokenAudioCheckAuthorization?
    var currentSession: (() -> CaptureSession)?

    override init() {
        super.init()
        cleanupAbandonedFiles()
    }

    func start(
        authorization: SpokenAudioCheckAuthorization,
        currentSession: @escaping () -> CaptureSession,
        pauseCapture: @escaping () -> Void,
        resumeCapture: @escaping () -> Void,
        playbackCompleted: @escaping () -> Void
    ) {
        guard !blocksCapture,
              authorization.authorizes(
                  currentSession(),
                  covering: Self.authorizationWindow
              ),
              prepareProtectedRecording()
        else { return }
        self.authorization = authorization
        self.currentSession = currentSession
        self.resumeCapture = resumeCapture
        self.playbackCompletion = playbackCompleted
        pauseCapture()
        scheduleAuthorizationExpiry(at: authorization.effectiveExpiresAt)
        scheduleRecordingStart()
    }

    func play() {
        guard phase == .ready, let fileURL else { return }
        guard authorizationIsCurrent() else {
            cancel(resumeCapture: false)
            return
        }
        do {
            let player = try makePlayer(for: fileURL)
            self.player = player
            phase = .playing
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Ends the check because the app left the foreground. Capture must not restart while
    /// inactive, so a capture this check paused is kept for `resumeAfterInactivity()`.
    func cancelForInactivity() {
        let pausedCapture = blocksCapture ? resumeCapture : captureResumeAfterInactivity
        cancel(resumeCapture: false)
        captureResumeAfterInactivity = pausedCapture
    }

    /// Restarts, at most once, the capture that an inactivity-cancelled check had paused.
    func resumeAfterInactivity() {
        let resume = captureResumeAfterInactivity
        captureResumeAfterInactivity = nil
        resume?()
    }

    func cancel(resumeCapture shouldResume: Bool) {
        captureResumeAfterInactivity = nil
        let mayResume = shouldResume && authorizationIsCurrent()
        preparationTask?.cancel()
        preparationTask = nil
        clearAuthorization()
        stopActiveAudio()
        cleanupFile()
        let resume = resumeCapture
        resumeCapture = nil
        playbackCompletion = nil
        phase = .idle
        deactivateAudioSession()
        if mayResume { resume?() }
    }

    func invalidateIfUnauthorized(for session: CaptureSession, at date: Date = Date()) {
        guard blocksCapture, authorization?.authorizes(session, at: date) != true else { return }
        cancel(resumeCapture: false)
    }

    func authorizationIsCurrent(
        at date: Date = Date(),
        covering duration: TimeInterval = 0
    ) -> Bool {
        guard let authorization, let currentSession else { return false }
        return authorization.authorizes(currentSession(), at: date, covering: duration)
    }

    func scheduleAuthorizationExpiry(at expiration: Date?) {
        authorizationExpiryTask?.cancel()
        guard let expiration else {
            authorizationExpiryTask = nil
            return
        }
        authorizationExpiryTask = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let remaining = expiration.timeIntervalSinceNow
                    if remaining <= 0 {
                        self?.invalidateCurrentAuthorization()
                        return
                    }
                    try await Task.sleep(for: .seconds(remaining))
                }
            } catch is CancellationError {
                return
            } catch {
                self?.invalidateCurrentAuthorization()
            }
        }
    }

    func invalidateCurrentAuthorization() {
        guard blocksCapture, !authorizationIsCurrent() else { return }
        cancel(resumeCapture: false)
    }

    func clearAuthorization() {
        authorizationExpiryTask?.cancel()
        authorizationExpiryTask = nil
        authorization = nil
        currentSession = nil
    }
}

extension SpokenAudioCheckModel: AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.recordingFinished(recorder, successfully: flag) }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.playbackFinished(player, successfully: flag) }
    }
}
