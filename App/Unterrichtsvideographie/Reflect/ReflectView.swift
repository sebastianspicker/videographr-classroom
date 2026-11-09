import AVKit
import ExperimentalResearch
import Foundation
import SessionCore
import SwiftUI
import UniformTypeIdentifiers

enum ReflectionSection: Equatable {
    case notes
    case metadata
}

enum ReflectionAnnotationField: Hashable {
    case author
    case note
    case start
    case end
}

/// Post-take reflection grounded in user-linked media evidence.
/// The page reads as a transcript: the player, the person's notes in
/// Königsblau, and timecodes in the margin.
struct ReflectView: View {
    @EnvironmentObject var appStore: AppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.scenePhase) var scenePhase

    @State var selectedAssetID: UUID?
    @State var playback = ReflectionPlaybackModel()
    @State var gaussianRequest: GaussianFrameRequest?
    @State var gaussianLaunchMessage: String?
    @State var gaussianLaunchID: UUID?
    @State var mediaAvailability: [UUID: URL] = [:]
    @State var isCheckingMedia = true
    @State var rangeStartMilliseconds: Int64?
    @State var isImportingMedia = false
    @State var isProcessingMediaImport = false
    @State var preparedExport: AppStore.PreparedExport?
    @State var pendingExportOutcome: AppStore.PreparedExport?
    @State var exportOutcomeCoordinator: ExportOutcomeCoordinator?
    @State var isPreparingExport = false
    @State var focusedPrompt: ReflectionPromptID = .studentLearningEvidence
    @State var annotationAuthor = ""
    @State var annotationStartTimecode = ""
    @State var annotationEndTimecode = ""
    @State var annotationEditorMessage: String?
    @State var isSavingAnnotation = false
    @State var interruptedTakeIDs: [UUID] = []
    @State var interruptedTakeMessage: String?
    @State var isResolvingInterruptedTake = false
    @State var interruptedTakePendingDiscard: UUID?
    @FocusState var annotationFocus: ReflectionAnnotationField?
    let onEditSession: () -> Void
    let initialSection: ReflectionSection
    let isReflectionSelected: @MainActor () -> Bool

    init(
        playback: ReflectionPlaybackModel = ReflectionPlaybackModel(),
        onEditSession: @escaping () -> Void = {},
        initialSection: ReflectionSection = .notes,
        isReflectionSelected: @escaping @MainActor () -> Bool = { true }
    ) {
        _playback = State(initialValue: playback)
        self.onEditSession = onEditSession
        self.initialSection = initialSection
        self.isReflectionSelected = isReflectionSelected
    }

    var selectedAsset: SessionMediaAsset? {
        let assets = appStore.session.mediaAssets
        guard !assets.isEmpty else { return nil }
        return assets.first(where: { $0.id == selectedAssetID }) ?? assets.first
    }

    var selectedMediaURL: URL? {
        guard let selectedAsset else { return nil }
        return mediaAvailability[selectedAsset.id]
    }

    var hasPlayableSelectedMedia: Bool {
        selectedMediaURL != nil
    }

    var activeGrantCount: Int {
        appStore.session.consentGrants.filter { grant in
            ConsentScope.allCases.contains { grant.authorizes($0) }
        }.count
    }

    var body: some View {
        let index = ReflectionAnnotationIndex(appStore.session.evidenceAnnotations)
        NavigationStack {
            Group {
                if initialSection == .metadata {
                    metadataReview
                } else {
                    VStack(spacing: 0) {
                        GeometryReader { geo in
                            let wide = geo.size.width >= 700 && !dynamicTypeSize.isAccessibilitySize
                            ScrollView {
                                VStack(alignment: .leading, spacing: Space.xl) {
                                    VStack(alignment: .leading, spacing: Space.s) {
                                        reflectionStatusHeader(index: index)
                                        reflectionContextLine
                                    }
                                    if let error = appStore.lastStoreError {
                                        StatusMark(error, kind: .fault, prominent: true)
                                            .accessibilityIdentifier("reflect.operationError")
                                    }
                                    if wide {
                                        HStack(alignment: .top, spacing: Space.xxl) {
                                            playerColumn
                                                .frame(maxWidth: .infinity)
                                            notesColumn(index: index)
                                                .frame(width: min(400, geo.size.width * 0.42))
                                        }
                                    } else {
                                        VStack(alignment: .leading, spacing: Space.xxl) {
                                            playerColumn
                                            notesColumn(index: index)
                                        }
                                    }
                                    reflectionSupportingSections(index: index)
                                }
                                .padding(.horizontal, pageGutter)
                                .padding(.top, Space.xl)
                                .padding(.bottom, Space.xxl)
                                .frame(maxWidth: Space.pageMaximum, alignment: .leading)
                                .frame(maxWidth: .infinity)
                            }
                            .scrollDismissesKeyboard(.immediately)
                            .accessibilityIdentifier("reflect.scroll")
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                }
            }
            .paperSurface()
            .task(id: ReflectionMediaRequest(sessionID: appStore.session.id, assets: appStore.session.mediaAssets)) {
                await refreshMediaAvailability()
            }
            .onChange(of: appStore.session.id) { _, _ in interruptedTakeMessage = nil }
            .task(id: appStore.session.takeManifests.map { "\($0.id)-\($0.effectiveLifecycleState)" }) {
                interruptedTakeIDs = await appStore.pendingInterruptedTakeIDs()
            }
            .task(id: selectedMediaURL) {
                rangeStartMilliseconds = nil
                playback.configure(url: selectedMediaURL)
                populateAnnotationEditorFromPlayback()
            }
            .task(id: gaussianLaunchID) {
                guard let token = gaussianLaunchID else { return }
                await beginGaussianExploration(token: token)
            }
            .onChange(of: selectedAssetID) { _, _ in
                clearAnnotationEditorMessage()
            }
            .onChange(of: focusedPrompt) { _, _ in
                clearAnnotationEditorMessage()
            }
            .onChange(of: annotationAuthor) { _, _ in
                clearAnnotationEditorMessage()
            }
            .onChange(of: annotationStartTimecode) { _, _ in
                clearAnnotationEditorMessage()
            }
            .onChange(of: annotationEndTimecode) { _, _ in
                clearAnnotationEditorMessage()
            }
            .fileImporter(
                isPresented: $isImportingMedia,
                allowedContentTypes: [.mpeg4Movie],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    guard let url = urls.first else { return }
                    isProcessingMediaImport = true
                    Task {
                        await appStore.importMedia(from: url)
                        isProcessingMediaImport = false
                    }
                case let .failure(error):
                    appStore.lastStoreError = "Video konnte nicht ausgewählt werden: \(error.localizedDescription)"
                }
            }
            .sheet(item: $preparedExport, onDismiss: recordCancelledExportIfNeeded) { prepared in
                SystemShareSheet(items: [prepared.packageURL]) { completed, activityIdentifier, failure in
                    recordActivityExportOutcome(
                        prepared,
                        completed: completed,
                        shareActivityIdentifier: activityIdentifier,
                        failureDescription: failure
                    )
                }
            }
            .sheet(item: $gaussianRequest) { request in
                GaussianExplorationSheet(request: request) {
                    isReflectionSelected()
                        && appStore.session.id == request.sessionID
                        && selectedAsset?.id == request.assetID
                        && selectedMediaURL == request.mediaURL
                        && playback.matchesPausedFrame(url: request.mediaURL, time: request.time)
                }
                .id(request.id)
                .environmentObject(appStore)
                .presentationCompactAdaptation(.none)
            }
            .onDisappear {
                gaussianLaunchID = nil
                // A covering sheet must not invalidate its own frozen player identity.
                if !isReflectionSelected() {
                    gaussianRequest = nil
                    playback.stop()
                } else if gaussianRequest == nil { playback.stop() }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") {
                        annotationFocus = nil
                    }
                }
            }
        }
    }

    var pageGutter: CGFloat {
        sizeClass == .regular ? Space.gutterRegular : Space.gutterCompact
    }

    private var sessionTitle: String {
        let title = appStore.session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Neue Sitzung" : title
    }

    private func reflectionStatusHeader(index: ReflectionAnnotationIndex) -> some View {
        DocumentHeader(
            eyebrow: "Notizen · \(sessionTitle)",
            title: hasFinalizedSelectedRecording ? "Aufnahme lokal gesichert" : "Video reflektieren"
        ) {
            if reflectionIsComplete(index: index) {
                StatusMark("Vollständig", kind: .secured)
            } else {
                StatusMark("Entwurf · \(index.linkedPromptCount) / 4 Fragen belegt", kind: .open)
            }
        }
    }

    private var hasFinalizedSelectedRecording: Bool {
        guard let asset = selectedAsset, asset.role == .ownRecorded else { return false }
        return appStore.session.takeManifests.contains {
            $0.mediaAssetID == asset.id && $0.effectiveLifecycleState == .finalized
        }
    }

    private var reflectionContextLine: some View {
        ViewThatFits(in: .horizontal) {
            Text("Nur lokal · \(operatingModeTitle) · \(activeGrantCount) Freigaben aktiv")
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Nur lokal")
                Text(operatingModeTitle)
                Text("\(activeGrantCount) Freigaben aktiv")
            }
        }
        .font(Typeface.labelSmall)
        .tracking(0.3)
        .foregroundStyle(Ink.tertiary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sitzung lokal. \(appStore.session.operatingMode == .evidenceSafe ? "Evidence-safe" : "Experimenteller") Modus. \(activeGrantCount) Freigaben aktiv.")
    }

    private var operatingModeTitle: String {
        appStore.session.operatingMode == .evidenceSafe ? "Evidence-safe" : "Experimentell"
    }

    private var reflectionContextDetails: some View {
        DisclosureGroup("Details zur lokalen Sitzung") {
            Text("Nur lokal, kein Cloud-Abgleich. Schema v\(appStore.session.schemaVersion) · \(BuildIdentity.current.displayVersion)")
                .font(Typeface.valueSmall)
                .foregroundStyle(Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Space.l)
        }
        .disclosureGroupStyle(InkDisclosureStyle())
        .accessibilityIdentifier("reflect.sessionDetails")
    }

    private func reflectionSupportingSections(index: ReflectionAnnotationIndex) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rule(strong: true)
            DisclosureGroup("Reflexionsstruktur") {
                lafColumn(index: index)
                    .padding(.bottom, Space.l)
            }
            .disclosureGroupStyle(InkDisclosureStyle())

            Rule()
            DisclosureGroup("Fortschritt und Entwurf") {
                reflectProgress(index: index)
                    .padding(.bottom, Space.l)
            }
            .disclosureGroupStyle(InkDisclosureStyle())

            Rule()
            reflectionContextDetails

            if appStore.session.operatingMode == .experimentalResearch,
               appStore.session.hasUsableExperimentalProtocol,
               appStore.session.latestCodingSnapshot != nil {
                Rule()
                DisclosureGroup("Experimentelle Hilfen · nicht validiert") {
                    experimentalHypotheses
                        .padding(.bottom, Space.l)
                }
                .disclosureGroupStyle(InkDisclosureStyle())
            }
            Rule()
        }
    }
}

#Preview {
    ReflectView().environmentObject(AppStore())
}

#Preview("Reflexion · Große Schrift") {
    ReflectView()
        .environmentObject(AppStore())
        .environment(\.dynamicTypeSize, .accessibility3)
}
