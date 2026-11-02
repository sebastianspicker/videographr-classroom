import Foundation

struct StrictUUIDTriple {
    let transactionID: UUID
    let sessionID: UUID
    let mediaID: UUID
}

private struct StrictUUIDTripleTexts {
    let transactionID: String
    let sessionID: String
    let mediaID: String
}

extension SessionStore {
    func fileURL(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    func observationJournalURL(for id: UUID) -> URL {
        rootDirectory
            .appendingPathComponent(Self.observationDirectoryName, isDirectory: true)
            .appendingPathComponent("\(id.uuidString).jsonl", isDirectory: false)
    }

    func codingSnapshotJournalURL(for id: UUID) -> URL {
        rootDirectory
            .appendingPathComponent(Self.codingSnapshotDirectoryName, isDirectory: true)
            .appendingPathComponent("\(id.uuidString).jsonl", isDirectory: false)
    }

    func importMarkerURL(sessionID: UUID, assetID: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent(
            "\(Self.importMarkerPrefix)\(sessionID.uuidString)-\(assetID.uuidString)\(Self.importMarkerSuffix)",
            isDirectory: false
        )
    }

    func importMarkerIdentity(for fileName: String) -> (sessionID: UUID, assetID: UUID)? {
        let hasReservedEnvelope = [
            fileName.hasPrefix(Self.importMarkerPrefix),
            fileName.hasSuffix(Self.importMarkerSuffix)
        ].allSatisfy({ $0 })
        guard hasReservedEnvelope else { return nil }
        let body = String(fileName.dropFirst(Self.importMarkerPrefix.count).dropLast(Self.importMarkerSuffix.count))
        return strictUUIDPair(from: body).map { (sessionID: $0.0, assetID: $0.1) }
    }

    func strictUUIDPair(from body: String) -> (UUID, UUID)? {
        guard let (firstText, secondText) = strictUUIDPairTexts(from: body) else { return nil }
        let texts = [firstText, secondText]
        guard let identifiers = canonicalUUIDs(from: texts) else { return nil }
        return (identifiers[0], identifiers[1])
    }

    func strictUUIDTriple(from body: String) -> StrictUUIDTriple? {
        guard let texts = strictUUIDTripleTexts(from: body) else { return nil }
        let textValues = [texts.transactionID, texts.sessionID, texts.mediaID]
        guard let identifiers = canonicalUUIDs(from: textValues) else { return nil }
        return StrictUUIDTriple(
            transactionID: identifiers[0],
            sessionID: identifiers[1],
            mediaID: identifiers[2]
        )
    }

    func UUIDTextsAreCanonical(_ texts: [String], identifiers: [UUID]) -> Bool {
        zip(texts, identifiers).allSatisfy { $0 == $1.uuidString }
    }

    private func canonicalUUIDs(from texts: [String]) -> [UUID]? {
        let identifiers = texts.compactMap(UUID.init(uuidString:))
        guard identifiers.count == texts.count else { return nil }
        guard UUIDTextsAreCanonical(texts, identifiers: identifiers) else { return nil }
        return identifiers
    }

    private func strictUUIDPairTexts(from body: String) -> (String, String)? {
        let hasExpectedWidth = [body.utf8.count == 73, body.count == 73].allSatisfy({ $0 })
        guard hasExpectedWidth else { return nil }
        let separator = body.index(body.startIndex, offsetBy: 36)
        guard body[separator] == "-" else { return nil }
        return (String(body[..<separator]), String(body[body.index(after: separator)...]))
    }

    private func strictUUIDTripleTexts(from body: String) -> StrictUUIDTripleTexts? {
        let hasExpectedWidth = [body.utf8.count == 110, body.count == 110].allSatisfy({ $0 })
        guard hasExpectedWidth else { return nil }
        let firstSeparator = body.index(body.startIndex, offsetBy: 36)
        let secondSeparator = body.index(body.startIndex, offsetBy: 73)
        let hasSeparators = [body[firstSeparator] == "-", body[secondSeparator] == "-"].allSatisfy({ $0 })
        guard hasSeparators else { return nil }
        return StrictUUIDTripleTexts(
            transactionID: String(body[..<firstSeparator]),
            sessionID: String(body[body.index(after: firstSeparator)..<secondSeparator]),
            mediaID: String(body[body.index(after: secondSeparator)...])
        )
    }

    /// Atomically write one session JSON (updates `updatedAt`).
    public func save(_ session: CaptureSession) throws {
        try queue.sync {
            try validateStoreDirectories()
            var copy = session
            copy.updatedAt = Date()
            // `load` returns a merged export snapshot, but JSONL is the authoritative
            // observation store. Persisting that snapshot verbatim would duplicate an
            // unbounded journal into metadata on every unrelated session edit.
            let observationsToAppend = copy.captureObservations
            copy.captureObservations.removeAll()
            let codingSnapshotsToAppend = copy.codingSnapshots
            copy.codingSnapshots.removeAll()
            try validateSessionOwnership(copy, expectedID: copy.id)
            try appendObservationsToJournal(observationsToAppend, sessionID: copy.id)
            try appendCodingSnapshotsToJournal(codingSnapshotsToAppend, sessionID: copy.id)
            let data = try encoder.encode(copy)
            let url = fileURL(for: copy.id)
            try prepareRootDirectory()
            if try isSymbolicLink(url) { throw SessionStoreError.sessionMetadataIsSymbolicLink }
            let previousData = FileManager.default.fileExists(atPath: url.path)
                ? try Data(contentsOf: url)
                : nil
            try transactionallyWriteMetadata(data, replacing: previousData, at: url) {
                _ = try self.validatedPersistedSession(at: url, expectedID: copy.id)
            }
        }
    }

    /// Load a session by id, or `nil` if the file is missing.
    public func load(id: UUID) throws -> CaptureSession? {
        let url = fileURL(for: id)
        return try queue.sync {
            try validateStoreDirectories()
            if try isSymbolicLink(url) { throw SessionStoreError.sessionMetadataIsSymbolicLink }
            guard FileManager.default.fileExists(atPath: url.path) else {
                try validateStoreDirectories()
                return nil
            }
            let data = try Data(contentsOf: url)
            let session = try decoder.decode(CaptureSession.self, from: data)
            try validateSessionOwnership(session, expectedID: id)
            try validateStoreDirectories()
            return try mergedWithJournals(session)
        }
    }

    /// Metadata-only load for bounded read-modify-write operations. Full journal hydration is
    /// intentionally reserved for explicit history/export reads.
    internal func loadMetadataOnly(id: UUID) throws -> CaptureSession? {
        try queue.sync {
            try loadSessionMetadata(id: id)
        }
    }

    /// Lists readable session JSON files and retains failures for malformed files.
    /// Directory enumeration itself still throws. Sessions are metadata-only; journals are not merged.
    public func listSessionsWithDiagnostics() throws -> SessionStoreListing {
        try queue.sync {
            try validateStoreDirectories()
            let urls = try FileManager.default.contentsOfDirectory(
                at: rootDirectory,
                includingPropertiesForKeys: nil
            )
            var sessions: [CaptureSession] = []
            var failures: [SessionStoreFileFailure] = []
            let sessionURLs = urls
                .filter { $0.pathExtension == "json" }
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            for url in sessionURLs {
                do {
                    sessions.append(try listedSession(at: url))
                } catch {
                    failures.append(SessionStoreFileFailure(
                        fileName: url.lastPathComponent,
                        errorDescription: safeErrorDescription(error)
                    ))
                }
            }
            let listing = SessionStoreListing(
                sessions: sessions.sorted {
                    $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt
                },
                failures: failures
            )
            try validateStoreDirectories()
            return listing
        }
    }

    private func listedSession(at url: URL) throws -> CaptureSession {
        if try isSymbolicLink(url) { throw SessionStoreError.sessionMetadataIsSymbolicLink }
        let data = try Data(contentsOf: url)
        let session = try decoder.decode(CaptureSession.self, from: data)
        let identifier = url.deletingPathExtension().lastPathComponent
        guard let expectedID = UUID(uuidString: identifier), identifier == expectedID.uuidString else {
            throw SessionStoreError.sessionIdentifierMismatch
        }
        try validateSessionOwnership(session, expectedID: expectedID)
        return session
    }

    /// Appends a durable JSONL observation without rewriting session metadata.
    /// Repeated observation IDs are ignored, so retrying after an interrupted caller is safe.
    func appendCaptureObservation(_ observation: CaptureObservation, toSession id: UUID) throws {
        try queue.sync {
            _ = try requiredSessionMetadata(id: id)
            try appendObservationsToJournal([observation], sessionID: id)
        }
    }

    /// Revalidates collection consent from metadata and appends one observation in the same
    /// serialized store operation. Revocation cannot interleave between authorization and append.
    @discardableResult
    public func appendCaptureObservationIfAuthorized(
        _ observation: CaptureObservation,
        toSession id: UUID,
        at date: Date = Date()
    ) throws -> Bool {
        try queue.sync {
            let session = try requiredSessionMetadata(id: id)
            guard session.authorizes(.collection, at: date) else { return false }
            try appendObservationsToJournal([observation], sessionID: id)
            return true
        }
    }

    /// Appends one coding snapshot without rewriting the whole session metadata or history.
    /// Repeated snapshot IDs are ignored, making retries after interrupted callers safe.
    public func appendCodingSnapshot(_ snapshot: ResearchCodingSnapshot, toSession id: UUID) throws {
        try queue.sync {
            let session = try requiredSessionMetadata(id: id)
            guard session.hasUsableExperimentalProtocol else {
                throw CocoaError(.fileWriteNoPermission)
            }
            try appendCodingSnapshotsToJournal([snapshot], sessionID: id)
        }
    }

    /// Reads inline legacy observations and JSONL observations as one ID-deduplicated timeline.
    public func loadCaptureObservations(forSession id: UUID) throws -> [CaptureObservation] {
        try queue.sync {
            guard let session = try loadSessionMetadata(id: id) else { return [] }
            return try mergedObservations(inline: session.captureObservations, sessionID: id)
        }
    }

    /// Reads inline legacy and durable JSONL coding snapshots as one ID-deduplicated timeline.
    public func loadCodingSnapshots(forSession id: UUID) throws -> [ResearchCodingSnapshot] {
        try queue.sync {
            guard let session = try loadSessionMetadata(id: id) else { return [] }
            return try mergedCodingSnapshots(inline: session.codingSnapshots, sessionID: id)
        }
    }

    func requiredSessionMetadata(id: UUID) throws -> CaptureSession {
        try validateStoreDirectories()
        let metadataURL = fileURL(for: id)
        if try isSymbolicLink(metadataURL) { throw SessionStoreError.sessionMetadataIsSymbolicLink }
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let session = try decoder.decode(CaptureSession.self, from: Data(contentsOf: metadataURL))
        try validateSessionOwnership(session, expectedID: id)
        return session
    }

}
