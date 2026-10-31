import Foundation
import AVFoundation
import ExperimentalResearch
import GuidanceEngine
import SessionCore
import QuartzCore
import UIKit

/// Publishes transient capture state and guidance; `CaptureSessionController` owns AVFoundation objects.
///
/// Production path: sample buffers → `FrameSampler` (luminance + Vision) + `MotionService` →
/// pure `GuidanceEngine` observability plus explicitly authorized research windows → Live UI.
/// Simulator path: synthetic classroom fixtures so demos work without hardware.
@MainActor
final class LiveStore: NSObject, ObservableObject {
    /// The only durable-workflow boundary. LiveStore never exposes persistence callbacks to views.
    let appStore: AppStore
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined
    @Published var microphoneAuthorizationStatus: AVAuthorizationStatus = .notDetermined
    @Published var isSessionRunning = false
    @Published var lastError: String?
    @Published var frameMetrics = FrameMetrics()
    @Published var cvFeatures = CVFeatures.empty
    @Published var guidance = GuidanceResult(tips: [])
    @Published var usingSimulatorFallback = false
    @Published var audioSample = AudioLevelSample()
    @Published var isStartingRecording = false
    @Published var isRecording = false
    @Published var isFinalizingRecording = false
    @Published var lastRecordingURL: URL?
    @Published var recordStatusMessage: String?
    /// Blocks the preview whenever an inactive/interrupted capture could expose stale pixels.
    @Published var privacyCoverIsVisible = true
    @Published var canRetryCapture = false
    /// In-memory recovery notice for Live UI; never replaces a newer take's status.
    @Published var artifactRecoveryDiagnostic: String?
    @Published var runtimeStatus = CaptureRuntimeStatus()
    /// Teaching-situation preset from Setup - drives scene expectations and coding.
    @Published var teachingSituation: TeachingSituationID = .frontalBoardInstruction {
        didSet {
            if oldValue != teachingSituation {
                capture.prepareVision(for: teachingSituation, generation: lifecycleGeneration)
                analysis.reset()
                clearExperimentalOutput()
                recomputeGuidance()
            }
        }
    }
    /// Experimental-only analysis focus for unvalidated IPN/GTI rule priors.
    @Published var analysisFocus: CodingAnalysisFocus = .lessonAnalysis {
        didSet {
            if oldValue != analysisFocus {
                analysis.reset()
                clearExperimentalOutput()
                recomputeGuidance()
            }
        }
    }
    /// Evidence-safe by default; experimental hypotheses require a persisted, usable protocol.
    @Published var operatingMode: OperatingMode = .evidenceSafe {
        didSet {
            if oldValue != operatingMode {
                analysis.reset()
                clearExperimentalOutput()
                recomputeGuidance()
            }
        }
    }
    /// Experimental-only temporal aggregation of unvalidated IPN/TIMSS/GTI rules.
    @Published var windowedCoding: PedagogicalCodingResult = .empty()
    /// Unvalidated experimental output; never used for readiness or export eligibility.
    @Published var experimentalResult: ExperimentalResearchResult?
    /// Latest research-exportable coding snapshot.
    @Published var latestCodingSnapshot: ResearchCodingSnapshot?
    internal var activePreparedRecording: AppStore.PreparedRecording?
    internal var captureAuthorizationDeadlineTask: Task<Void, Never>?
    internal var activeRecordingTransaction: RecordingTransaction?
    /// Terminal ownership retained after background expiry so a late delegate callback can still
    /// attach or roll back its artifact without changing a newer take's UI state.
    internal var deferredArtifactTransactions: [RecordingTransaction: Void] = [:]
    internal var stopRequestedDuringStart = false
    internal var recordingBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    internal var expirationRecoveryWorkItem: DispatchWorkItem?
    internal var startAcknowledgementWatchdogWorkItem: DispatchWorkItem?
    internal var finalizationWatchdogWorkItem: DispatchWorkItem?
    internal var metadataAttachmentWatchdogWorkItem: DispatchWorkItem?
    internal var recordingWatchdogs = RecordingTransactionWatchdogs<RecordingTransaction>()
    internal var boundSessionID: UUID?
    internal var requiresFreshLiveSample = true

    internal let capture = CaptureSessionController()
    /// Read-only preview handle. Configuration and start/stop stay inside `capture`.
    var session: AVCaptureSession { capture.session }
    internal let motion = MotionService()
    internal let engine = GuidanceEngine()
    internal let researchEngine = ExperimentalResearchEngine()
    /// Experimental-only smoothing windows and transition detector.
    internal var analysis = ExperimentalAnalysisSession()
    /// Experimental-only scene/TIMSS rule transitions.
    @Published var recentTransitions: [SceneTransitionEvent] = []
    internal var lastPersistedSnapshotAt: CFTimeInterval = 0
    internal var lastPersistedObservationAt: CFTimeInterval = 0
    internal let observerStorage = CaptureObserverStorage()
    internal var simulatorTimer: Timer?
    internal var simulatorTick = 0
    internal var simAudioPhase = 0
    internal var lifecycleGeneration = 0
    internal var liveIsActive = false
    internal var viewWantsLive = false
    internal var appIsActive = true
    internal var captureIsInterrupted = false
    internal var runtimeRecoveryAttempts = 0
    internal let maximumRuntimeRecoveryAttempts = 1
    internal var previousIdleTimerDisabled: Bool?
    internal var motionGuidanceCadence = MotionGuidanceCadence(minimumInterval: 0.2)

    init(appStore: AppStore) {
        self.appStore = appStore
        super.init()
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        microphoneAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshRuntimeStatus()
        configureCaptureObservers()
    }

    internal func persistOperationalObservation(kind: CaptureObservationKind, note: String) {
        guard isStartingRecording || isRecording || isFinalizingRecording,
              let transaction = activeRecordingTransaction,
              let boundSessionID,
              boundSessionID == transaction.sessionID
        else { return }
        var observationValues = CaptureObservation.Values()
        observationValues.kind = kind
        observationValues.measurements = CaptureObservation.operationalMeasurements(audio: audioSample)
        observationValues.note = note
        let observation = CaptureObservation(observationValues)
        Task { await appStore.attachCaptureObservation(observation, for: boundSessionID) }
    }

}
