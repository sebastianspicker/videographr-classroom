import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A malformed session file is reported without hiding other readable sessions.
public struct SessionStoreFileFailure: Equatable, Sendable {
    public let fileName: String
    public let errorDescription: String

    public init(fileName: String, errorDescription: String) {
        self.fileName = fileName
        self.errorDescription = errorDescription
    }
}

/// Result of a best-effort session listing. Directory access failures still throw.
public struct SessionStoreListing: Sendable {
    public let sessions: [CaptureSession]
    public let failures: [SessionStoreFileFailure]

    public init(sessions: [CaptureSession], failures: [SessionStoreFileFailure]) {
        self.sessions = sessions
        self.failures = failures
    }
}

/// A recording artifact that reconciliation deliberately left in place.
public struct RecordingArtifactDiagnostic: Equatable, Hashable, Sendable {
    public let fileName: String
    public let reason: RecordingArtifactDiagnosticReason

    public init(fileName: String, reason: RecordingArtifactDiagnosticReason) {
        self.fileName = fileName
        self.reason = reason
    }
}

public enum RecordingArtifactDiagnosticReason: String, Equatable, Hashable, Sendable {
    case invalidReservedStagingName
    case invalidDeletionQuarantineName
    case artifactIsSymbolicLink
    case unsupportedArtifactType
    case canonicalRestoreDestinationOccupied
    case sessionMetadataMissing
    case sessionMetadataIsSymbolicLink
    case sessionMetadataInvalid
    case artifactPolicyInvalid
    case captureFinalizationPending
    case canonicalRecoveryAmbiguous
    case canonicalRollbackFailed
    case sessionMetadataUpdateFailed
    case stagingRemovalFailed
    case quarantineRestoreFailed
    case quarantineRemovalFailed

    /// Non-sensitive German status text suitable for the local UI.
    public var localizedDescription: String {
        switch self {
        case .invalidReservedStagingName:
            return "Temporärer Aufnahmedateiname ist ungültig."
        case .invalidDeletionQuarantineName:
            return "Dateiname der unterbrochenen Medienbereinigung ist ungültig."
        case .artifactIsSymbolicLink:
            return "Aufnahmeartefakt ist ein symbolischer Link."
        case .unsupportedArtifactType:
            return "Aufnahmeartefakt ist keine reguläre Datei."
        case .canonicalRestoreDestinationOccupied:
            return "Zieldatei für die Wiederherstellung ist bereits belegt."
        case .sessionMetadataMissing:
            return "Zugehörige Sitzungsdatei fehlt."
        case .sessionMetadataIsSymbolicLink:
            return "Zugehörige Sitzungsdatei ist ein symbolischer Link."
        case .sessionMetadataInvalid:
            return "Zugehörige Sitzungsdatei ist ungültig."
        case .artifactPolicyInvalid:
            return "Lokale Schutz- und Backup-Richtlinie konnte nicht bestätigt werden."
        case .captureFinalizationPending:
            return "Aufnahmeabschluss ist nicht bestätigt und benötigt lokale Wiederherstellung."
        case .canonicalRecoveryAmbiguous:
            return "Aufnahmeartefakt konnte keiner eindeutigen Wiederherstellung zugeordnet werden."
        case .canonicalRollbackFailed:
            return "Ungültige abgeschlossene Aufnahme konnte nicht sicher zurückgerollt werden."
        case .sessionMetadataUpdateFailed:
            return "Sitzungsdatei konnte nicht sicher aktualisiert werden."
        case .stagingRemovalFailed:
            return "Unterbrochene temporäre Aufnahme konnte nicht bereinigt werden."
        case .quarantineRestoreFailed:
            return "Unterbrochene Medienbereinigung konnte nicht zurückgerollt werden."
        case .quarantineRemovalFailed:
            return "Unterbrochene Medienbereinigung konnte nicht abgeschlossen werden."
        }
    }
}

/// Deterministic summary of bounded startup recovery inside `Recordings/`.
public struct RecordingArtifactReconciliationReport: Equatable, Sendable {
    public struct Values: Sendable {
        public var removedStagingFileNames: [String]
        public var restoredQuarantineFileNames: [String] = []
        public var removedQuarantineFileNames: [String] = []
        /// Staged takes interrupted by termination, kept for an explicit operator decision.
        public var preservedInterruptedTakeFileNames: [String] = []
        public var relinkedSessionIDs: [UUID]
        public var alreadyLinkedSessionIDs: [UUID]
        public var diagnostics: [RecordingArtifactDiagnostic]

        public init(
            removedStagingFileNames: [String] = [],
            relinkedSessionIDs: [UUID] = [],
            alreadyLinkedSessionIDs: [UUID] = [],
            diagnostics: [RecordingArtifactDiagnostic] = []
        ) {
            self.removedStagingFileNames = removedStagingFileNames
            self.relinkedSessionIDs = relinkedSessionIDs
            self.alreadyLinkedSessionIDs = alreadyLinkedSessionIDs
            self.diagnostics = diagnostics
        }
    }

    public let removedStagingFileNames: [String]
    public let restoredQuarantineFileNames: [String]
    public let removedQuarantineFileNames: [String]
    public let preservedInterruptedTakeFileNames: [String]
    public let relinkedSessionIDs: [UUID]
    public let alreadyLinkedSessionIDs: [UUID]
    public let diagnostics: [RecordingArtifactDiagnostic]

    public init(_ values: Values = Values()) {
        removedStagingFileNames = values.removedStagingFileNames
        restoredQuarantineFileNames = values.restoredQuarantineFileNames
        removedQuarantineFileNames = values.removedQuarantineFileNames
        preservedInterruptedTakeFileNames = values.preservedInterruptedTakeFileNames
        relinkedSessionIDs = values.relinkedSessionIDs
        alreadyLinkedSessionIDs = values.alreadyLinkedSessionIDs
        diagnostics = values.diagnostics
    }
}

/// Cleanup result for non-recording persistence artifacts. Unknown media is preserved.
public struct PersistenceArtifactReconciliationReport: Equatable, Sendable {
    public let removedOrphanJournalFileNames: [String]
    public let removedOrphanCodingJournalFileNames: [String]
    public let removedOrphanImportedFileNames: [String]
    public let diagnostics: [RecordingArtifactDiagnostic]

    public init(
        removedOrphanJournalFileNames: [String] = [],
        removedOrphanCodingJournalFileNames: [String] = [],
        removedOrphanImportedFileNames: [String] = [],
        diagnostics: [RecordingArtifactDiagnostic] = []
    ) {
        self.removedOrphanJournalFileNames = removedOrphanJournalFileNames
        self.removedOrphanCodingJournalFileNames = removedOrphanCodingJournalFileNames
        self.removedOrphanImportedFileNames = removedOrphanImportedFileNames
        self.diagnostics = diagnostics
    }
}

public enum SessionStoreError: Error, LocalizedError, Equatable, Sendable {
    case rootDirectoryIsSymbolicLink
    case sessionIdentifierMismatch
    case sessionMetadataIsSymbolicLink
    case recordingFileNameMismatch
    case unsafeRecordingRelativePath
    case recordingDirectoryIsSymbolicLink
    case observationDirectoryIsSymbolicLink
    case observationJournalIsSymbolicLink
    case observationJournalInvalid
    case codingSnapshotDirectoryIsSymbolicLink
    case codingSnapshotJournalIsSymbolicLink
    case codingSnapshotJournalInvalid
    case recordingFileIsSymbolicLink
    case recordingOutsideStore
    case invalidRecordingFileName
    case invalidReservedStagingFileName
    case recordingArtifactIsNotRegularFile
    case importedMediaSourceIsSymbolicLink
    case importedMediaSourceIsNotRegularFile
    case importedMediaSourceIsEmpty
    case importedMediaSourceTooLarge
    case importedMediaInsufficientCapacity
    case importedMediaAlreadyCommitted
    case mediaFileMissing
    case mediaFileIsNotRegular
    case localArtifactPolicyMismatch
    case sessionMetadataRollbackFailed

    public var errorDescription: String? {
        switch self {
        case .rootDirectoryIsSymbolicLink:
            return "Der Sitzungsspeicher ist ein symbolischer Link. Bitte den lokalen Speicherort prüfen."
        case .sessionIdentifierMismatch:
            return "Die Sitzungsdatei passt nicht zu ihrer Kennung und wurde nicht verwendet."
        case .sessionMetadataIsSymbolicLink:
            return "Die Sitzungsdatei ist ein symbolischer Link und wurde aus Sicherheitsgründen abgelehnt."
        case .recordingFileNameMismatch:
            return "Die Aufnahme gehört nicht eindeutig zu dieser Sitzung."
        case .unsafeRecordingRelativePath:
            return "Der gespeicherte Aufnahmepfad ist unsicher und wurde abgelehnt."
        case .recordingDirectoryIsSymbolicLink:
            return "Der Aufnahmeordner ist ein symbolischer Link. Bitte den lokalen Speicherort prüfen."
        case .observationDirectoryIsSymbolicLink:
            return "Der Beobachtungsordner ist ein symbolischer Link und wurde abgelehnt."
        case .observationJournalIsSymbolicLink:
            return "Das Beobachtungsjournal ist ein symbolischer Link und wurde abgelehnt."
        case .observationJournalInvalid:
            return "Das Beobachtungsjournal enthält einen ungültigen Eintrag."
        case .codingSnapshotDirectoryIsSymbolicLink:
            return "Der Kodierungsordner ist ein symbolischer Link und wurde abgelehnt."
        case .codingSnapshotJournalIsSymbolicLink:
            return "Das Kodierungsjournal ist ein symbolischer Link und wurde abgelehnt."
        case .codingSnapshotJournalInvalid:
            return "Das Kodierungsjournal enthält einen ungültigen Eintrag."
        case .recordingFileIsSymbolicLink:
            return "Die Aufnahme ist ein symbolischer Link und wurde aus Sicherheitsgründen abgelehnt."
        case .recordingOutsideStore:
            return "Die Aufnahme liegt außerhalb des geschützten Sitzungsspeichers."
        case .invalidRecordingFileName:
            return "Der Dateiname der Aufnahme entspricht nicht dem erwarteten Format."
        case .invalidReservedStagingFileName:
            return "Der temporäre Aufnahmedateiname entspricht nicht dem reservierten Format."
        case .recordingArtifactIsNotRegularFile:
            return "Das Aufnahmeobjekt ist keine reguläre Datei und wurde nicht verändert."
        case .importedMediaSourceIsSymbolicLink:
            return "Die zu importierende Mediendatei ist ein symbolischer Link und wurde abgelehnt."
        case .importedMediaSourceIsNotRegularFile:
            return "Die zu importierende Mediendatei ist keine reguläre MP4-Datei."
        case .importedMediaSourceIsEmpty:
            return "Die zu importierende Mediendatei ist leer."
        case .importedMediaSourceTooLarge:
            return "Die zu importierende Mediendatei überschreitet die lokale Größenbegrenzung."
        case .importedMediaInsufficientCapacity:
            return "Für den Medienimport ist nicht genügend freier Speicher mit Sicherheitsreserve verfügbar."
        case .importedMediaAlreadyCommitted:
            return "Ein bereits in Sitzungsmetadaten verknüpftes Medium darf nicht als Import-Rollback gelöscht werden."
        case .mediaFileMissing:
            return "Die verknüpfte Mediendatei fehlt."
        case .mediaFileIsNotRegular:
            return "Die verknüpfte Mediendatei ist keine reguläre Datei."
        case .localArtifactPolicyMismatch:
            return "Die lokale Schutz- und Backup-Richtlinie der Aufnahme konnte nicht bestätigt werden."
        case .sessionMetadataRollbackFailed:
            return "Die vorherige Sitzungsdatei konnte nach einem Speicherfehler nicht sicher wiederhergestellt werden."
        }
    }
}

/// Local persistence for capture sessions (JSON files under Application Support / custom directory).
///
/// Thread-safe via a serial queue. No network: alpha keeps classroom metadata and coding
/// trails on-device for institutional control of identifiable media.
public final class SessionStore: @unchecked Sendable {
    internal enum PersistenceFaultPoint {
        case beforeCodingJournalDeletion
        case afterImportPromotion
    }

    static let stagedRecordingPrefix = ".videographr-"
    static let deletionQuarantinePrefix = ".deleting-"
    static let movieExtension = ".mp4"
    static let observationDirectoryName = "Observations"
    static let codingSnapshotDirectoryName = "CodingSnapshots"
    static let importMarkerPrefix = ".videographr-import-"
    static let importMarkerSuffix = ".pending"
    // 120 minutes of five-second samples is 1,440 rows. These ceilings leave
    // ample room for rich, bounded observations while rejecting malformed or
    // adversarial JSONL before it can cause unbounded memory use.
    internal static let maximumObservationJournalBytes = 32 * 1_024 * 1_024
    internal static let maximumObservationLineBytes = 256 * 1_024
    internal static let maximumImportedMediaBytes: Int64 = 20 * 1_024 * 1_024 * 1_024
    static let importCopyBufferBytes = 1_024 * 1_024

    struct DeletionQuarantineIdentity {
        let sessionID: UUID
        let transactionID: UUID
        let mediaID: UUID
    }

    struct ImportedMediaTransaction {
        let transactionID: UUID
        let finalized: SessionMediaAsset
        let source: FileHandle
        let sourceSize: Int64
        let staging: URL
        let destination: URL
        let marker: URL
    }

    struct ActiveImportedMediaTransaction {
        let transaction: ImportedMediaTransaction
        var destinationIsOwned = false
    }

    /// Root folder containing `*.json` sessions and a `Recordings/` subdirectory.
    public let rootDirectory: URL
    let encoder: JSONEncoder
    let decoder: JSONDecoder
    let queue = DispatchQueue(label: "uv.session.store")
    var policyVerificationHook: ((URL) throws -> Void)?
    /// Test-only seam invoked after the source descriptor is open. The import
    /// always reads that descriptor, not the path, so path replacement cannot
    /// change the copied bytes after this point.
    var importSourceOpenedHook: (() throws -> Void)?
    /// Test-only seam for failure paths that otherwise depend on filesystem timing.
    var persistenceFaultHook: ((PersistenceFaultPoint) throws -> Void)?
    /// Test-only seam for deterministic occupied-import-destination checks.
    var importedMediaIDFactory: () -> UUID
    /// Queue-confined reservations keep live imports distinct from abandoned crash artifacts.
    var activeImportedMediaTransactions: [UUID: ActiveImportedMediaTransaction] = [:]
    /// Queue-confined ID index avoids re-decoding the entire JSONL file for every long-take append.
    var observationIDsBySession: [UUID: Set<UUID>] = [:]
    var codingSnapshotIDsBySession: [UUID: Set<UUID>] = [:]

    /// - Parameter rootDirectory: Override for tests; default is Application Support.
    public init(rootDirectory: URL? = nil) {
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            // Directory name keeps domain string for data-path stability; product brand is Videographr.
            self.rootDirectory = base.appendingPathComponent("Unterrichtsvideographie/Sessions", isDirectory: true)
        }
        self.encoder = SessionCoding.sessionFileEncoder()
        self.decoder = SessionCoding.decoder()
        self.policyVerificationHook = nil
        self.importSourceOpenedHook = nil
        self.persistenceFaultHook = nil
        self.importedMediaIDFactory = { UUID() }
        let rootAttributes = try? FileManager.default.attributesOfItem(atPath: self.rootDirectory.path)
        let rootType = rootAttributes?[.type] as? FileAttributeType
        if rootType != .typeSymbolicLink {
            try? FileManager.default.createDirectory(at: self.rootDirectory, withIntermediateDirectories: true)
        }
    }

    /// Test-only seam for deterministic post-write policy failure coverage.
    internal convenience init(
        rootDirectory: URL,
        policyVerificationHook: @escaping (URL) throws -> Void
    ) {
        self.init(rootDirectory: rootDirectory)
        self.policyVerificationHook = policyVerificationHook
    }

    /// Test-only seam for verifying that imports read one opened source handle.
    internal convenience init(
        rootDirectory: URL,
        importSourceOpenedHook: @escaping () throws -> Void
    ) {
        self.init(rootDirectory: rootDirectory)
        self.importSourceOpenedHook = importSourceOpenedHook
    }

    /// Test-only seam for rollback coverage at durable persistence boundaries.
    internal convenience init(
        rootDirectory: URL,
        persistenceFaultHook: @escaping (PersistenceFaultPoint) throws -> Void
    ) {
        self.init(rootDirectory: rootDirectory)
        self.persistenceFaultHook = persistenceFaultHook
    }

}
