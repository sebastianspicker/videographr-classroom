import Foundation

extension SessionStore {
    struct RecordingArtifactReconciliationState {
        var removedStagingFileNames: [String] = []
        var restoredQuarantineFileNames: [String] = []
        var removedQuarantineFileNames: [String] = []
        var preservedInterruptedTakeFileNames: [String] = []
        var relinkedSessionIDs: [UUID] = []
        var alreadyLinkedSessionIDs: [UUID] = []
        var diagnostics: [RecordingArtifactDiagnostic] = []
        var linkedImportedFileNames: Set<String> = []
    }

    struct ReconciliationSessionMetadata {
        let url: URL
        let data: Data
        let session: CaptureSession
    }

    private struct QuarantineRestorePlan {
        let canonicalURL: URL
        let canonicalFileName: String
        let metadata: ReconciliationSessionMetadata
        let needsMetadataLink: Bool
    }

    struct RecordingArtifactClassification {
        let staged: Bool
        let quarantined: Bool
        let canonical: Bool
        let stagingCandidate: Bool
        let quarantineCandidate: Bool

        var isRecognized: Bool {
            staged || quarantined || canonical || stagingCandidate || quarantineCandidate
        }
    }

    public func reconcileRecordingArtifacts() throws -> RecordingArtifactReconciliationReport {
        try queue.sync {
            try reconcileRecordingArtifactsLocked()
        }
    }

    private func reconcileRecordingArtifactsLocked() throws -> RecordingArtifactReconciliationReport {
        try validateStoreDirectories()
        try prepareRootDirectory()
        let directory = try prepareRecordingsDirectory()
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var state = RecordingArtifactReconciliationState()
        let knownSessions = try knownSessionsForReconciliation()
        state.linkedImportedFileNames = Set(knownSessions.values.flatMap { session in
            session.mediaAssets.compactMap { asset in
                guard asset.role == .otherImported,
                      asset.relativePath == "\(asset.id.uuidString).mp4",
                      knownSessions[asset.id] == nil else { return nil }
                return asset.relativePath
            }
        })
        for url in urls {
            try validateStoreDirectories()
            try reconcileRecordingArtifact(url, in: directory, state: &state)
        }
        try validateStoreDirectories()
        var values = RecordingArtifactReconciliationReport.Values(
            removedStagingFileNames: state.removedStagingFileNames,
            relinkedSessionIDs: state.relinkedSessionIDs,
            alreadyLinkedSessionIDs: state.alreadyLinkedSessionIDs,
            diagnostics: state.diagnostics
        )
        values.restoredQuarantineFileNames = state.restoredQuarantineFileNames
        values.removedQuarantineFileNames = state.removedQuarantineFileNames
        values.preservedInterruptedTakeFileNames = state.preservedInterruptedTakeFileNames
        return RecordingArtifactReconciliationReport(values)
    }

    private func reconcileRecordingArtifact(
        _ url: URL, in directory: URL, state: inout RecordingArtifactReconciliationState
    ) throws {
        let fileName = url.lastPathComponent
        let stagedIdentity = stagedRecordingIdentity(for: fileName)
        let quarantineIdentity = deletionQuarantineIdentity(for: fileName)
        let canonicalSessionID = canonicalRecordingSessionID(for: fileName)
        let isStagingCandidate = fileName.hasPrefix(Self.stagedRecordingPrefix)
        let isQuarantineCandidate = fileName.hasPrefix(Self.deletionQuarantinePrefix)
        let classification = RecordingArtifactClassification(
            staged: stagedIdentity != nil, quarantined: quarantineIdentity != nil,
            canonical: canonicalSessionID != nil, stagingCandidate: isStagingCandidate,
            quarantineCandidate: isQuarantineCandidate
        )
        if try isSymbolicLink(url) {
            recordArtifactLinkDiagnostic(fileName, classification: classification, state: &state)
            return
        }
        if isQuarantineCandidate {
            try reconcileQuarantineCandidate(url, identity: quarantineIdentity, in: directory, state: &state)
            return
        }
        if isStagingCandidate {
            try reconcileStagingCandidate(url, identity: stagedIdentity, state: &state)
            return
        }
        guard let sessionID = canonicalSessionID else { return }
        try reconcileCanonicalRecording(url, sessionID: sessionID, state: &state)
    }

    func removeStagedRecording(
        _ url: URL, state: inout RecordingArtifactReconciliationState
    ) throws {
        guard try fileType(at: url) == .typeRegular else {
            appendDiagnostic(url.lastPathComponent, reason: .unsupportedArtifactType, to: &state)
            return
        }
        do {
            try FileManager.default.removeItem(at: url)
            try validateStoreDirectories()
            state.removedStagingFileNames.append(url.lastPathComponent)
        } catch {
            appendDiagnostic(url.lastPathComponent, reason: .stagingRemovalFailed, to: &state)
        }
    }

    func reconcileQuarantinedRecording(
        _ url: URL, identity: DeletionQuarantineIdentity,
        in directory: URL, state: inout RecordingArtifactReconciliationState
    ) throws {
        guard try fileType(at: url) == .typeRegular else {
            appendDiagnostic(url.lastPathComponent, reason: .unsupportedArtifactType, to: &state)
            return
        }
        let metadataURL = fileURL(for: identity.sessionID)
        if try isSymbolicLink(metadataURL) {
            appendDiagnostic(url.lastPathComponent, reason: .sessionMetadataIsSymbolicLink, to: &state)
        } else if FileManager.default.fileExists(atPath: metadataURL.path) {
            try restoreQuarantinedRecording(url, identity: identity, in: directory, state: &state)
        } else {
            try removeQuarantinedRecording(url, state: &state)
        }
    }

    private func restoreQuarantinedRecording(
        _ url: URL, identity: DeletionQuarantineIdentity,
        in directory: URL, state: inout RecordingArtifactReconciliationState
    ) throws {
        guard let plan = try quarantineRestorePlan(url, identity: identity, in: directory, state: &state) else {
            return
        }
        do {
            try applyAndVerifyLocalArtifactPolicy(to: url)
        } catch {
            appendDiagnostic(url.lastPathComponent, reason: .artifactPolicyInvalid, to: &state)
            return
        }
        if plan.needsMetadataLink {
            guard try linkQuarantineSession(plan, fileName: url.lastPathComponent, state: &state) else {
                return
            }
        }
        try moveQuarantinedRecording(url, using: plan, state: &state)
    }

    private func quarantineRestorePlan(
        _ url: URL, identity: DeletionQuarantineIdentity,
        in directory: URL, state: inout RecordingArtifactReconciliationState
    ) throws -> QuarantineRestorePlan? {
        guard let metadata = try validatedQuarantineMetadata(identity, artifactName: url.lastPathComponent, state: &state) else { return nil }
        let canonicalName = "\(identity.mediaID.uuidString).mp4"
        let canonicalURL = directory.appendingPathComponent(canonicalName)
        guard try isAvailableRestoreDestination(canonicalURL) else {
            appendDiagnostic(
                url.lastPathComponent,
                reason: .canonicalRestoreDestinationOccupied,
                to: &state
            )
            return nil
        }
        return QuarantineRestorePlan(
            canonicalURL: canonicalURL, canonicalFileName: canonicalName, metadata: metadata,
            needsMetadataLink: identity.mediaID == identity.sessionID
                && metadata.session.recordingRelativePath == nil
                && !metadata.session.mediaAssets.contains { $0.relativePath == canonicalName }
        )
    }

    private func linkQuarantineSession(
        _ plan: QuarantineRestorePlan, fileName: String,
        state: inout RecordingArtifactReconciliationState
    ) throws -> Bool {
        var linked = plan.metadata.session
        linked.recordingRelativePath = plan.canonicalFileName
        linked.updatedAt = Date()
        do {
            try persistReconciledSession(linked, replacing: plan.metadata.data, at: plan.metadata.url)
            return true
        } catch SessionStoreError.sessionMetadataRollbackFailed {
            throw SessionStoreError.sessionMetadataRollbackFailed
        } catch {
            appendDiagnostic(fileName, reason: .sessionMetadataUpdateFailed, to: &state)
            return false
        }
    }

    private func moveQuarantinedRecording(
        _ url: URL, using plan: QuarantineRestorePlan,
        state: inout RecordingArtifactReconciliationState
    ) throws {
        do {
            try FileManager.default.moveItem(at: url, to: plan.canonicalURL)
        } catch {
            try rollbackQuarantineMetadataLinkIfNeeded(plan)
            appendDiagnostic(url.lastPathComponent, reason: .quarantineRestoreFailed, to: &state)
            return
        }
        try validateStoreDirectories()
        state.restoredQuarantineFileNames.append(url.lastPathComponent)
        if plan.needsMetadataLink { state.relinkedSessionIDs.append(plan.metadata.session.id) }
    }

    private func rollbackQuarantineMetadataLinkIfNeeded(_ plan: QuarantineRestorePlan) throws {
        guard plan.needsMetadataLink else { return }
        do {
            let linkedData = try Data(contentsOf: plan.metadata.url)
            try persistReconciledSession(
                plan.metadata.session, replacing: linkedData, at: plan.metadata.url
            )
        } catch {
            throw SessionStoreError.sessionMetadataRollbackFailed
        }
    }

    private func removeQuarantinedRecording(
        _ url: URL, state: inout RecordingArtifactReconciliationState
    ) throws {
        do {
            try FileManager.default.removeItem(at: url)
            try validateStoreDirectories()
            state.removedQuarantineFileNames.append(url.lastPathComponent)
        } catch {
            appendDiagnostic(url.lastPathComponent, reason: .quarantineRemovalFailed, to: &state)
        }
    }

    private func reconcileCanonicalRecording(
        _ url: URL, sessionID: UUID, state: inout RecordingArtifactReconciliationState
    ) throws {
        guard try fileType(at: url) == .typeRegular else {
            appendDiagnostic(url.lastPathComponent, reason: .unsupportedArtifactType, to: &state)
            return
        }
        if state.linkedImportedFileNames.contains(url.lastPathComponent) {
            do {
                try applyAndVerifyLocalArtifactPolicy(to: url)
            } catch {
                appendDiagnostic(url.lastPathComponent, reason: .artifactPolicyInvalid, to: &state)
            }
            return
        }
        guard let metadata = try reconciliationMetadata(
            for: sessionID, artifactName: url.lastPathComponent, state: &state
        ) else { return }
        do {
            try applyAndVerifyLocalArtifactPolicy(to: url)
        } catch {
            appendDiagnostic(url.lastPathComponent, reason: .artifactPolicyInvalid, to: &state)
            return
        }
        try reconcileCanonicalSession(
            metadata, fileName: url.lastPathComponent, sessionID: sessionID, state: &state
        )
    }

    func reconciliationMetadata(
        for sessionID: UUID, artifactName: String,
        state: inout RecordingArtifactReconciliationState
    ) throws -> ReconciliationSessionMetadata? {
        let url = fileURL(for: sessionID)
        if try isSymbolicLink(url) {
            appendDiagnostic(artifactName, reason: .sessionMetadataIsSymbolicLink, to: &state)
            return nil
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            appendDiagnostic(artifactName, reason: .sessionMetadataMissing, to: &state)
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let session = try decoder.decode(CaptureSession.self, from: data)
            try validateSessionOwnership(session, expectedID: sessionID)
            return ReconciliationSessionMetadata(url: url, data: data, session: session)
        } catch {
            appendDiagnostic(artifactName, reason: .sessionMetadataInvalid, to: &state)
            return nil
        }
    }

    private func reconcileCanonicalSession(
        _ metadata: ReconciliationSessionMetadata, fileName: String, sessionID: UUID,
        state: inout RecordingArtifactReconciliationState
    ) throws {
        switch canonicalRecordingRecovery(for: metadata.session, fileName: fileName) {
        case .legacyOrFinalized:
            try reconcileLegacyOrFinalizedCanonicalSession(
                metadata, fileName: fileName, sessionID: sessionID, state: &state
            )
        case .finalizationPending(let pending):
            try preservePendingFinalization(
                pending, replacing: metadata, fileName: fileName, state: &state
            )
        case .rollback(let rollback):
            try rollbackCanonicalRecording(
                rollback, replacing: metadata, fileName: fileName, state: &state
            )
        case .ambiguous:
            appendDiagnostic(fileName, reason: .canonicalRecoveryAmbiguous, to: &state)
        }
    }

}
