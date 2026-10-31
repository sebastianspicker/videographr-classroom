import Combine
import Foundation
import GuidanceEngine
import SessionCore
import SwiftUI
import UIKit

/// App-wide active capture session and asynchronous local persistence.
@MainActor
final class AppStore: ObservableObject {
    enum BootstrapState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    enum BootstrapMode {
        case automatic
        case deferred
    }

    enum SaveState: Equatable {
        case saved
        case unsaved
        case saving
        case failed(String)

        var titleDE: String {
            switch self {
            case .saved: return "Gespeichert"
            case .unsaved: return "Ungespeicherte Änderungen"
            case .saving: return "Speichert…"
            case let .failed(message): return "Speicherfehler: \(message)"
            }
        }
    }

    struct PreparedRecording: Sendable {
        let sessionID: UUID
        let transactionID: UUID
        let mediaAssetID: UUID
        let url: URL
        let stagedURL: URL
        let authorization: CaptureAuthorizationSnapshot
        let plannedDurationMinutes: Int
    }

    struct PreparedExport: Identifiable, Equatable, Sendable {
        let id: UUID
        let sessionID: UUID
        let packageURL: URL
    }

    struct RecordingPreparation {
        let transactionID: UUID
        let readiness: SessionReadiness
        let overrideReason: String
        let operatorPseudonym: String
        let runtimeStatus: CaptureRuntimeStatus
    }

    @Published private(set) var session: CaptureSession
    @Published var allSessions: [CaptureSession] = []
    @Published var saveState: SaveState = .saved
    @Published var studyPackageURL: URL?
    @Published var lastStoreError: String?
    @Published private(set) var bootstrapState: BootstrapState = .loading
    @Published private(set) var mediaURLs: [UUID: URL] = [:]

    let store: SessionStore
    /// The narrow persistence capability handed to the capture boundary for recording artifacts.
    var recordingArtifacts: any RecordingArtifactSecuring { store }
    let readiness = ReadinessAggregator()

    let asyncStore: any SessionRepository
    let mediaInspector = MediaInspector()
    let packageWriter = StudyPackageWriter()
    var autosaveTask: Task<Void, Never>?
    var bootstrapTask: Task<Void, Never>?
    var bootstrapIsRunning = false
    var editRevision = 0
    var savedRevision = 0
    var activeSessionGeneration = 0
    var persistenceOperationSequence = 0
    var latestAppliedPersistenceOperation = 0
    var persistenceWillStoreHook: (@MainActor @Sendable (Int) async throws -> Void)?
    var persistenceDidStoreHook: (@MainActor @Sendable (Int) async -> Void)?
    var mediaResolutionSignature: [UUID: String] = [:]
    /// Takes prepared in this process; only takes from an earlier process count as interrupted.
    var recordingTransactionsOfThisLaunch: Set<UUID> = []

    init(store: SessionStore? = nil, bootstrapMode: BootstrapMode = .automatic) {
        let store = store ?? Self.defaultStore()
        self.store = store
        self.asyncStore = SessionStoreAsync(store: store)
        self.session = Self.makeSession(buildProvenance: BuildProvenanceFactory.capture(for: .evidenceSafe))
        if session.buildProvenance == nil, session.takeManifests.isEmpty {
            session.buildProvenance = BuildProvenanceFactory.capture(for: session.operatingMode)
        }
        if case .automatic = bootstrapMode {
            bootstrapTask = Task { [weak self] in
                await self?.bootstrap()
            }
        }
    }

    deinit {
        autosaveTask?.cancel()
        bootstrapTask?.cancel()
    }

    func bootstrap() async {
        guard !bootstrapIsRunning else { return }
        bootstrapIsRunning = true
        bootstrapState = .loading
        lastStoreError = nil
        defer { bootstrapIsRunning = false }
        do {
            async let packageReconciliation: Void = packageWriter.reconcileStartupArtifacts()
            let result = try await asyncStore.bootstrapPersistence()
            await packageReconciliation
            var recovered = result.activeSession
                ?? Self.makeSession(buildProvenance: BuildProvenanceFactory.capture(for: .evidenceSafe))
            if recovered.buildProvenance == nil, recovered.takeManifests.isEmpty {
                recovered.buildProvenance = BuildProvenanceFactory.capture(for: recovered.operatingMode)
            }
            session = recovered
            activeSessionGeneration &+= 1
            allSessions = result.listing.sessions
            editRevision = 0
            savedRevision = 0
            saveState = .saved
            applyListingDiagnostics(result.listing)
            applyReconciliationStatus(result.recordingReconciliation)
            applyPersistenceReconciliationStatus(result.persistenceReconciliation)
            await refreshMediaURLs()
            bootstrapState = .ready
        } catch {
            let message = error.localizedDescription
            bootstrapState = .failed(message)
            lastStoreError = message
        }
    }

    var persistenceIsReady: Bool { bootstrapState == .ready }

    func replaceMediaURLs(_ resolved: [UUID: URL]) {
        mediaURLs = resolved
    }

    func cacheMediaURL(_ url: URL, for assetID: UUID, in resolvedSession: CaptureSession) {
        mediaURLs[assetID] = url
        mediaResolutionSignature = mediaSignature(for: resolvedSession)
    }

    func mediaSignature(for candidate: CaptureSession) -> [UUID: String] {
        candidate.mediaAssets.reduce(into: [:]) { signature, asset in
            signature[asset.id] = asset.relativePath
        }
    }

    /// The only edit path for the active draft: applies the mutation, then marks it dirty.
    func edit(_ mutate: (inout CaptureSession) -> Void) {
        mutate(&session)
        markDirty()
    }

    /// Swaps in a hydrated, loaded or persisted session without marking it dirty.
    func replaceSession(_ session: CaptureSession) {
        self.session = session
    }

    /// A form binding whose writes go through `edit(_:)`.
    func binding<Value>(_ keyPath: WritableKeyPath<CaptureSession, Value>) -> Binding<Value> {
        Binding(
            get: { self.session[keyPath: keyPath] },
            set: { value in self.edit { $0[keyPath: keyPath] = value } }
        )
    }

    /// Marks the active draft dirty and coalesces edits into one background save.
    func markDirty() {
        guard persistenceIsReady else { return }
        session.updatedAt = Date()
        editRevision &+= 1
        saveState = .unsaved
        studyPackageURL = nil
        invalidateCachedPackages(for: session.id)
        scheduleAutosave(delayNanoseconds: 650_000_000)
    }

    /// Immediately schedules persistence for the current setup form.
    func save() {
        guard persistenceIsReady else { return }
        if savedRevision == editRevision { markDirty() }
        scheduleAutosave(delayNanoseconds: 0)
    }

    @discardableResult
    func flushPendingChanges() async -> Bool {
        guard persistenceIsReady else { return false }
        let pendingAutosave = autosaveTask
        pendingAutosave?.cancel()
        autosaveTask = nil
        if let pendingAutosave {
            await pendingAutosave.value
        }
        while savedRevision < editRevision {
            let revision = editRevision
            guard await persistCurrentSession(
                revision: revision,
                generation: activeSessionGeneration
            ) else { return false }
        }
        return true
    }

    /// Replaces active scoped grants while retaining withdrawn records for auditability.
    func updateConsentGrant(_ draft: ConsentGrantDraft) {
        guard persistenceIsReady else { return }
        edit { $0.replaceConsentGrants(with: draft, at: Date()) }
        scheduleAutosave(delayNanoseconds: 0)
    }

    func activateExperimentalMode(protocol reference: ResearchProtocolReference) {
        edit { $0.activateExperimentalMode(protocol: reference) }
    }

    func returnToEvidenceSafe() {
        edit { $0.returnToEvidenceSafe() }
    }

    func removeAnnotation(id: EvidenceAnnotation.ID) {
        edit { $0.removeAnnotation(id: id) }
    }

    /// Resolves a protected media file without exposing the repository to views.
    func resolvedMediaURL(for asset: SessionMediaAsset, sessionID: UUID) async -> URL? {
        try? await asyncStore.validatedMediaURL(for: asset, sessionID: sessionID)
    }

    func newSession() {
        guard persistenceIsReady else { return }
        Task { [weak self] in
            guard let self, await self.flushPendingChanges() else { return }
            self.session = Self.makeSession(buildProvenance: BuildProvenanceFactory.capture(for: .evidenceSafe))
            self.activeSessionGeneration &+= 1
            self.replaceMediaURLs([:])
            self.mediaResolutionSignature = [:]
            self.studyPackageURL = nil
            self.markDirty()
            _ = await self.flushPendingChanges()
        }
    }

    func select(_ id: UUID) {
        guard persistenceIsReady else { return }
        Task { [weak self] in
            guard let self, await self.flushPendingChanges() else { return }
            do {
                guard var loaded = try await self.asyncStore.load(id: id) else {
                    self.lastStoreError = "Die ausgewählte Sitzung wurde nicht gefunden."
                    return
                }
                if loaded.buildProvenance == nil, loaded.takeManifests.isEmpty {
                    loaded.buildProvenance = BuildProvenanceFactory.capture(for: loaded.operatingMode)
                }
                self.session = loaded
                self.activeSessionGeneration &+= 1
                self.editRevision = 0
                self.savedRevision = 0
                self.saveState = .saved
                self.lastStoreError = nil
                await self.refreshMediaURLs()
                self.studyPackageURL = nil
            } catch {
                self.lastStoreError = error.localizedDescription
            }
        }
    }

    func evaluateReadiness(visual: GuidanceResult, audio: AudioLevelSample) -> SessionReadiness {
        readiness.evaluate(session: session, visual: visual, audioSample: audio)
    }

}
