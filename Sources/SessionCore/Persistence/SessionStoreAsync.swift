import Foundation

public struct SessionPersistenceBootstrap: Sendable {
    public let recordingReconciliation: RecordingArtifactReconciliationReport
    public let persistenceReconciliation: PersistenceArtifactReconciliationReport
    public let listing: SessionStoreListing
    public let activeSession: CaptureSession?

    public init(
        recordingReconciliation: RecordingArtifactReconciliationReport,
        persistenceReconciliation: PersistenceArtifactReconciliationReport,
        listing: SessionStoreListing,
        activeSession: CaptureSession?
    ) {
        self.recordingReconciliation = recordingReconciliation
        self.persistenceReconciliation = persistenceReconciliation
        self.listing = listing
        self.activeSession = activeSession
    }
}

/// Actor-isolated facade for callers that must not perform storage work from the main actor.
public actor SessionStoreAsync {
    private let store: SessionStore
    /// A late autosave of a session deleted in this launch must not write it back.
    private var deletedSessionIDs: Set<UUID> = []

    public init(store: SessionStore) { self.store = store }
    public func bootstrapPersistence() throws -> SessionPersistenceBootstrap {
        // Import cleanup first: its marker shares the staging prefix and would raise false recording warnings.
        let persistenceReconciliation = try store.reconcilePersistenceArtifacts()
        let recordingReconciliation = try store.reconcileRecordingArtifacts()
        try reconcileInterruptedSessionMetadata()
        let listing = try store.listSessionsWithDiagnostics()
        // A damaged journal must not block the app; the session still opens from its metadata.
        let activeSession = try listing.sessions.first.flatMap {
            try (try? store.load(id: $0.id)) ?? store.loadMetadataOnly(id: $0.id)
        }
        return SessionPersistenceBootstrap(
            recordingReconciliation: recordingReconciliation,
            persistenceReconciliation: persistenceReconciliation,
            listing: listing,
            activeSession: activeSession
        )
    }
    public func save(_ session: CaptureSession) throws { try store.save(session) }
    public func load(id: UUID) throws -> CaptureSession? { try store.load(id: id) }
    public func listSessionSummariesWithDiagnostics() throws -> SessionStoreListing {
        try store.listSessionsWithDiagnostics()
    }
    public func deleteSessionAndMedia(id: UUID) throws {
        try store.deleteSessionAndMedia(id: id)
        deletedSessionIDs.insert(id)
    }
    public func prepareRecordingURL(for session: CaptureSession) throws -> URL {
        try store.prepareRecordingURL(for: session)
    }
    public func prepareStagedRecordingURL(for sessionID: UUID, transactionID: UUID) throws -> URL {
        try store.prepareStagedRecordingURL(for: sessionID, transactionID: transactionID)
    }
    public func discardStagedRecording(at url: URL) throws { try store.discardStagedRecording(at: url) }
    public func interruptedTakeURL(sessionID: UUID, transactionID: UUID) throws -> URL? {
        try store.interruptedTakeURL(sessionID: sessionID, transactionID: transactionID)
    }
    public func promoteInterruptedTake(sessionID: UUID, transactionID: UUID) throws -> URL {
        try store.promoteInterruptedTake(sessionID: sessionID, transactionID: transactionID)
    }
    public func demoteInterruptedTake(sessionID: UUID, transactionID: UUID) throws {
        try store.demoteInterruptedTake(sessionID: sessionID, transactionID: transactionID)
    }
    public func secureFinalizedRecording(at url: URL) throws { try store.secureFinalizedRecording(at: url) }
    public func validatedMediaURL(for asset: SessionMediaAsset, sessionID: UUID) throws -> URL {
        try store.validatedMediaURL(for: asset, sessionID: sessionID)
    }
    public func importMedia(from sourceURL: URL, into sessionID: UUID) async throws -> SessionMediaAsset {
        let importTask = Task.detached(priority: .utility) { [store] in
            try store.importMedia(from: sourceURL, into: sessionID)
        }
        return try await withTaskCancellationHandler {
            try await importTask.value
        } onCancel: {
            importTask.cancel()
        }
    }
    public func commitImportedMedia(_ asset: SessionMediaAsset, toSession sessionID: UUID) throws {
        try store.commitImportedMedia(asset, toSession: sessionID)
    }
    public func reconcilePersistenceArtifacts() throws -> PersistenceArtifactReconciliationReport {
        try store.reconcilePersistenceArtifacts()
    }
    public func discardUncommittedImportedMedia(_ asset: SessionMediaAsset, from sessionID: UUID) throws {
        try store.discardUncommittedImportedMedia(asset, from: sessionID)
    }
    public func appendCodingSnapshot(_ snapshot: ResearchCodingSnapshot, toSession id: UUID) throws {
        try store.appendCodingSnapshot(snapshot, toSession: id)
    }
    @discardableResult
    public func appendCaptureObservationIfAuthorized(
        _ observation: CaptureObservation,
        toSession id: UUID,
        at date: Date = Date()
    ) throws -> Bool {
        try store.appendCaptureObservationIfAuthorized(observation, toSession: id, at: date)
    }
    public func loadCaptureObservations(forSession id: UUID) throws -> [CaptureObservation] {
        try store.loadCaptureObservations(forSession: id)
    }

    /// Executes one read-modify-write transaction without an actor reentrancy point.
    @discardableResult
    public func mutateSession(
        id: UUID,
        includeJournals: Bool = false,
        _ mutation: @Sendable (inout CaptureSession) throws -> Void
    ) throws -> CaptureSession {
        let loaded = includeJournals ? try store.load(id: id) : try store.loadMetadataOnly(id: id)
        guard var session = loaded else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "Session \(id.uuidString) wurde nicht gefunden."
            ])
        }
        try mutation(&session)
        try store.save(session)
        return includeJournals
            ? (try store.load(id: id) ?? session)
            : (try store.loadMetadataOnly(id: id) ?? session)
    }

    /// Persists only interactive draft fields, preserving runtime-owned take, media, journal,
    /// provenance, and disclosure state written by concurrent capture operations.
    @discardableResult
    public func mergeDraftSession(_ draft: CaptureSession) throws -> CaptureSession {
        guard var current = try store.loadMetadataOnly(id: draft.id) else {
            guard !deletedSessionIDs.contains(draft.id) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [
                    NSLocalizedDescriptionKey: "Session \(draft.id.uuidString) wurde gelöscht."
                ])
            }
            try store.save(draft)
            return try store.loadMetadataOnly(id: draft.id) ?? draft
        }
        current.mergeDraftFields(from: draft)
        try store.save(current)
        return try store.loadMetadataOnly(id: draft.id) ?? current
    }

    private func reconcileInterruptedSessionMetadata() throws {
        for var candidate in try store.listSessionsWithDiagnostics().sessions {
            let closedAt = Date()
            let canonicalAssetIDs = Set(candidate.mediaAssets.compactMap { asset -> UUID? in
                guard let url = try? store.validatedMediaURL(for: asset, sessionID: candidate.id),
                      FileManager.default.fileExists(atPath: url.path)
                else { return nil }
                return asset.id
            })
            let preservedTakeIDs = Set(candidate.takeManifests.compactMap { manifest -> UUID? in
                (try? store.interruptedTakeURL(sessionID: candidate.id, transactionID: manifest.id)) != nil
                    ? manifest.id : nil
            })
            var changed = candidate.failAbandonedTakes(
                canonicalMediaAssetIDs: canonicalAssetIDs,
                preservedTakeIDs: preservedTakeIDs,
                at: closedAt
            ) > 0
            for index in candidate.exportEvents.indices
                where candidate.exportEvents[index].status == .attempted
            {
                candidate.exportEvents[index].finish(
                    status: .outcomeUnknown,
                    shareActivityIdentifier: "unknown-after-relaunch",
                    failureDescription: "App wurde beendet, bevor der Systemdialog einen Abschlussstatus liefern konnte."
                )
                changed = true
            }
            // One unsavable session must not block the app; the repair is retried on the next launch.
            if changed { try? store.save(candidate) }
        }
    }
}
