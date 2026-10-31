import AVFoundation
import Foundation
import ExperimentalResearch
import GuidanceEngine
import SessionCore
import UIKit

extension LiveStore {
    /// Synchronizes durable consent/protocol authority into the transient capture boundary.
    func synchronizeSession() {
        let session = appStore.session
        bind(to: session.id)
        teachingSituation = session.teachingSituation
        analysisFocus = session.analysisIntent
        operatingMode = session.operatingMode == .experimentalResearch
            && session.hasUsableExperimentalProtocol
            && session.experimentalProtocol?.protocolIdentifier != nil
            ? .experimentalResearch
            : .evidenceSafe
        let authorized = activePreparedRecording.map { appStore.recordingAuthorizationIsValid($0) }
            ?? (session.authorizes(ConsentScope.collection) && session.authorizes(ConsentScope.localReflection))
        enforceCaptureAuthorization(authorized, transactionID: activePreparedRecording?.transactionID)
    }

    /// The capture boundary prepares only the AVFoundation request after AppStore durably reserves it.
    func beginRecording(
        readiness: SessionReadiness,
        allowDespiteWarnings: Bool,
        overrideReason: String,
        operatorPseudonym: String
    ) async {
        guard !usingSimulatorFallback else {
            rejectSimulatorRecordingAttempt()
            return
        }
        let preparation = AppStore.RecordingPreparation(
            transactionID: UUID(),
            readiness: readiness,
            overrideReason: allowDespiteWarnings ? overrideReason : "",
            operatorPseudonym: operatorPseudonym,
            runtimeStatus: runtimeStatus
        )
        guard let prepared = await appStore.prepareSessionForRecording(preparation) else {
            showRecordingPreparationError(appStore.lastStoreError ?? "Die Sitzung konnte nicht für die Aufnahme vorbereitet werden.")
            return
        }
        guard appStore.recordingAuthorizationIsValid(prepared) else {
            await appStore.cancelPreparedRecording(prepared)
            showRecordingPreparationError("Aufnahme blockiert: die vorbereitende Freigabe ist nicht mehr aktiv.")
            return
        }
        let started = startRecording(RecordingStartRequest(
            url: prepared.url,
            stagedURL: prepared.stagedURL,
            allowDespiteWarnings: allowDespiteWarnings,
            readiness: readiness,
            plannedDurationMinutes: prepared.plannedDurationMinutes,
            sessionID: prepared.sessionID,
            transactionID: prepared.transactionID,
            artifacts: appStore.recordingArtifacts
        ))
        guard started else {
            await appStore.cancelPreparedRecording(prepared)
            return
        }
        activePreparedRecording = prepared
        scheduleAuthorizationDeadline(for: prepared)
    }

    private func scheduleAuthorizationDeadline(for prepared: AppStore.PreparedRecording) {
        captureAuthorizationDeadlineTask?.cancel()
        guard let expiry = prepared.authorization.effectiveExpiresAt else { return }
        let delay = max(0, expiry.timeIntervalSinceNow - 30)
        let nanoseconds = UInt64(min(delay, Double(UInt64.max) / 1_000_000_000) * 1_000_000_000)
        captureAuthorizationDeadlineTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: nanoseconds) } catch { return }
            guard self?.activePreparedRecording?.transactionID == prepared.transactionID else { return }
            self?.enforceCaptureAuthorization(
                false,
                transactionID: prepared.transactionID,
                reason: "Erforderliche Freigabe läuft in weniger als 30 Sekunden ab - Aufnahme wird finalisiert."
            )
        }
    }

    internal func clearPreparedRecording(_ transaction: RecordingTransaction) {
        guard activePreparedRecording?.transactionID == transaction.transactionID else { return }
        captureAuthorizationDeadlineTask?.cancel()
        captureAuthorizationDeadlineTask = nil
        activePreparedRecording = nil
    }

    func start() {
        viewWantsLive = true
        activateLive()
    }

    private func activateLive() {
        guard viewWantsLive else { return }
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        liveIsActive = true
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        // Vision is configured by the serial capture owner only after this generation's
        // session has been configured and started. Retagging here could mislabel an old frame.
        isSessionRunning = false
        usingSimulatorFallback = false
        lastError = nil
        canRetryCapture = false
        // A capture transaction outlives preview generations. A foreground resume can arrive
        // before the serial capture queue emits `recordingFinalizing`; keep ownership until a
        // tagged terminal event closes it.
        if activeRecordingTransaction == nil {
            isStartingRecording = false
            isRecording = false
            isFinalizingRecording = false
        }
        lastRecordingURL = nil
        recordStatusMessage = nil
        invalidateDirectVisualSample()
        experimentalResult = nil
        latestCodingSnapshot = nil
        audioSample = AudioLevelSample()
        analysis.reset()
        recentTransitions = []
        windowedCoding = .empty()
        lastPersistedSnapshotAt = 0
        motion.start()
        requestMicThenVideo(generation: generation)
    }

    func bind(to sessionID: UUID) {
        guard boundSessionID != sessionID else { return }
        boundSessionID = sessionID
        latestCodingSnapshot = nil
        lastPersistedSnapshotAt = 0
        invalidateDirectVisualSample()
        audioSample = AudioLevelSample()
        runtimeStatus.spokenAudioCheckCompleted = false
        experimentalResult = nil
        windowedCoding = .empty()
        analysis.reset()
        recentTransitions = []
    }

    private func requestMicThenVideo(generation: Int) {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        microphoneAuthorizationStatus = micStatus
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    self?.microphoneAuthorizationStatus = granted ? .authorized : .denied
                    self?.requestVideo(generation: generation)
                }
            }
        } else {
            requestVideo(generation: generation)
        }
    }

    private func requestVideo(generation: Int) {
        guard liveIsActive, generation == lifecycleGeneration else { return }
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        microphoneAuthorizationStatus = micStatus
        guard micStatus == .authorized else {
            startSimulatorFallback(
                reason: "Mikrofonzugriff erforderlich - Berechtigung in Einstellungen aktivieren.",
                generation: generation
            )
            return
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        authorizationStatus = status
        if status == .authorized {
            configureAndStartSession(generation: generation)
            return
        }
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    self?.handleVideoAuthorization(granted, generation: generation)
                }
            }
            return
        }
        startSimulatorFallback(
            reason: "Keine Kamera-Berechtigung - Demo-Modus mit synthetischem Klassenzimmer",
            generation: generation
        )
    }

    private func handleVideoAuthorization(_ granted: Bool, generation: Int) {
        authorizationStatus = granted ? .authorized : .denied
        guard liveIsActive, lifecycleGeneration == generation else { return }
        if granted {
            configureAndStartSession(generation: generation)
            return
        }
        startSimulatorFallback(reason: "Kamerazugriff verweigert - Demo-Modus", generation: generation)
    }

    /// Tear down motion, timers, Vision state, and the capture session (stop recording first if needed).
    func stop() {
        viewWantsLive = false
        captureAuthorizationDeadlineTask?.cancel()
        captureAuthorizationDeadlineTask = nil
        suspend()
    }

    internal func suspend() {
        guard liveIsActive || isRecording || isFinalizingRecording else { return }
        liveIsActive = false
        isSessionRunning = false
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        lifecycleGeneration &+= 1
        motion.stop()
        simulatorTimer?.invalidate()
        simulatorTimer = nil
        capture.resetVisionTemporalState()
        invalidateDirectVisualSample()
        if let transaction = activeRecordingTransaction {
            beginRecordingBackgroundTask(for: transaction)
        }
        capture.stopAfterRecordingFinalizes()
    }

    internal func resumeIfDesired() {
        guard viewWantsLive, appIsActive, !captureIsInterrupted, !liveIsActive else { return }
        activateLive()
    }

    func retryCapture() {
        guard canRetryCapture, viewWantsLive, appIsActive, !captureIsInterrupted else { return }
        runtimeRecoveryAttempts = 0
        canRetryCapture = false
        suspend()
        resumeIfDesired()
    }

    /// Surfaces a synchronous recording-preparation failure beside the Live controls.
    func showRecordingPreparationError(_ message: String) {
        guard !isStartingRecording, !isRecording, !isFinalizingRecording else { return }
        recordStatusMessage = "Aufnahme konnte nicht vorbereitet werden: \(message)"
    }

    func markSpokenAudioCheckCompleted() {
        runtimeStatus.spokenAudioCheckCompleted = true
    }

    func invalidateSpokenAudioCheck() {
        runtimeStatus.spokenAudioCheckCompleted = false
    }

    /// Live/UI callers should invoke this whenever local collection/reflection authority changes.
    /// A revoked or expired authority stops an active take rather than merely disabling the next one.
    func enforceCaptureAuthorization(
        _ isAuthorized: Bool,
        transactionID: UUID? = nil,
        reason: String = "Lokale Freigabe ist nicht mehr aktiv - Aufnahme wird finalisiert."
    ) {
        guard !isAuthorized, let transaction = activeRecordingTransaction else { return }
        if let transactionID, transaction.transactionID != transactionID { return }
        requestRecordingStop(
            transaction: transaction,
            reason: reason
        )
    }

    /// Continuous classroom recording to a local movie file (Derry continuous take).
    /// - Parameters:
    ///   - url: Destination `.mp4`; the capture owner records to a temporary sibling first.
    ///   - allowDespiteWarnings: When true, start even if `readiness.canRecord` is false.
    ///   - readiness: Latest Setup+sensor gate from the Live view.
    @discardableResult
    func startRecording(_ request: RecordingStartRequest) -> Bool {
        guard canStartRecording(request) else { return false }
        let transaction = RecordingTransaction(
            sessionID: request.sessionID,
            transactionID: request.transactionID,
            generation: lifecycleGeneration
        )
        prepareRecordingStart(transaction, request: request)
        capture.startRecording(
            CaptureSessionController.RecordingStartRequest(
                destinationURL: request.url,
                stagedURL: request.stagedURL,
                transaction: transaction,
                artifacts: request.artifacts
            )
        )
        return true
    }

    private func canStartRecording(_ request: RecordingStartRequest) -> Bool {
        guard hasValidRecordingReadiness(request) else { return false }
        if usingSimulatorFallback {
            recordStatusMessage = "Demo-Modus zeigt Vorschau, erzeugt aber keine Medienaufnahme."
            return false
        }
        guard captureSessionIsReadyForRecording() else {
            recordStatusMessage = "Capture-Session nicht bereit oder Aufnahme wird finalisiert."
            return false
        }
        return true
    }

    private func hasValidRecordingReadiness(_ request: RecordingStartRequest) -> Bool {
        guard !requiresFreshLiveSample else {
            recordStatusMessage = "Aufnahme blockiert: aktuelles direktes Bildsignal fehlt noch."
            return false
        }
        if !request.readiness.canOverrideQualityWarnings {
            recordStatusMessage = "Aufnahme blockiert: aktiver lokaler Freigabedatensatz fehlt."
            return false
        }
        if !request.readiness.canRecord, !request.allowDespiteWarnings {
            recordStatusMessage = "Aufnahme blockiert: \(request.readiness.summaryDE)"
            return false
        }
        return true
    }

    /// A fresh capture generation must not inherit a prior preview's direct visual evidence.
    /// `currentFrame` is an internal readiness marker, replaced only by a generation-matched
    /// frame event in `handleFrame`.
    internal func invalidateDirectVisualSample() {
        requiresFreshLiveSample = true
        privacyCoverIsVisible = true
        frameMetrics = FrameMetrics()
        cvFeatures = .empty
        var values = GuidanceResult.Values(tips: [], placement: .assess(.init(
            orientation: OrientationSample(pitchDegrees: 0, rollDegrees: 0),
            frame: frameMetrics
        )))
        values.observability = CaptureObservabilityAssessment(dimensions: [
            CaptureObservabilityDimension(.init(
                id: "currentFrame",
                labelDE: "Aktuelles Bildsignal",
                status: .unavailable
            ))
        ])
        guidance = GuidanceResult(values)
    }

    private func captureSessionIsReadyForRecording() -> Bool {
        [
            liveIsActive,
            isSessionRunning,
            !isStartingRecording,
            !isRecording,
            !isFinalizingRecording
        ].allSatisfy { $0 }
    }

    private func prepareRecordingStart(_ transaction: RecordingTransaction, request: RecordingStartRequest) {
        activeRecordingTransaction = transaction
        lastPersistedObservationAt = 0
        lastPersistedSnapshotAt = 0
        stopRequestedDuringStart = false
        isStartingRecording = true
        // `isRecording` becomes true exclusively in the AVFoundation didStart delegate event.
        isRecording = false
        isFinalizingRecording = false
        recordStatusMessage = request.allowDespiteWarnings && !request.readiness.canRecord
            ? "Aufnahme wird gestartet (trotz unvollständiger Readiness)"
            : "Kontinuierliche Aufnahme wird gestartet"
        armStartAcknowledgementWatchdog(for: transaction)
    }

    /// Simulator previews are intentionally non-recording; reject before callers create recording metadata.
    func rejectSimulatorRecordingAttempt() {
        guard usingSimulatorFallback else { return }
        recordStatusMessage = "Demo-Modus zeigt Vorschau, erzeugt aber keine Medienaufnahme."
    }

    /// End the continuous take; file finalize is handled by the movie-output delegate.
    func stopRecording() {
        if usingSimulatorFallback {
            isRecording = false
            recordStatusMessage = "Demo-Aufnahme beendet"
            return
        }
        guard let transaction = activeRecordingTransaction else { return }
        requestRecordingStop(transaction: transaction, reason: "Stopp angefordert.")
    }

    private func requestRecordingStop(transaction: RecordingTransaction, reason: String) {
        guard activeRecordingTransaction == transaction, !isFinalizingRecording else { return }
        persistCaptureObservation(from: guidance, force: true, kind: .transition, note: reason)
        if isStartingRecording {
            stopRequestedDuringStart = true
            recordStatusMessage = "Stopp nach Startbestätigung wird angefordert…"
        } else if isRecording {
            isFinalizingRecording = true
            recordStatusMessage = "Aufnahme wird finalisiert…"
        } else {
            return
        }
        capture.requestStop(transaction: transaction, reason: reason)
    }
}
