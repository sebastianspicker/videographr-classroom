import Foundation
import ExperimentalResearch
import GuidanceEngine
import QuartzCore
import SessionCore

extension LiveStore {
    internal func configureAndStartSession(generation: Int) {
        guard liveIsActive, generation == lifecycleGeneration else { return }
        capture.start(
            generation: generation,
            teachingSituation: teachingSituation,
            rotationAngle: Self.rotationAngle()
        )
    }

    internal func startSimulatorFallback(reason: String, generation: Int) {
        guard liveIsActive, generation == lifecycleGeneration else { return }
#if targetEnvironment(simulator)
        prepareSimulatorFallback(reason: reason)

        scheduleSimulatorUpdates(generation: generation)
#else
        usingSimulatorFallback = false
        isSessionRunning = false
        lastError = reason
        canRetryCapture = true
        recordStatusMessage = "Kamera/Mikrofon nicht verfügbar. Berechtigungen und Hardware in Einstellungen prüfen."
#endif
    }

#if targetEnvironment(simulator)
    private func prepareSimulatorFallback(reason: String) {
        usingSimulatorFallback = true
        lastError = reason
        isSessionRunning = true
        simulatorTimer?.invalidate()
        simulatorTimer = nil
        simulatorTick = 0
        applySimulatorFrame(FrameAnalyzer.syntheticClassroom())
        cvFeatures = .fixtureClassroomPresent()
        audioSample = makeAudioSample { values in
            values.peakLevel = 0.28
            values.averageLevel = 0.2
            values.externalMicIndicated = true
        }
        requiresFreshLiveSample = false
        if appIsActive, !captureIsInterrupted { privacyCoverIsVisible = false }
        recomputeGuidanceForNewFrame()
    }

    private func scheduleSimulatorUpdates(generation: Int) {
        simulatorTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.liveIsActive, self.lifecycleGeneration == generation else { return }
                self.simulatorTick += 1
                self.applySimulatorTick(self.simulatorTick)
            }
        }
    }

    private func applySimulatorTick(_ tick: Int) {
        applySimulatorFrame(simulatorFrame(for: tick % 4))
        cvFeatures = simulatorFeatures(for: tick % 10)
        simAudioPhase = (simAudioPhase + 1) % 3
        audioSample = simulatorAudioSample(for: simAudioPhase)
        recomputeGuidanceForNewFrame()
    }

    private func applySimulatorFrame(_ synthetic: (buffer: [Double], width: Int, height: Int)) {
        frameMetrics = FrameAnalyzer().analyze(
            luminance: synthetic.buffer,
            width: synthetic.width,
            height: synthetic.height
        )
    }

    private func simulatorFrame(for phase: Int) -> (buffer: [Double], width: Int, height: Int) {
        var configuration = FrameAnalyzer.SyntheticClassroomConfiguration()
        switch phase {
        case 1:
            configuration.ceilingHeightFraction = 0.48
        case 2:
            configuration.windowSide = .left
            configuration.windowBrightness = 0.99
            configuration.baseLuminance = 0.32
        case 3:
            configuration.boardRect = (0.2, 0.12, 0.6, 0.25)
        default: break
        }
        return FrameAnalyzer.syntheticClassroom(configuration)
    }

    private func simulatorFeatures(for phase: Int) -> CVFeatures {
        let fixtures: [() -> CVFeatures] = [
            CVFeatures.fixtureEmptyRoom,
            CVFeatures.fixturePeopleNoBoard,
            CVFeatures.fixtureBoardNoPeople,
            CVFeatures.fixturePeopleOffZone,
            CVFeatures.fixtureGroupWork,
            CVFeatures.fixtureCircleDiscussion,
            CVFeatures.fixtureExperimentSpread,
            CVFeatures.fixtureSeatworkScattered,
            CVFeatures.fixtureTeacherDemonstration,
            CVFeatures.fixtureClassroomPresent
        ]
        return fixtures[min(max(phase, 0), fixtures.count - 1)]()
    }

    private func simulatorAudioSample(for phase: Int) -> AudioLevelSample {
        switch phase {
        case 0:
            return makeAudioSample { $0.peakLevel = 0.01; $0.averageLevel = 0.005 }
        case 1:
            return makeAudioSample { $0.peakLevel = 0.3; $0.averageLevel = 0.22; $0.externalMicIndicated = true }
        default:
            return makeAudioSample { $0.peakLevel = 0.5; $0.averageLevel = 0.35 }
        }
    }
#endif

    /// Re-run direct observability without advancing experimental temporal windows.
    internal func recomputeGuidance() {
        guard !requiresFreshLiveSample else { return }
        publishDirectGuidance(evaluateDirectGuidance())
    }

    /// A newly analyzed camera frame advances the optional research windows exactly once.
    internal func recomputeGuidanceForNewFrame() {
        guard !requiresFreshLiveSample else { return }
        let result = evaluateDirectGuidance()

        guard operatingMode == .experimentalResearch else {
            clearExperimentalOutput()
            publishDirectGuidance(result)
            return
        }

        let experimental = researchEngine.evaluate(
            observability: result,
            frame: frameMetrics,
            cv: cvFeatures,
            teachingSituation: teachingSituation,
            analysisFocus: analysisFocus,
            experimentalSignals: ExperimentalCaptureSignals(cv: cvFeatures)
        )
        publishExperimentalOutput(experimental)
        publishDirectGuidance(result)
    }

    private func evaluateDirectGuidance() -> GuidanceResult {
        var inputValues = GuidanceInput.Values(
            orientation: motion.orientation,
            frame: frameMetrics
        )
        inputValues.cv = cvFeatures
        inputValues.motion = motion.motionMetrics
        return engine.evaluate(GuidanceInput(inputValues))
    }

    private func publishExperimentalOutput(_ experimental: ExperimentalResearchResult) {
        // Temporal scene smoothing is experimental-only and never changes direct observability.
        let output = analysis.advance(
            with: experimental,
            analysisFocus: analysisFocus,
            provenance: BuildProvenanceFactory.researchArtifact
        )
        windowedCoding = output.coding
        experimentalResult = experimental
        if let transitions = output.recentTransitions { recentTransitions = transitions }
        latestCodingSnapshot = output.snapshot
        persistSnapshotIfNeeded(output.snapshot)
    }

    private func publishDirectGuidance(_ result: GuidanceResult) {
        persistCaptureObservation(from: result, force: false)
        guidance = result
    }

    internal func clearExperimentalOutput() {
        latestCodingSnapshot = nil
        windowedCoding = .empty()
        recentTransitions = []
        experimentalResult = nil
    }

    private func persistSnapshotIfNeeded(_ snapshot: ResearchCodingSnapshot) {
        guard isRecording, !isFinalizingRecording else { return }
        guard experimentalResult?.hypotheses.hypotheses.isEmpty == false else { return }
        let now = CACurrentMediaTime()
        guard now - lastPersistedSnapshotAt >= 5 else { return }
        guard let boundSessionID = activeBoundSessionID() else { return }
        lastPersistedSnapshotAt = now
        Task { await appStore.attachCodingSnapshot(snapshot, for: boundSessionID, recordingIsActive: true) }
    }

    private func activeBoundSessionID() -> UUID? {
        guard let transaction = activeRecordingTransaction else { return nil }
        guard let boundSessionID else { return nil }
        guard boundSessionID == transaction.sessionID else { return nil }
        return boundSessionID
    }

    internal func persistCaptureObservation(
        from result: GuidanceResult,
        force: Bool,
        kind: CaptureObservationKind = .periodic,
        note: String = CaptureObservation.directSignalsNote
    ) {
        guard let sessionID = captureObservationSessionID(from: result, force: force) else { return }
        guard observationPersistenceIsDue(force: force) else { return }
        var observationValues = CaptureObservation.Values()
        observationValues.kind = kind
        observationValues.measurements = CaptureObservation.directMeasurements(guidance: result, audio: audioSample)
        observationValues.missingReason = CaptureObservation.unavailableReason(guidance: result)
        observationValues.note = note
        let observation = CaptureObservation(observationValues)
        Task { await appStore.attachCaptureObservation(observation, for: sessionID) }
    }

    private func captureObservationSessionID(
        from result: GuidanceResult,
        force: Bool
    ) -> UUID? {
        guard force || isRecording else { return nil }
        guard !result.observability.dimensions.isEmpty else { return nil }
        return activeBoundSessionID()
    }

    private func observationPersistenceIsDue(force: Bool) -> Bool {
        let now = CACurrentMediaTime()
        guard force || now - lastPersistedObservationAt >= 5.0 else { return false }
        lastPersistedObservationAt = now
        return true
    }
}
