import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

extension SessionStore {
    func prepareRootDirectory() throws {
        try validateStoreDirectories()
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try validateStoreDirectories()
        try applyAndVerifyLocalArtifactPolicy(to: rootDirectory)
        try validateStoreDirectories()
    }

    func prepareRecordingsDirectory() throws -> URL {
        try validateStoreDirectories()
        let directory = rootDirectory.appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try validateStoreDirectories()
        try applyAndVerifyLocalArtifactPolicy(to: directory)
        try validateStoreDirectories()
        return directory
    }

    func prepareObservationsDirectory() throws -> URL {
        try validateStoreDirectories()
        let directory = rootDirectory.appendingPathComponent(Self.observationDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if try isSymbolicLink(directory) { throw SessionStoreError.observationDirectoryIsSymbolicLink }
        try applyAndVerifyLocalArtifactPolicy(to: directory)
        return directory
    }

    func prepareCodingSnapshotDirectory() throws -> URL {
        try validateStoreDirectories()
        let directory = rootDirectory.appendingPathComponent(Self.codingSnapshotDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if try isSymbolicLink(directory) { throw SessionStoreError.codingSnapshotDirectoryIsSymbolicLink }
        try applyAndVerifyLocalArtifactPolicy(to: directory)
        return directory
    }

    func validateStoreDirectories() throws {
        if try isSymbolicLink(rootDirectory) {
            throw SessionStoreError.rootDirectoryIsSymbolicLink
        }
        let recordings = rootDirectory.appendingPathComponent("Recordings", isDirectory: true)
        if try isSymbolicLink(recordings) {
            throw SessionStoreError.recordingDirectoryIsSymbolicLink
        }
        let observations = rootDirectory.appendingPathComponent(Self.observationDirectoryName, isDirectory: true)
        if try isSymbolicLink(observations) {
            throw SessionStoreError.observationDirectoryIsSymbolicLink
        }
        let codingSnapshots = rootDirectory.appendingPathComponent(Self.codingSnapshotDirectoryName, isDirectory: true)
        if try isSymbolicLink(codingSnapshots) {
            throw SessionStoreError.codingSnapshotDirectoryIsSymbolicLink
        }
    }

    func validatedObservationJournalURL(for id: UUID) throws -> URL {
        try validateStoreDirectories()
        let directory = rootDirectory.appendingPathComponent(Self.observationDirectoryName, isDirectory: true)
        if try isSymbolicLink(directory) { throw SessionStoreError.observationDirectoryIsSymbolicLink }
        let url = observationJournalURL(for: id)
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
              url.lastPathComponent == "\(id.uuidString).jsonl"
        else {
            throw SessionStoreError.observationJournalInvalid
        }
        return url
    }

    func validatedCodingSnapshotJournalURL(for id: UUID) throws -> URL {
        try validateStoreDirectories()
        let directory = rootDirectory.appendingPathComponent(Self.codingSnapshotDirectoryName, isDirectory: true)
        if try isSymbolicLink(directory) { throw SessionStoreError.codingSnapshotDirectoryIsSymbolicLink }
        let url = codingSnapshotJournalURL(for: id)
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
              url.lastPathComponent == "\(id.uuidString).jsonl"
        else { throw SessionStoreError.codingSnapshotJournalInvalid }
        return url
    }

    func validatedRecordingURL(
        for relativePath: String,
        expectedSessionID: UUID? = nil
    ) throws -> URL {
        try validateStoreDirectories()
        try validateRecordingRelativePath(relativePath, expectedSessionID: expectedSessionID)

        let directory = rootDirectory.appendingPathComponent("Recordings", isDirectory: true)
        if try isSymbolicLink(directory) {
            throw SessionStoreError.recordingDirectoryIsSymbolicLink
        }
        let url = directory.appendingPathComponent(relativePath, isDirectory: false)
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else {
            throw SessionStoreError.unsafeRecordingRelativePath
        }
        return url
    }

    func validateSessionOwnership(_ session: CaptureSession, expectedID: UUID) throws {
        guard session.id == expectedID else { throw SessionStoreError.sessionIdentifierMismatch }
        if let relativePath = session.recordingRelativePath {
            try validateRecordingRelativePath(relativePath, expectedSessionID: session.id)
        }
        for asset in session.mediaAssets {
            try validateMediaAsset(asset, sessionID: session.id)
        }
    }

    func validateMediaAsset(_ asset: SessionMediaAsset, sessionID: UUID) throws {
        let path = asset.relativePath
        try validateRecordingRelativePath(path, expectedSessionID: nil)
        let expectedNameByRole: [MediaAssetRole: String] = [
            .ownRecorded: "\(sessionID.uuidString).mp4",
            .otherImported: "\(asset.id.uuidString).mp4"
        ]
        guard path == expectedNameByRole[asset.role] else { throw SessionStoreError.recordingFileNameMismatch }
    }

    func validateRecordingRelativePath(
        _ relativePath: String,
        expectedSessionID: UUID?
    ) throws {
        guard URL(fileURLWithPath: relativePath).pathExtension.lowercased() == "mp4",
              !relativePath.isEmpty,
              !relativePath.contains("/"),
              !relativePath.contains("\\"),
              URL(fileURLWithPath: relativePath).lastPathComponent == relativePath
        else {
            throw SessionStoreError.unsafeRecordingRelativePath
        }

        if let expectedSessionID {
            guard relativePath == "\(expectedSessionID.uuidString).mp4" else {
                throw SessionStoreError.recordingFileNameMismatch
            }
        }
    }

    func stagedRecordingFileName(sessionID: UUID, transactionID: UUID) -> String {
        "\(Self.stagedRecordingPrefix)\(sessionID.uuidString)-\(transactionID.uuidString)\(Self.movieExtension)"
    }

    func stagedRecordingIdentity(for fileName: String) -> (sessionID: UUID, transactionID: UUID)? {
        guard let identity = transactionArtifactIdentity(for: fileName, prefix: Self.stagedRecordingPrefix) else {
            return nil
        }
        return (identity.firstID, identity.secondID)
    }

    func deletionQuarantineFileName(
        sessionID: UUID,
        transactionID: UUID,
        mediaID: UUID
    ) -> String {
        "\(Self.deletionQuarantinePrefix)\(transactionID.uuidString)-\(sessionID.uuidString)-\(mediaID.uuidString)\(Self.movieExtension)"
    }

    func deletionQuarantineIdentity(for fileName: String) -> DeletionQuarantineIdentity? {
        if let legacy = transactionArtifactIdentity(for: fileName, prefix: Self.deletionQuarantinePrefix) {
            return DeletionQuarantineIdentity(
                sessionID: legacy.secondID,
                transactionID: legacy.firstID,
                mediaID: legacy.secondID
            )
        }
        let hasReservedEnvelope = [
            fileName.hasPrefix(Self.deletionQuarantinePrefix), fileName.hasSuffix(Self.movieExtension)
        ].allSatisfy({ $0 })
        guard hasReservedEnvelope else { return nil }
        let body = String(fileName
            .dropFirst(Self.deletionQuarantinePrefix.count)
            .dropLast(Self.movieExtension.count))
        guard let identities = strictUUIDTriple(from: body) else { return nil }
        return DeletionQuarantineIdentity(
            sessionID: identities.sessionID,
            transactionID: identities.transactionID,
            mediaID: identities.mediaID
        )
    }

    func transactionArtifactIdentity(
        for fileName: String,
        prefix: String
    ) -> (firstID: UUID, secondID: UUID)? {
        let hasReservedEnvelope = [fileName.hasPrefix(prefix), fileName.hasSuffix(Self.movieExtension)]
            .allSatisfy({ $0 })
        guard hasReservedEnvelope else { return nil }

        let body = String(fileName
            .dropFirst(prefix.count)
            .dropLast(Self.movieExtension.count))
        return strictUUIDPair(from: body).map { (firstID: $0.0, secondID: $0.1) }
    }

    func canonicalRecordingSessionID(for fileName: String) -> UUID? {
        guard fileName.hasSuffix(Self.movieExtension) else { return nil }
        let identifier = String(fileName.dropLast(Self.movieExtension.count))
        guard let sessionID = UUID(uuidString: identifier), identifier == sessionID.uuidString else {
            return nil
        }
        return sessionID
    }

    func validateFinalizedRecordingFileName(_ fileName: String) throws {
        if canonicalRecordingSessionID(for: fileName) != nil { return }
        if stagedRecordingIdentity(for: fileName) != nil { return }
        if fileName.hasPrefix(Self.stagedRecordingPrefix) {
            throw SessionStoreError.invalidReservedStagingFileName
        }
        throw SessionStoreError.invalidRecordingFileName
    }

    func availableImportCapacity() throws -> Int64? {
        let values = try rootDirectory.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])
        if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 {
            return important
        }
        if let fallback = values.volumeAvailableCapacity {
            return Int64(fallback)
        }
        return values.volumeAvailableCapacityForImportantUsage
    }

}
