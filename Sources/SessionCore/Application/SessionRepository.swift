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

/// App-facing asynchronous persistence boundary for capture-session work.
///
/// The protocol intentionally mirrors the operations used by the application. It does not
/// reinterpret paths, bytes, or persistence errors; `SessionStoreAsync` remains the concrete
/// implementation of those storage semantics.
public protocol SessionRepository: Actor {
    func bootstrapPersistence() async throws -> SessionPersistenceBootstrap
    func load(id: UUID) async throws -> CaptureSession?
    func listSessionSummariesWithDiagnostics() async throws -> SessionStoreListing
    func deleteSessionAndMedia(id: UUID) async throws
    func prepareRecordingURL(for session: CaptureSession) async throws -> URL
    func prepareStagedRecordingURL(for sessionID: UUID, transactionID: UUID) async throws -> URL
    func discardStagedRecording(at url: URL) async throws
    /// The preserved staged media of an interrupted take, or nil when none exists.
    func interruptedTakeURL(sessionID: UUID, transactionID: UUID) async throws -> URL?
    /// Moves a preserved interrupted take to its session's canonical recording name.
    func promoteInterruptedTake(sessionID: UUID, transactionID: UUID) async throws -> URL
    /// Moves a promoted interrupted take back to staging after a failed attachment.
    func demoteInterruptedTake(sessionID: UUID, transactionID: UUID) async throws
    func secureFinalizedRecording(at url: URL) async throws
    func validatedMediaURL(for asset: SessionMediaAsset, sessionID: UUID) async throws -> URL
    func importMedia(from sourceURL: URL, into sessionID: UUID) async throws -> SessionMediaAsset
    func commitImportedMedia(_ asset: SessionMediaAsset, toSession sessionID: UUID) async throws
    func discardUncommittedImportedMedia(_ asset: SessionMediaAsset, from sessionID: UUID) async throws
    func appendCaptureObservationIfAuthorized(
        _ observation: CaptureObservation,
        toSession id: UUID,
        at date: Date
    ) async throws -> Bool
    func appendCodingSnapshot(_ snapshot: ResearchCodingSnapshot, toSession id: UUID) async throws
    func mutateSession(
        id: UUID,
        includeJournals: Bool,
        _ mutation: @Sendable (inout CaptureSession) throws -> Void
    ) async throws -> CaptureSession
    func mergeDraftSession(_ draft: CaptureSession) async throws -> CaptureSession
}

public extension SessionRepository {
    @discardableResult
    func mutateSession(
        id: UUID,
        _ mutation: @Sendable (inout CaptureSession) throws -> Void
    ) async throws -> CaptureSession {
        try await mutateSession(id: id, includeJournals: false, mutation)
    }
}
