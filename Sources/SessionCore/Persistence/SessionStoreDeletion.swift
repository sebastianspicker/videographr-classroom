import Foundation

extension SessionStore {
    private struct SessionDeletionContext {
        let metadataURL: URL
        let metadataData: Data
        let session: CaptureSession
        let journalURL: URL
        let journalData: Data?
        let codingJournalURL: URL
        let codingJournalData: Data?
        let media: [(url: URL, mediaID: UUID)]
    }

    private struct QuarantinedMedia {
        let original: URL
        let quarantine: URL
    }

    /// Deletes a session and its validated in-store recording. Missing files are a no-op.
    /// Unsafe paths and symbolic links are rejected before metadata or external files are touched.
    public func deleteSessionAndMedia(id: UUID) throws {
        try queue.sync {
            try deleteSessionAndMediaLocked(id: id)
        }
    }

    private func deleteSessionAndMediaLocked(id: UUID) throws {
        try validateStoreDirectories()
        guard let context = try deletionContext(for: id) else {
            try validateStoreDirectories()
            return
        }
        let quarantined = try quarantineMedia(for: context)
        do {
            try deleteSessionArtifacts(in: context)
        } catch {
            try rollbackDeletion(context, quarantined: quarantined)
            throw error
        }
        discardQuarantinedMedia(quarantined)
        discardInterruptedTakes(of: context.session)
        observationIDsBySession[id] = nil
        codingSnapshotIDsBySession[id] = nil
        try validateStoreDirectories()
    }

    private func deletionContext(for id: UUID) throws -> SessionDeletionContext? {
        let metadataURL = fileURL(for: id)
        if try isSymbolicLink(metadataURL) { throw SessionStoreError.sessionMetadataIsSymbolicLink }
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { return nil }
        let metadataData = try Data(contentsOf: metadataURL)
        let session = try decoder.decode(CaptureSession.self, from: metadataData)
        try validateSessionOwnership(session, expectedID: id)
        let journal = try deletionJournal(for: id)
        return SessionDeletionContext(
            metadataURL: metadataURL, metadataData: metadataData, session: session,
            journalURL: journal.observationURL, journalData: journal.observationData,
            codingJournalURL: journal.codingURL, codingJournalData: journal.codingData,
            media: try validatedDeletionMedia(for: session)
        )
    }

    private func deletionJournal(for id: UUID) throws -> (
        observationURL: URL, observationData: Data?, codingURL: URL, codingData: Data?
    ) {
        let observationURL = try validatedObservationJournalURL(for: id)
        let codingURL = try validatedCodingSnapshotJournalURL(for: id)
        return (
            observationURL,
            try deletionJournalData(at: observationURL, symbolicLinkError: .observationJournalIsSymbolicLink),
            codingURL,
            try deletionJournalData(at: codingURL, symbolicLinkError: .codingSnapshotJournalIsSymbolicLink)
        )
    }

    private func deletionJournalData(at url: URL, symbolicLinkError: SessionStoreError) throws -> Data? {
        if try isSymbolicLink(url) { throw symbolicLinkError }
        return FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }

    private func validatedDeletionMedia(for session: CaptureSession) throws -> [(url: URL, mediaID: UUID)] {
        var mediaByPath: [String: (url: URL, mediaID: UUID)] = [:]
        let canonicalURL = try validatedRecordingURL(
            for: "\(session.id.uuidString).mp4", expectedSessionID: session.id
        )
        mediaByPath[canonicalURL.path] = (canonicalURL, session.id)
        try addReferencedDeletionMedia(for: session, to: &mediaByPath)
        let media = mediaByPath.values.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
        try validateDeletionMedia(media)
        return media
    }

    private func addReferencedDeletionMedia(
        for session: CaptureSession, to mediaByPath: inout [String: (url: URL, mediaID: UUID)]
    ) throws {
        if let path = session.recordingRelativePath {
            let url = try validatedRecordingURL(for: path, expectedSessionID: session.id)
            mediaByPath[url.path] = (url, session.id)
        }
        for asset in session.mediaAssets {
            try validateMediaAsset(asset, sessionID: session.id)
            let url = try validatedRecordingURL(for: asset.relativePath)
            mediaByPath[url.path] = (url, asset.role == .ownRecorded ? session.id : asset.id)
        }
    }

    private func validateDeletionMedia(_ media: [(url: URL, mediaID: UUID)]) throws {
        for item in media {
            if try isSymbolicLink(item.url) { throw SessionStoreError.recordingFileIsSymbolicLink }
            guard FileManager.default.fileExists(atPath: item.url.path) else { continue }
            guard try fileType(at: item.url) == .typeRegular else {
                throw SessionStoreError.recordingArtifactIsNotRegularFile
            }
        }
    }

    private func quarantineMedia(for context: SessionDeletionContext) throws -> [QuarantinedMedia] {
        var quarantined: [QuarantinedMedia] = []
        do {
            for item in context.media where FileManager.default.fileExists(atPath: item.url.path) {
                let moved = try quarantineMedia(item, sessionID: context.session.id)
                quarantined.append(moved)
            }
            return quarantined
        } catch {
            try restoreQuarantinedMedia(quarantined)
            throw error
        }
    }

    private func quarantineMedia(
        _ item: (url: URL, mediaID: UUID), sessionID: UUID
    ) throws -> QuarantinedMedia {
        let name = deletionQuarantineFileName(
            sessionID: sessionID, transactionID: UUID(), mediaID: item.mediaID
        )
        guard deletionQuarantineIdentity(for: name) != nil else {
            throw SessionStoreError.invalidRecordingFileName
        }
        let quarantine = item.url.deletingLastPathComponent().appendingPathComponent(name)
        if try isSymbolicLink(quarantine) { throw SessionStoreError.recordingFileIsSymbolicLink }
        guard !FileManager.default.fileExists(atPath: quarantine.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.moveItem(at: item.url, to: quarantine)
        return QuarantinedMedia(original: item.url, quarantine: quarantine)
    }

    private func deleteSessionArtifacts(in context: SessionDeletionContext) throws {
        try FileManager.default.removeItem(at: context.metadataURL)
        try removeJournalIfPresent(context.journalData, at: context.journalURL, error: .observationJournalInvalid)
        try removeCodingJournalIfPresent(context.codingJournalData, at: context.codingJournalURL)
    }

    private func removeJournalIfPresent(
        _ data: Data?, at url: URL, error: SessionStoreError
    ) throws {
        guard data != nil else { return }
        guard try fileType(at: url) == .typeRegular else { throw error }
        try FileManager.default.removeItem(at: url)
    }

    private func removeCodingJournalIfPresent(_ data: Data?, at url: URL) throws {
        guard data != nil else { return }
        guard try fileType(at: url) == .typeRegular else {
            throw SessionStoreError.codingSnapshotJournalInvalid
        }
        try persistenceFaultHook?(.beforeCodingJournalDeletion)
        try FileManager.default.removeItem(at: url)
    }

    private func rollbackDeletion(
        _ context: SessionDeletionContext, quarantined: [QuarantinedMedia]
    ) throws {
        do {
            try restoreJournal(context.journalData, at: context.journalURL)
            try restoreJournal(context.codingJournalData, at: context.codingJournalURL)
            try restoreQuarantinedMedia(quarantined)
            try restoreArtifact(context.metadataData, at: context.metadataURL, protection: .complete)
            try validateStoreDirectories()
        } catch {
            throw SessionStoreError.sessionMetadataRollbackFailed
        }
    }

    private func restoreJournal(_ data: Data?, at url: URL) throws {
        guard let data else { return }
        try restoreArtifact(data, at: url, protection: .completeUnlessOpen)
    }

    private func restoreQuarantinedMedia(_ media: [QuarantinedMedia]) throws {
        for item in media.reversed() where FileManager.default.fileExists(atPath: item.quarantine.path) {
            guard !FileManager.default.fileExists(atPath: item.original.path) else {
                throw CocoaError(.fileWriteFileExists)
            }
            try FileManager.default.moveItem(at: item.quarantine, to: item.original)
        }
    }

    private func restoreArtifact(_ data: Data, at url: URL, protection: FileProtectionType) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            let isLink = try isSymbolicLink(url)
            let type = try fileType(at: url)
            let contentsMatch = try Data(contentsOf: url) == data
            guard !isLink, type == .typeRegular, contentsMatch
            else { throw SessionStoreError.sessionMetadataRollbackFailed }
        } else {
            try data.write(to: url, options: [.atomic])
        }
        try applyAndVerifyLocalArtifactPolicy(to: url, fileProtection: protection)
        guard try Data(contentsOf: url) == data else { throw SessionStoreError.sessionMetadataRollbackFailed }
    }

    private func discardQuarantinedMedia(_ media: [QuarantinedMedia]) {
        for item in media { try? FileManager.default.removeItem(at: item.quarantine) }
    }

    /// Prepares and returns the protected, backup-excluded default recording destination.
    public func prepareRecordingURL(for session: CaptureSession) throws -> URL {
        try queue.sync {
            try validateStoreDirectories()
            try prepareRootDirectory()
            let directory = try prepareRecordingsDirectory()
            let url = directory.appendingPathComponent("\(session.id.uuidString).mp4")
            if try isSymbolicLink(url) { throw SessionStoreError.recordingFileIsSymbolicLink }
            try validateStoreDirectories()
            return url
        }
    }

    /// Reserves a unique capture destination whose exact name records its owning session.
    /// Callers should write only `.videographr-<session UUID>-<transaction UUID>.mp4`
    /// files so startup reconciliation can distinguish staging from user media. Staging of an
    /// unresolved take survives a relaunch as an interrupted take; other staging is removed.
    public func prepareStagedRecordingURL(
        for sessionID: UUID,
        transactionID: UUID = UUID()
    ) throws -> URL {
        try queue.sync {
            try validateStoreDirectories()
            try prepareRootDirectory()
            let directory = try prepareRecordingsDirectory()
            let fileName = stagedRecordingFileName(sessionID: sessionID, transactionID: transactionID)
            guard stagedRecordingIdentity(for: fileName) != nil else {
                throw SessionStoreError.invalidReservedStagingFileName
            }
            let url = directory.appendingPathComponent(fileName, isDirectory: false)
            if try isSymbolicLink(url) { throw SessionStoreError.recordingFileIsSymbolicLink }
            if FileManager.default.fileExists(atPath: url.path) {
                throw CocoaError(.fileWriteFileExists)
            }
            try validateStoreDirectories()
            return url
        }
    }

    /// Idempotently removes only an exact reserved staging file inside `Recordings/`.
    /// Canonical movies, malformed names, links, directories, and outside paths are rejected.
    public func discardStagedRecording(at url: URL) throws {
        try queue.sync { try discardStagedRecordingLocked(at: url) }
    }

    private func discardStagedRecordingLocked(at url: URL) throws {
        try validateStoreDirectories()
        let validatedURL = try validatedStagedRecordingURL(for: url)
        try removeStagedRecordingIfPresent(at: validatedURL)
        try validateStoreDirectories()
    }

    private func validatedStagedRecordingURL(for url: URL) throws -> URL {
        guard stagedRecordingIdentity(for: url.lastPathComponent) != nil else {
            throw SessionStoreError.invalidReservedStagingFileName
        }
        let validatedURL = try validatedRecordingURL(for: url.lastPathComponent)
        guard validatedURL.standardizedFileURL == url.standardizedFileURL else {
            throw SessionStoreError.recordingOutsideStore
        }
        return validatedURL
    }

    private func removeStagedRecordingIfPresent(at url: URL) throws {
        try removeRegularRecording(at: url, nonRegularError: .recordingArtifactIsNotRegularFile)
    }

    /// The preserved staged media of an interrupted take, or nil when none exists.
    /// Links and non-regular files are rejected, never followed.
    public func interruptedTakeURL(sessionID: UUID, transactionID: UUID) throws -> URL? {
        try queue.sync { try interruptedTakeURLLocked(sessionID: sessionID, transactionID: transactionID) }
    }

    private func interruptedTakeURLLocked(sessionID: UUID, transactionID: UUID) throws -> URL? {
        try validateStoreDirectories()
        let url = try validatedRecordingURL(
            for: stagedRecordingFileName(sessionID: sessionID, transactionID: transactionID)
        )
        if try isSymbolicLink(url) { throw SessionStoreError.recordingFileIsSymbolicLink }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard try fileType(at: url) == .typeRegular else {
            throw SessionStoreError.recordingArtifactIsNotRegularFile
        }
        return url
    }

    /// Moves an interrupted take's staged media to the session's canonical recording name so the
    /// ordinary finalization path can inspect and attach it. An occupied destination is refused.
    public func promoteInterruptedTake(sessionID: UUID, transactionID: UUID) throws -> URL {
        try queue.sync {
            // Serialized with deletion on this queue: a deleted session never receives media.
            try requireSessionMetadata(for: sessionID)
            guard let stagedURL = try interruptedTakeURLLocked(sessionID: sessionID, transactionID: transactionID) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let canonicalURL = try canonicalRecordingURL(for: sessionID)
            guard !FileManager.default.fileExists(atPath: canonicalURL.path) else {
                throw CocoaError(.fileWriteFileExists)
            }
            try FileManager.default.moveItem(at: stagedURL, to: canonicalURL)
            try applyAndVerifyLocalArtifactPolicy(to: canonicalURL)
            try validateStoreDirectories()
            return canonicalURL
        }
    }

    /// Reverses `promoteInterruptedTake` when attaching failed, so the media stays an
    /// interrupted take awaiting an operator decision instead of an unreferenced canonical file.
    public func demoteInterruptedTake(sessionID: UUID, transactionID: UUID) throws {
        try queue.sync {
            // Only media of a still-unresolved take may become staging; a finalized take's
            // staging would be removed as stale at the next launch.
            try requireUnresolvedTake(sessionID: sessionID, transactionID: transactionID)
            let canonicalURL = try canonicalRecordingURL(for: sessionID)
            guard FileManager.default.fileExists(atPath: canonicalURL.path) else { throw CocoaError(.fileNoSuchFile) }
            guard try fileType(at: canonicalURL) == .typeRegular else {
                throw SessionStoreError.recordingArtifactIsNotRegularFile
            }
            guard try interruptedTakeURLLocked(sessionID: sessionID, transactionID: transactionID) == nil else {
                throw CocoaError(.fileWriteFileExists)
            }
            let stagedURL = try validatedRecordingURL(
                for: stagedRecordingFileName(sessionID: sessionID, transactionID: transactionID)
            )
            try FileManager.default.moveItem(at: canonicalURL, to: stagedURL)
            try applyAndVerifyLocalArtifactPolicy(to: stagedURL)
            try validateStoreDirectories()
        }
    }

    private func canonicalRecordingURL(for sessionID: UUID) throws -> URL {
        let url = try validatedRecordingURL(
            for: "\(sessionID.uuidString)\(Self.movieExtension)", expectedSessionID: sessionID
        )
        if try isSymbolicLink(url) { throw SessionStoreError.recordingFileIsSymbolicLink }
        return url
    }

    private func requireUnresolvedTake(sessionID: UUID, transactionID: UUID) throws {
        try requireSessionMetadata(for: sessionID)
        let session = try decoder.decode(CaptureSession.self, from: Data(contentsOf: fileURL(for: sessionID)))
        try validateSessionOwnership(session, expectedID: sessionID)
        guard let manifest = session.takeManifests.first(where: { $0.id == transactionID }),
              RecordingStateMachine.isFinalizable(manifest)
        else { throw SessionStoreError.recordingFileNameMismatch }
    }

    private func requireSessionMetadata(for sessionID: UUID) throws {
        let metadataURL = fileURL(for: sessionID)
        if try isSymbolicLink(metadataURL) { throw SessionStoreError.sessionMetadataIsSymbolicLink }
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { throw CocoaError(.fileNoSuchFile) }
    }

    /// Interrupted takes are not session media yet; remove them once the session is gone.
    /// Startup reconciliation removes any staging whose session metadata is missing, so a
    /// failure here leaves no consented media behind past the next launch.
    private func discardInterruptedTakes(of session: CaptureSession) {
        for manifest in session.takeManifests {
            guard let url = try? interruptedTakeURLLocked(sessionID: session.id, transactionID: manifest.id) else {
                continue
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

}
