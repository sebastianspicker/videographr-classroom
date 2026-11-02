import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

extension SessionStore {
    struct PersistenceReconciliationState {
        var removedJournals: [String] = []
        var removedCodingJournals: [String] = []
        var removedImports: [String] = []
        var diagnostics: [RecordingArtifactDiagnostic] = []
        /// IDs of every `<UUID>.json` root entry, decodable or not; only a missing file makes a journal an orphan.
        var existingSessionIDs: Set<UUID> = []
    }

    struct JournalDirectoryReconciliation {
        let name: String
        let symbolicLinkError: SessionStoreError
        var removedFileNames: [String]
    }

    /// deleted because it cannot safely be distinguished from a recoverable recording.
    public func reconcilePersistenceArtifacts() throws -> PersistenceArtifactReconciliationReport {
        try queue.sync {
            try validateStoreDirectories()
            let knownSessions = try knownSessionsForReconciliation()
            var state = PersistenceReconciliationState()
            state.existingSessionIDs = try existingSessionIDsForReconciliation()
            try reconcileJournalDirectories(state: &state)
            try reconcileImportedMedia(knownSessions, state: &state)
            return PersistenceArtifactReconciliationReport(
                removedOrphanJournalFileNames: state.removedJournals.sorted(),
                removedOrphanCodingJournalFileNames: state.removedCodingJournals.sorted(),
                removedOrphanImportedFileNames: state.removedImports.sorted(), diagnostics: state.diagnostics
            )
        }
    }

    func knownSessionsForReconciliation() throws -> [UUID: CaptureSession] {
        try FileManager.default.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil)
            .reduce(into: [:]) { sessions, url in
                guard url.pathExtension == "json", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent), !(try isSymbolicLink(url)), let session = try? decoder.decode(CaptureSession.self, from: Data(contentsOf: url)), session.id == id else { return }
                sessions[id] = session
            }
    }

    func existingSessionIDsForReconciliation() throws -> Set<UUID> {
        Set(try FileManager.default.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil).compactMap { url in
            url.pathExtension == "json" ? UUID(uuidString: url.deletingPathExtension().lastPathComponent) : nil
        })
    }

    func reconcileJournalDirectories(state: inout PersistenceReconciliationState) throws {
        var observations = JournalDirectoryReconciliation(
            name: Self.observationDirectoryName,
            symbolicLinkError: .observationDirectoryIsSymbolicLink,
            removedFileNames: state.removedJournals
        )
        try reconcileJournalDirectory(&observations, existingIDs: state.existingSessionIDs, diagnostics: &state.diagnostics)
        state.removedJournals = observations.removedFileNames
        var coding = JournalDirectoryReconciliation(
            name: Self.codingSnapshotDirectoryName,
            symbolicLinkError: .codingSnapshotDirectoryIsSymbolicLink,
            removedFileNames: state.removedCodingJournals
        )
        try reconcileJournalDirectory(&coding, existingIDs: state.existingSessionIDs, diagnostics: &state.diagnostics)
        state.removedCodingJournals = coding.removedFileNames
    }

    func reconcileJournalDirectory(_ request: inout JournalDirectoryReconciliation, existingIDs: Set<UUID>, diagnostics: inout [RecordingArtifactDiagnostic]) throws {
        let directory = rootDirectory.appendingPathComponent(request.name, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        if try isSymbolicLink(directory) { throw request.symbolicLinkError }
        try removeOrphanJournals(in: directory, existingSessionIDs: existingIDs, removedFileNames: &request.removedFileNames, diagnostics: &diagnostics)
    }

    func reconcileImportedMedia(_ sessions: [UUID: CaptureSession], state: inout PersistenceReconciliationState) throws {
        let directory = rootDirectory.appendingPathComponent("Recordings", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        if try isSymbolicLink(directory) { throw SessionStoreError.recordingDirectoryIsSymbolicLink }
        for marker in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where marker.lastPathComponent.hasPrefix(Self.importMarkerPrefix) && marker.lastPathComponent.hasSuffix(Self.importMarkerSuffix) {
            try reconcileImportedMarker(marker, directory: directory, sessions: sessions, state: &state)
        }
    }

    func reconcileImportedMarker(_ marker: URL, directory: URL, sessions: [UUID: CaptureSession], state: inout PersistenceReconciliationState) throws {
        guard let identity = importMarkerIdentity(for: marker.lastPathComponent) else { return }
        if activeImportedMediaTransactions.values.contains(where: {
            $0.transaction.finalized.id == identity.assetID
                && $0.transaction.marker.lastPathComponent == marker.lastPathComponent
        }) { return }
        if try isSymbolicLink(marker) { throw SessionStoreError.recordingFileIsSymbolicLink }
        if sessions[identity.sessionID]?.mediaAssets.contains(where: { $0.id == identity.assetID }) == true { try FileManager.default.removeItem(at: marker); return }
        // A session file that exists but does not decode may still reference this media.
        if sessions[identity.sessionID] == nil, state.existingSessionIDs.contains(identity.sessionID) {
            state.diagnostics.append(.init(fileName: marker.lastPathComponent, reason: .sessionMetadataInvalid)); return
        }
        let mediaURL = directory.appendingPathComponent("\(identity.assetID.uuidString).mp4")
        if try isSymbolicLink(mediaURL) { state.diagnostics.append(.init(fileName: mediaURL.lastPathComponent, reason: .artifactIsSymbolicLink)); return }
        if FileManager.default.fileExists(atPath: mediaURL.path) { guard try fileType(at: mediaURL) == .typeRegular else { state.diagnostics.append(.init(fileName: mediaURL.lastPathComponent, reason: .unsupportedArtifactType)); return }; try FileManager.default.removeItem(at: mediaURL); state.removedImports.append(mediaURL.lastPathComponent) }
        try FileManager.default.removeItem(at: marker)
    }

    /// Applies the local-artifact policy to an existing finalized movie inside `Recordings`.
    /// Finalized media requires an unlocked device on iOS.
    public func secureFinalizedRecording(at url: URL) throws {
        try queue.sync {
            try validateStoreDirectories()
            let validatedURL = try validatedRecordingURL(for: url.lastPathComponent)
            guard validatedURL.standardizedFileURL == url.standardizedFileURL else {
                throw SessionStoreError.recordingOutsideStore
            }
            if try isSymbolicLink(validatedURL) {
                throw SessionStoreError.recordingFileIsSymbolicLink
            }
            try validateFinalizedRecordingFileName(validatedURL.lastPathComponent)
            guard FileManager.default.fileExists(atPath: validatedURL.path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            guard try fileType(at: validatedURL) == .typeRegular else {
                throw SessionStoreError.recordingArtifactIsNotRegularFile
            }
            try applyAndVerifyLocalArtifactPolicy(to: validatedURL)
            try validateStoreDirectories()
        }
    }

    /// Resolves a session media asset only after validating its canonical name, store boundary,
    /// symlink state, and regular-file type. App code must not construct media paths directly.
    public func validatedMediaURL(for asset: SessionMediaAsset, sessionID: UUID) throws -> URL {
        try queue.sync {
            try validateStoreDirectories()
            try validateMediaAsset(asset, sessionID: sessionID)
            let url = try validatedRecordingURL(for: asset.relativePath)
            if try isSymbolicLink(url) { throw SessionStoreError.recordingFileIsSymbolicLink }
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SessionStoreError.mediaFileMissing
            }
            guard try fileType(at: url) == .typeRegular else {
                throw SessionStoreError.mediaFileIsNotRegular
            }
            return url
        }
    }

    /// Copies an externally selected regular MP4 into the controlled recordings directory.
    /// The returned asset is always addressed as `<asset UUID>.mp4`; source links are rejected.
    public func importMedia(from sourceURL: URL, into sessionID: UUID) throws -> SessionMediaAsset {
        let transaction = try queue.sync {
            try reserveImportedMedia(from: sourceURL, into: sessionID)
        }
        defer { try? transaction.source.close() }
        do {
            try copyImportedMedia(transaction)
            try Task.checkCancellation()
            return try queue.sync {
                do {
                    try promoteImportedMedia(transaction, sessionID: sessionID)
                    activeImportedMediaTransactions[transaction.transactionID] = nil
                    try validateStoreDirectories()
                    return transaction.finalized
                } catch {
                    cleanUpFailedImport(transaction)
                    throw error
                }
            }
        } catch {
            queue.sync { cleanUpFailedImport(transaction) }
            throw error
        }
    }

    private func reserveImportedMedia(
        from sourceURL: URL,
        into sessionID: UUID
    ) throws -> ImportedMediaTransaction {
        try validateStoreDirectories()
        try validateImportSource(sourceURL)
        let source = try openImportedMediaSource(at: sourceURL)
        let sourceSize: Int64
        do {
            sourceSize = try validatedImportedSourceSize(source)
        } catch {
            try? source.close()
            throw error
        }
        let transaction: ImportedMediaTransaction
        do {
            transaction = try importedMediaTransaction(
                sourceURL: sourceURL,
                source: source,
                sourceSize: sourceSize,
                sessionID: sessionID
            )
        } catch {
            try? source.close()
            throw error
        }
        do {
            guard !FileManager.default.fileExists(atPath: transaction.marker.path),
                  !(try isSymbolicLink(transaction.marker)),
                  !FileManager.default.fileExists(atPath: transaction.staging.path),
                  !(try isSymbolicLink(transaction.staging))
            else { throw CocoaError(.fileWriteFileExists) }
            try Data(sessionID.uuidString.utf8).write(to: transaction.marker, options: .atomic)
            try applyAndVerifyLocalArtifactPolicy(to: transaction.marker)
            activeImportedMediaTransactions[transaction.transactionID] = ActiveImportedMediaTransaction(
                transaction: transaction
            )
            return transaction
        } catch {
            _ = removeImportArtifactIfSafe(transaction.marker)
            try? source.close()
            throw error
        }
    }

    private func validateImportSource(_ sourceURL: URL) throws {
        guard sourceURL.pathExtension.lowercased() == "mp4" else {
            throw SessionStoreError.importedMediaSourceIsNotRegularFile
        }
    }

    private func openImportedMediaSource(at sourceURL: URL) throws -> FileHandle {
        #if canImport(Darwin) || canImport(Glibc)
        let descriptor = sourceURL.path.withCString {
            open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        }
        guard descriptor >= 0 else {
            if errno == ELOOP { throw SessionStoreError.importedMediaSourceIsSymbolicLink }
            throw SessionStoreError.importedMediaSourceIsNotRegularFile
        }
        let source = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            _ = try regularFileSize(of: source)
            return source
        } catch {
            try? source.close()
            throw error
        }
        #else
        throw SessionStoreError.importedMediaSourceIsNotRegularFile
        #endif
    }

    private func importedMediaTransaction(
        sourceURL: URL,
        source: FileHandle,
        sourceSize: Int64,
        sessionID: UUID
    ) throws -> ImportedMediaTransaction {
        let directory = try prepareRecordingsDirectory()
        let finalized = try importedMediaAsset(sourceURL: sourceURL, sessionID: sessionID)
        let destination = directory.appendingPathComponent(finalized.relativePath, isDirectory: false)
        guard !FileManager.default.fileExists(atPath: destination.path), !(try isSymbolicLink(destination)) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let staging = directory.appendingPathComponent(
            stagedRecordingFileName(sessionID: sessionID, transactionID: UUID()), isDirectory: false
        )
        guard let transactionID = stagedRecordingIdentity(for: staging.lastPathComponent)?.transactionID else {
            throw SessionStoreError.invalidReservedStagingFileName
        }
        return ImportedMediaTransaction(
            transactionID: transactionID,
            finalized: finalized,
            source: source,
            sourceSize: sourceSize,
            staging: staging,
            destination: destination,
            marker: importMarkerURL(sessionID: sessionID, assetID: finalized.id, in: directory)
        )
    }

    private func importedMediaAsset(
        sourceURL: URL, sessionID: UUID
    ) throws -> SessionMediaAsset {
        var values = SessionMediaAsset.Values()
        values.role = .otherImported
        values.relativePath = "pending.mp4"
        values.originalFileName = sourceURL.lastPathComponent
        values.id = importedMediaIDFactory()
        values.relativePath = "\(values.id.uuidString).mp4"
        let finalized = SessionMediaAsset(values)
        try validateMediaAsset(finalized, sessionID: sessionID)
        return finalized
    }

    private func copyImportedMedia(_ transaction: ImportedMediaTransaction) throws {
        try importSourceOpenedHook?()
        try streamCopy(
            source: transaction.source,
            to: transaction.staging,
            admittedSize: transaction.sourceSize
        )
        let copiedSize = try validatedImportedCopySize(at: transaction.staging)
        guard copiedSize == transaction.sourceSize else {
            throw SessionStoreError.importedMediaSourceIsNotRegularFile
        }
        try applyAndVerifyLocalArtifactPolicy(
            to: transaction.staging,
            fileProtection: .completeUnlessOpen
        )
    }

    private func validatedImportedSourceSize(_ source: FileHandle) throws -> Int64 {
        let size = try regularFileSize(of: source)
        try validateImportedMediaSize(size)
        if let available = try availableImportCapacity() {
            let reserve: Int64 = 250 * 1_024 * 1_024
            guard available >= size + reserve else {
                throw SessionStoreError.importedMediaInsufficientCapacity
            }
        }
        return size
    }

    private func validatedImportedCopySize(at staging: URL) throws -> Int64 {
        if try isSymbolicLink(staging) { throw SessionStoreError.recordingFileIsSymbolicLink }
        guard try fileType(at: staging) == .typeRegular else {
            throw SessionStoreError.importedMediaSourceIsNotRegularFile
        }
        let size = try regularFileSize(at: staging)
        try validateImportedMediaSize(size)
        return size
    }

    private func validateImportedMediaSize(_ size: Int64) throws {
        guard size > 0 else { throw SessionStoreError.importedMediaSourceIsEmpty }
        guard size <= Self.maximumImportedMediaBytes else {
            throw SessionStoreError.importedMediaSourceTooLarge
        }
    }

    private func promoteImportedMedia(
        _ transaction: ImportedMediaTransaction, sessionID: UUID
    ) throws {
        try validateStoreDirectories()
        guard let active = activeImportedMediaTransactions[transaction.transactionID],
              active.transaction.finalized.id == transaction.finalized.id,
              active.transaction.staging == transaction.staging,
              active.transaction.destination == transaction.destination,
              active.transaction.marker == transaction.marker
        else { throw CocoaError(.fileWriteUnknown) }
        guard !FileManager.default.fileExists(atPath: transaction.destination.path),
              !(try isSymbolicLink(transaction.destination))
        else { throw CocoaError(.fileWriteFileExists) }
        _ = try validatedImportedCopySize(at: transaction.staging)
        try FileManager.default.moveItem(at: transaction.staging, to: transaction.destination)
        activeImportedMediaTransactions[transaction.transactionID]?.destinationIsOwned = true
        try persistenceFaultHook?(.afterImportPromotion)
        try applyAndVerifyLocalArtifactPolicy(to: transaction.destination)
    }

    private func cleanUpFailedImport(_ transaction: ImportedMediaTransaction) {
        guard let active = activeImportedMediaTransactions[transaction.transactionID],
              active.transaction.finalized.id == transaction.finalized.id,
              active.transaction.marker == transaction.marker
        else { return }
        let stagingRemoved = removeImportArtifactIfSafe(transaction.staging)
        let destinationRemoved = !active.destinationIsOwned
            || removeImportArtifactIfSafe(transaction.destination)
        if stagingRemoved && destinationRemoved {
            _ = removeImportArtifactIfSafe(transaction.marker)
        }
        activeImportedMediaTransactions[transaction.transactionID] = nil
    }

    private func removeImportArtifactIfSafe(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        guard (try? isSymbolicLink(url)) == false, (try? fileType(at: url)) == .typeRegular else {
            return false
        }
        do {
            try FileManager.default.removeItem(at: url)
            return !FileManager.default.fileExists(atPath: url.path)
        } catch {
            return false
        }
    }

    /// Removes an imported file only while no session metadata references its asset ID.
    /// Used to roll back AV validation or metadata-commit failures after a successful copy.
    public func discardUncommittedImportedMedia(_ asset: SessionMediaAsset, from sessionID: UUID) throws {
        try queue.sync { try discardUncommittedImportedMediaLocked(asset, sessionID: sessionID) }
    }

    private func discardUncommittedImportedMediaLocked(_ asset: SessionMediaAsset, sessionID: UUID) throws {
        try validateStoreDirectories()
        try validateUncommittedImportedMedia(asset, sessionID: sessionID)
        let url = try validatedRecordingURL(for: asset.relativePath)
        try removeUncommittedImportedMedia(at: url)
        try removeImportMarkerIfSafe(for: asset, sessionID: sessionID, directory: url.deletingLastPathComponent())
        try validateStoreDirectories()
    }

    private func validateUncommittedImportedMedia(_ asset: SessionMediaAsset, sessionID: UUID) throws {
        guard asset.role == .otherImported else { throw SessionStoreError.recordingFileNameMismatch }
        try validateMediaAsset(asset, sessionID: sessionID)
        let committed = try loadSessionMetadata(id: sessionID)?.mediaAssets.contains(where: { $0.id == asset.id }) ?? false
        guard !committed else { throw SessionStoreError.importedMediaAlreadyCommitted }
    }

    private func removeUncommittedImportedMedia(at url: URL) throws {
        try removeRegularRecording(at: url, nonRegularError: .mediaFileIsNotRegular)
    }

    func removeRegularRecording(at url: URL, nonRegularError: SessionStoreError) throws {
        if try isSymbolicLink(url) { throw SessionStoreError.recordingFileIsSymbolicLink }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard try fileType(at: url) == .typeRegular else { throw nonRegularError }
        try FileManager.default.removeItem(at: url)
    }

    private func removeImportMarkerIfSafe(for asset: SessionMediaAsset, sessionID: UUID, directory: URL) throws {
        let marker = importMarkerURL(sessionID: sessionID, assetID: asset.id, in: directory)
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        guard try !isSymbolicLink(marker) else { return }
        try? FileManager.default.removeItem(at: marker)
    }

    /// Marks a copied import as durably referenced after its session metadata commit.
    public func commitImportedMedia(_ asset: SessionMediaAsset, toSession sessionID: UUID) throws {
        try queue.sync {
            try validateStoreDirectories()
            guard asset.role == .otherImported,
                  let session = try loadSessionMetadata(id: sessionID),
                  session.mediaAssets.contains(where: { $0.id == asset.id })
            else { throw SessionStoreError.importedMediaAlreadyCommitted }
            let directory = rootDirectory.appendingPathComponent("Recordings", isDirectory: true)
            let marker = importMarkerURL(sessionID: sessionID, assetID: asset.id, in: directory)
            if try isSymbolicLink(marker) { throw SessionStoreError.recordingFileIsSymbolicLink }
            if FileManager.default.fileExists(atPath: marker.path) { try FileManager.default.removeItem(at: marker) }
        }
    }

    func loadSessionMetadata(id: UUID) throws -> CaptureSession? {
        try validateStoreDirectories()
        let url = fileURL(for: id)
        if try isSymbolicLink(url) { throw SessionStoreError.sessionMetadataIsSymbolicLink }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let session = try decoder.decode(CaptureSession.self, from: Data(contentsOf: url))
        try validateSessionOwnership(session, expectedID: id)
        return session
    }

}
