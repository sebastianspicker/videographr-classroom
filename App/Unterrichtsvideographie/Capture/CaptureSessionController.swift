import AVFoundation
import Foundation
import GuidanceEngine
import QuartzCore
import SessionCore

/// Serial owner for AVFoundation capture objects. UI state is never mutated here; callers receive
/// value events and publish them on the main actor. The session, movie output, and their lifecycle
/// are confined to `sessionQueue`; Vision state is confined to `videoQueue`.
final class CaptureSessionController: NSObject {
    /// Coalescible, generation-scoped samples and negotiated runtime facts.
    enum CaptureRuntimeEvent: Sendable {
        case sessionStarted(Int)
        case sessionStopped(Int)
        case configuration(Int, videoConfiguration: String, audioRoute: String)
        case fallback(Int, String)
        case frame(Int, LiveFrameAnalysis)
        case audio(Int, AudioLevelSample)
        case recordingCapacityUpdated(RecordingTransaction, Int64?)
    }

    /// Ordered recording lifecycle facts. These are never coalesced with preview samples.
    enum CaptureTransactionEvent: Sendable {
        case recordingBegan(RecordingTransaction)
        case recordingFinalizing(RecordingTransaction)
        case recordingFinished(RecordingTransaction, URL)
        case recordingRollbackCompleted(RecordingTransaction, String?)
        case recordingFailed(RecordingTransaction?, String)
        case recordingStopRequested(RecordingTransaction, String)
    }

    let session = AVCaptureSession()
    var runtimeEventSink: ((CaptureRuntimeEvent) -> Void)?
    var transactionEventSink: ((CaptureTransactionEvent) -> Void)?

    let sessionQueue = DispatchQueue(label: "uv.camera.session")
    let videoQueue = DispatchQueue(label: "uv.camera.video", qos: .userInitiated)
    let audioQueue = DispatchQueue(label: "uv.camera.audio", qos: .userInitiated)
    let sampler = FrameSampler()
    var videoOutput: AVCaptureVideoDataOutput?
    var movieOutput: AVCaptureMovieFileOutput?
    var activeGeneration: Int?
    var videoGeneration: Int?
    var audioGeneration: Int?
    var isActive = false
    var pendingStop = false
    var recording: Recording?
    var promotedArtifacts = RecordingArtifactOwnership<RecordingTransaction>()
    var queuedStart: StartRequest?
    var audioDeliveryScheduled = false
    var latestAudio: (generation: Int, sample: AudioLevelSample)?
    var lastAudioDeliveryTime: CFTimeInterval = 0
    let minimumAudioDeliveryInterval: CFTimeInterval = 0.1
    var audioUsesExternalMicrophone = false
    let reusableAudioBufferList = ReusableAudioBufferList(maximumBuffers: 8)
    var minimumObservedAudioAverage: Double?
    var expectedNextAudioPresentationTime: CMTime?
    var capacityMonitor: DispatchSourceTimer?

    struct Recording {
        let transaction: RecordingTransaction
        let artifacts: any RecordingArtifactSecuring
        let temporaryURL: URL
        let destinationURL: URL
        var didStart: Bool
        var stopRequested: Bool
        var finalizing: Bool
    }

    struct RecordingStartRequest {
        let destinationURL: URL
        let stagedURL: URL
        let transaction: RecordingTransaction
        let artifacts: any RecordingArtifactSecuring
    }

    /// The planned duration is a planning value only; the free-capacity monitor is the single
    /// automatic stop. Clear both AVFoundation caps so no earlier configuration truncates a take.
    static func removeRecordingLimits(from output: AVCaptureMovieFileOutput) {
        output.maxRecordedDuration = .invalid
        output.maxRecordedFileSize = 0
    }

    struct StartRequest {
        let generation: Int
        let teachingSituation: TeachingSituationID
        let rotationAngle: CGFloat
    }

    func prepareVision(for situation: TeachingSituationID, generation: Int) {
        videoQueue.async(execute: DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.videoGeneration = generation
            self.sampler.configureVision(for: situation)
            self.sampler.resetVisionTemporalState()
        })
    }

    func resetVisionTemporalState() {
        videoQueue.async(execute: DispatchWorkItem { [weak self] in self?.sampler.resetVisionTemporalState() })
    }

    func start(generation: Int, teachingSituation: TeachingSituationID, rotationAngle: CGFloat) {
        sessionQueue.async(execute: DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.recording != nil {
                self.isActive = true
                self.activeGeneration = generation
                self.queuedStart = StartRequest(
                    generation: generation,
                    teachingSituation: teachingSituation,
                    rotationAngle: rotationAngle
                )
                return
            }
            self.activeGeneration = generation
            self.isActive = true
            self.pendingStop = false
            self.videoQueue.async(execute: DispatchWorkItem { [weak self] in self?.videoGeneration = generation })
            self.audioQueue.async(execute: DispatchWorkItem { [weak self] in
                self?.audioGeneration = generation
                self?.latestAudio = nil
                self?.audioDeliveryScheduled = false
                self?.lastAudioDeliveryTime = 0
                self?.minimumObservedAudioAverage = nil
                self?.expectedNextAudioPresentationTime = nil
            })
            self.configureSession(
                generation: generation,
                teachingSituation: teachingSituation,
                rotationAngle: rotationAngle
            )
        })
    }

    func stopAfterRecordingFinalizes() {
        sessionQueue.async(execute: DispatchWorkItem { [weak self] in
            guard let self else { return }
            let stoppingGeneration = self.activeGeneration
            self.isActive = false
            self.activeGeneration = nil
            self.queuedStart = nil
            self.videoQueue.async(execute: DispatchWorkItem { [weak self] in self?.videoGeneration = nil })
            self.audioQueue.async(execute: DispatchWorkItem { [weak self] in
                self?.audioGeneration = nil
                self?.latestAudio = nil
                self?.audioDeliveryScheduled = false
                self?.lastAudioDeliveryTime = 0
                self?.minimumObservedAudioAverage = nil
                self?.expectedNextAudioPresentationTime = nil
            })
            if self.recording != nil {
                self.pendingStop = true
                if let recording = self.recording {
                    self.requestStopOnSessionQueue(
                        transaction: recording.transaction,
                        reason: "Live-Aufnahme wird beendet."
                    )
                }
            } else {
                self.stopSession(generation: stoppingGeneration)
            }
        })
    }

    func startRecording(_ request: RecordingStartRequest) {
        sessionQueue.async(execute: DispatchWorkItem { [weak self] in
            guard let self,
                  self.isActive,
                  self.activeGeneration == request.transaction.generation,
                  self.recording == nil,
                  self.session.isRunning,
                  let movieOutput = self.movieOutput
            else {
                self?.emitTransaction(.recordingFailed(request.transaction, "Capture-Session nicht bereit."))
                return
            }

            Self.removeRecordingLimits(from: movieOutput)
            self.recording = Recording(
                transaction: request.transaction,
                artifacts: request.artifacts,
                temporaryURL: request.stagedURL,
                destinationURL: request.destinationURL,
                didStart: false,
                stopRequested: false,
                finalizing: false
            )
            movieOutput.startRecording(to: request.stagedURL, recordingDelegate: self)
        })
    }

    /// The one idempotent recording-stop request path. It emits at most one lifecycle event.
    func requestStop(transaction: RecordingTransaction, reason: String) {
        sessionQueue.async(execute: DispatchWorkItem { [weak self] in
            self?.requestStopOnSessionQueue(transaction: transaction, reason: reason)
        })
    }

    func requestStopOnSessionQueue(transaction: RecordingTransaction, reason: String) {
        guard var recording = recording, recording.transaction == transaction, !recording.stopRequested else { return }
        recording.stopRequested = true
        self.recording = recording
        emitTransaction(.recordingStopRequested(recording.transaction, reason))
        if recording.didStart { finishRecordingIfNeeded() }
    }

    func rollbackPromotedRecording(_ url: URL, for transaction: RecordingTransaction) {
        sessionQueue.async(execute: DispatchWorkItem { [weak self] in
            guard let self,
                  let promotedURL = self.promotedArtifacts.validatedDestination(
                    for: transaction,
                    matching: url
                  )
            else {
                self?.emitTransaction(.recordingRollbackCompleted(
                    transaction,
                    "Die zugehörige Aufnahme konnte nicht eindeutig verifiziert werden."
                ))
                return
            }
            do {
                try FileManager.default.removeItem(at: promotedURL)
                self.promotedArtifacts.confirm(transaction)
                self.emitTransaction(.recordingRollbackCompleted(transaction, nil))
            } catch {
                // Retain the transaction marker: a later start cannot mistake this canonical
                // artifact for a successful recording, and startup reconciliation can report it.
                self.emitTransaction(.recordingRollbackCompleted(transaction, error.localizedDescription))
            }
        })
    }

    func confirmPromotedRecording(for transaction: RecordingTransaction) {
        sessionQueue.async(execute: DispatchWorkItem { [weak self] in
            self?.promotedArtifacts.confirm(transaction)
        })
    }

    func updateVideoRotation(angle: CGFloat) {
        sessionQueue.async(execute: DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.setRotation(angle, for: self.videoOutput?.connection(with: .video))
            self.setRotation(angle, for: self.movieOutput?.connection(with: .video))
        })
    }

    func refreshAudioRouteCache() {
        sessionQueue.async(execute: DispatchWorkItem { [weak self] in
            self?.cacheCurrentAudioRouteOnSessionQueue()
        })
    }

    func cacheCurrentAudioRouteOnSessionQueue() {
        let external = AVAudioSession.sharedInstance().currentRoute.inputs.contains {
            $0.portType == .headsetMic || $0.portType == .usbAudio || $0.portType == .bluetoothHFP
        }
        audioQueue.async(execute: DispatchWorkItem { [weak self] in
            self?.audioUsesExternalMicrophone = external
        })
    }

    func finishRecordingIfNeeded() {
        guard var recording else { return }
        guard recording.didStart else { return }
        guard !recording.finalizing else { return }
        recording.finalizing = true
        self.recording = recording
        stopCapacityMonitor()
        emitTransaction(.recordingFinalizing(recording.transaction))
        movieOutput?.stopRecording()
    }

    func stopSession(generation: Int?) {
        guard let generation else { return }
        guard session.isRunning else {
            emitRuntime(.sessionStopped(generation))
            return
        }
        session.stopRunning()
        emitRuntime(.sessionStopped(generation))
    }

    func setRotation(_ angle: CGFloat, for connection: AVCaptureConnection?) {
        guard let connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    func emitRuntime(_ event: CaptureRuntimeEvent) {
        runtimeEventSink?(event)
    }

    func emitTransaction(_ event: CaptureTransactionEvent) {
        transactionEventSink?(event)
    }
}
