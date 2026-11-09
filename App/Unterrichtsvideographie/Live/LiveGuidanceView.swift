@preconcurrency import AVFoundation
import SwiftUI
import GuidanceEngine
import SessionCore

/// Live filming surface: camera preview, readiness, prioritized tips, scene/coding panel, record controls.
///
/// Presents the environment-injected `LiveStore` with `FilmingGuidancePolicy`.
/// so continuous classroom takes keep mid-take critical signals without freezing guidance at pre-roll.
struct LiveGuidanceView: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var liveStore: LiveStore
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject var audioCheck = SpokenAudioCheckModel()
    /// User override to start recording despite non-critical readiness blockers (research ops).
    @State var forceRecord = false
    @State var overrideReason = ""
    @State var operatorPseudonym = ""
    @State var inspectorIsVisible = false
    /// This is set only after the capture owner reports an active take. It is
    /// presentation state, never an input to the recording transaction.
    @State var recordingStartedAt: Date?

    let filmingPolicy = FilmingGuidancePolicy()
    let onExit: () -> Void

    init(onExit: @escaping () -> Void = {}) {
        self.onExit = onExit
    }

    /// Setup + visual + audio gate for the red record button.
    var readiness: SessionReadiness {
        appStore.evaluateReadiness(visual: liveStore.guidance, audio: liveStore.audioSample)
    }

    /// Live pre-roll + mid-take guidance (always re-evaluated from sensors).
    var filming: FilmingGuidanceSnapshot {
        filmingPolicy.evaluate(
            visual: liveStore.guidance,
            audioSample: liveStore.audioSample,
            isRecording: liveStore.isRecording
        )
    }

    var requiresOverride: Bool {
        !readiness.canRecord
            || liveStore.runtimeStatus.hasResourceWarning
            || !liveStore.runtimeStatus.spokenAudioCheckCompleted
    }

    var overrideIsValid: Bool {
        !requiresOverride || (forceRecord && !overrideReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        GeometryReader { geo in
            let isWide = geo.size.width >= 900 && geo.size.width > geo.size.height
                && !dynamicTypeSize.isAccessibilitySize
            VStack(spacing: 0) {
                liveToolbar
                ScrollView {
                    liveStage(previewHeight: isWide
                        ? max(220, min((geo.size.width - 32) * 9 / 16, geo.size.height - 335))
                        : (geo.size.width - 32) * 9 / 16)
                }
            }
            .sheet(isPresented: $inspectorIsVisible) {
                inspectorPane
                    .presentationDetents([.large])
            }
            .roomSurface()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: inspectorIsVisible)
            // System tab bar is replaced by DestinationBar in RootTabView.
            .toolbar(.hidden, for: .tabBar)
            .onAppear {
                if liveStore.isRecording { recordingStartedAt = Date() }
                operatorPseudonym = appStore.session.consentGrants
                    .last(where: { $0.authorizes(.collection) })?
                    .participantGroupPseudonym ?? ""
                liveStore.synchronizeSession()
                liveStore.start()
            }
            .onChange(of: appStore.session.teachingSituation) { _, newValue in
                liveStore.teachingSituation = newValue
            }
            .onChange(of: appStore.session.analysisIntent) { _, newValue in
                liveStore.analysisFocus = newValue
            }
            .onChange(of: appStore.session.operatingMode) { _, _ in
                forceRecord = false
                overrideReason = ""
                liveStore.synchronizeSession()
            }
            .onChange(of: appStore.session.experimentalProtocol) { _, _ in
                liveStore.synchronizeSession()
            }
            .onChange(of: appStore.session.consentGrants) { _, _ in
                audioCheck.invalidateIfUnauthorized(for: appStore.session)
                liveStore.synchronizeSession()
            }
            .onChange(of: liveStore.isRecording) { _, isRecording in
                recordingStartedAt = isRecording ? Date() : nil
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    liveStore.synchronizeSession()
                    audioCheck.resumeAfterInactivity()
                } else {
                    audioCheck.cancelForInactivity()
                }
            }
            .onChange(of: appStore.session.id) { _, _ in
                forceRecord = false
                overrideReason = ""
                audioCheck.cancel(resumeCapture: false)
                liveStore.synchronizeSession()
                operatorPseudonym = appStore.session.consentGrants
                    .last(where: { $0.authorizes(.collection) })?
                    .participantGroupPseudonym ?? ""
            }
            .onDisappear {
                audioCheck.cancel(resumeCapture: false)
                liveStore.stop()
            }
        }
    }

    /// Compact format chip for provenance. Never imply a negotiated capture fact
    /// before AVFoundation has supplied one.
    var liveFormatLabel: String {
        let configuration = liveStore.runtimeStatus.videoConfiguration
        if configuration.isEmpty || configuration == "Noch nicht ausgehandelt" {
            return "Nicht ausgehandelt"
        }
        return configuration
    }
}

extension LiveGuidanceView {
    @MainActor
    func beginRecording() {
        Task {
            await liveStore.beginRecording(
                readiness: readiness,
                allowDespiteWarnings: requiresOverride && forceRecord,
                overrideReason: overrideReason,
                operatorPseudonym: operatorPseudonym
            )
            forceRecord = false
            overrideReason = ""
        }
    }

    func formatCapacity(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview {
    let appStore = AppStore()
    LiveGuidanceView()
        .environmentObject(appStore)
        .environmentObject(LiveStore(appStore: appStore))
}
