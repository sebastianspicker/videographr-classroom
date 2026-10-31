import Foundation

extension SessionStore {
    enum CanonicalRecordingRecovery {
        case legacyOrFinalized
        case finalizationPending(CaptureSession)
        case rollback(CaptureSession)
        case ambiguous
    }

    func appendDiagnostic(
        _ fileName: String, reason: RecordingArtifactDiagnosticReason,
        to state: inout RecordingArtifactReconciliationState
    ) {
        state.diagnostics.append(RecordingArtifactDiagnostic(fileName: fileName, reason: reason))
    }

    struct CanonicalRecordingUpdate {
        let session: CaptureSession
        let data: Data
        let url: URL
        let fileName: String
    }

    func reconcileQuarantineCandidate(
        _ url: URL, identity: DeletionQuarantineIdentity?, in directory: URL,
        state: inout RecordingArtifactReconciliationState
    ) throws {
        guard let identity else {
            appendDiagnostic(url.lastPathComponent, reason: .invalidDeletionQuarantineName, to: &state)
            return
        }
        try reconcileQuarantinedRecording(url, identity: identity, in: directory, state: &state)
    }

    func reconcileStagingCandidate(
        _ url: URL, identity: (sessionID: UUID, transactionID: UUID)?,
        state: inout RecordingArtifactReconciliationState
    ) throws {
        guard let identity else {
            appendDiagnostic(url.lastPathComponent, reason: .invalidReservedStagingName, to: &state)
            return
        }
        if activeImportedMediaTransactions.values.contains(where: {
            $0.transaction.staging.lastPathComponent == url.lastPathComponent
        }) { return }
        if try preserveInterruptedTake(url, identity: identity, state: &state) { return }
        try removeStagedRecording(url, state: &state)
    }

    /// At startup no capture is in flight, so a staged take whose session still holds the
    /// unresolved manifest was cut off by termination. Consented media is kept as
    /// `completionUnknown` for an explicit operator decision instead of being deleted.
    /// Returns false only when the file is disposable: its session is gone, or its take
    /// is already finalized or failed.
    func preserveInterruptedTake(
        _ url: URL, identity: (sessionID: UUID, transactionID: UUID),
        state: inout RecordingArtifactReconciliationState
    ) throws -> Bool {
        let fileName = url.lastPathComponent
        guard try fileType(at: url) == .typeRegular else { return false }
        let metadataURL = fileURL(for: identity.sessionID)
        if try !isSymbolicLink(metadataURL), !FileManager.default.fileExists(atPath: metadataURL.path) {
            return false
        }
        guard let metadata = try reconciliationMetadata(
            for: identity.sessionID, artifactName: fileName, state: &state
        ) else { return true }
        guard let manifest = metadata.session.takeManifests.first(where: { $0.id == identity.transactionID }),
              manifest.sessionID == metadata.session.id,
              RecordingStateMachine.isFinalizable(manifest)
        else { return false }
        do {
            try applyAndVerifyLocalArtifactPolicy(to: url)
        } catch {
            appendDiagnostic(fileName, reason: .artifactPolicyInvalid, to: &state)
        }
        var pending = metadata.session
        if RecordingStateMachine.completionUnknown(
            transactionID: identity.transactionID, in: &pending, at: Date()
        ) {
            guard try persistCanonicalRecordingLink(
                CanonicalRecordingUpdate(session: pending, data: metadata.data, url: metadata.url, fileName: fileName),
                state: &state, recordsRelink: false
            ) else { return true }
        }
        state.preservedInterruptedTakeFileNames.append(fileName)
        return true
    }

    func recordArtifactLinkDiagnostic(
        _ fileName: String, classification: RecordingArtifactClassification,
        state: inout RecordingArtifactReconciliationState
    ) {
        guard classification.isRecognized else { return }
        appendDiagnostic(fileName, reason: .artifactIsSymbolicLink, to: &state)
    }

    func quarantineMediaIsLinked(
        _ identity: DeletionQuarantineIdentity,
        canonicalName: String, session: CaptureSession
    ) -> Bool {
        let assetIsLinked = session.mediaAssets.contains { $0.relativePath == canonicalName }
        return assetIsLinked || session.recordingRelativePath == canonicalName
            || (identity.mediaID == identity.sessionID && session.recordingRelativePath == nil)
    }

    func canonicalRecordingRecovery(
        for session: CaptureSession, fileName: String
    ) -> CanonicalRecordingRecovery {
        guard canonicalRecordingLinkIsCompatible(session, fileName: fileName) else { return .ambiguous }
        return canonicalTakeRecovery(for: session, fileName: fileName)
    }

    func canonicalTakeRecovery(
        for session: CaptureSession, fileName: String
    ) -> CanonicalRecordingRecovery {
        guard !session.takeManifests.isEmpty else { return .legacyOrFinalized }
        guard let asset = canonicalOwnRecordedAsset(in: session, fileName: fileName) else {
            return failedManifestOnlyRecovery(for: session, fileName: fileName)
        }
        guard let manifest = canonicalTakeManifest(for: asset, in: session) else { return .ambiguous }
        return canonicalManifestRecovery(
            manifest, session: session, fileName: fileName, assetID: asset.id
        )
    }

    func canonicalRecordingLinkIsCompatible(_ session: CaptureSession, fileName: String) -> Bool {
        session.recordingRelativePath.map { $0 == fileName } ?? true
    }

    func canonicalOwnRecordedAsset(
        in session: CaptureSession, fileName: String
    ) -> SessionMediaAsset? {
        let assets = session.mediaAssets.filter {
            $0.role == .ownRecorded && $0.relativePath == fileName
        }
        guard assets.count == 1 else { return nil }
        return assets[0]
    }

    func canonicalTakeManifest(
        for asset: SessionMediaAsset, in session: CaptureSession
    ) -> CaptureTakeManifest? {
        let manifests = session.takeManifests.filter { $0.mediaAssetID == asset.id }
        guard manifests.count == 1, let manifest = manifests.first else { return nil }
        return manifest.sessionID == session.id ? manifest : nil
    }

    func canonicalManifestRecovery(
        _ manifest: CaptureTakeManifest, session: CaptureSession,
        fileName: String, assetID: UUID
    ) -> CanonicalRecordingRecovery {
        switch manifest.effectiveLifecycleState {
        case .finalized:
            return .legacyOrFinalized
        case .prepared, .recording, .completionUnknown:
            return .finalizationPending(markingFinalizationPending(session, manifestID: manifest.id))
        case .failed:
            return .rollback(rollingBackCanonicalRecording(session, fileName: fileName, assetID: assetID))
        }
    }

    func failedManifestOnlyRecovery(
        for session: CaptureSession, fileName: String
    ) -> CanonicalRecordingRecovery {
        guard session.mediaAssets.isEmpty,
              session.takeManifests.count == 1,
              let manifest = session.takeManifests.first,
              manifest.sessionID == session.id,
              manifest.effectiveLifecycleState == .failed
        else { return .ambiguous }
        return .rollback(rollingBackCanonicalRecording(
            session, fileName: fileName, assetID: manifest.mediaAssetID
        ))
    }

    func markingFinalizationPending(_ session: CaptureSession, manifestID: UUID) -> CaptureSession {
        let lifecycleState = session.takeManifests.first(where: { $0.id == manifestID })?.effectiveLifecycleState
        guard session.recordingRelativePath != nil || lifecycleState != .completionUnknown
        else { return session }
        var pending = session
        pending.recordingRelativePath = nil
        if let index = pending.takeManifests.firstIndex(where: { $0.id == manifestID }) {
            pending.takeManifests[index].lifecycleState = .completionUnknown
        }
        pending.updatedAt = Date()
        return pending
    }

    func rollingBackCanonicalRecording(
        _ session: CaptureSession, fileName: String, assetID: UUID
    ) -> CaptureSession {
        guard session.mediaAssets.contains(where: { $0.id == assetID })
                || session.recordingRelativePath == fileName
        else { return session }
        var rollback = session
        rollback.mediaAssets.removeAll { $0.id == assetID }
        if rollback.recordingRelativePath == fileName { rollback.recordingRelativePath = nil }
        rollback.updatedAt = Date()
        return rollback
    }

    func reconcileLegacyOrFinalizedCanonicalSession(
        _ metadata: ReconciliationSessionMetadata, fileName: String, sessionID: UUID,
        state: inout RecordingArtifactReconciliationState
    ) throws {
        if metadata.session.recordingRelativePath == fileName {
            state.alreadyLinkedSessionIDs.append(sessionID)
            return
        }
        guard metadata.session.recordingRelativePath == nil else {
            appendDiagnostic(fileName, reason: .sessionMetadataInvalid, to: &state)
            return
        }
        var linked = metadata.session
        linked.recordingRelativePath = fileName
        linked.updatedAt = Date()
        _ = try persistCanonicalRecordingLink(
            CanonicalRecordingUpdate(session: linked, data: metadata.data, url: metadata.url, fileName: fileName),
            state: &state, recordsRelink: true
        )
    }

    func preservePendingFinalization(
        _ pending: CaptureSession, replacing metadata: ReconciliationSessionMetadata,
        fileName: String, state: inout RecordingArtifactReconciliationState
    ) throws {
        if pending != metadata.session {
            guard try persistCanonicalRecordingLink(
                CanonicalRecordingUpdate(session: pending, data: metadata.data, url: metadata.url, fileName: fileName),
                state: &state, recordsRelink: false
            ) else { return }
        }
        appendDiagnostic(fileName, reason: .captureFinalizationPending, to: &state)
    }

    func rollbackCanonicalRecording(
        _ rollback: CaptureSession, replacing metadata: ReconciliationSessionMetadata,
        fileName: String, state: inout RecordingArtifactReconciliationState
    ) throws {
        if rollback != metadata.session {
            guard try persistCanonicalRecordingLink(
                CanonicalRecordingUpdate(session: rollback, data: metadata.data, url: metadata.url, fileName: fileName),
                state: &state, recordsRelink: false
            ) else { return }
        }
        do {
            let recordingURL = try validatedRecordingURL(for: fileName, expectedSessionID: rollback.id)
            try FileManager.default.removeItem(at: recordingURL)
            try validateStoreDirectories()
        } catch {
            appendDiagnostic(fileName, reason: .canonicalRollbackFailed, to: &state)
        }
    }

    func persistCanonicalRecordingLink(
        _ update: CanonicalRecordingUpdate,
        state: inout RecordingArtifactReconciliationState,
        recordsRelink: Bool
    ) throws -> Bool {
        do {
            try validateStoreDirectories()
            if try isSymbolicLink(update.url) { throw SessionStoreError.sessionMetadataIsSymbolicLink }
            try persistReconciledSession(update.session, replacing: update.data, at: update.url)
            if recordsRelink { state.relinkedSessionIDs.append(update.session.id) }
            return true
        } catch SessionStoreError.sessionMetadataRollbackFailed {
            throw SessionStoreError.sessionMetadataRollbackFailed
        } catch {
            appendDiagnostic(update.fileName, reason: .sessionMetadataUpdateFailed, to: &state)
            return false
        }
    }

    func validatedQuarantineMetadata(
        _ identity: DeletionQuarantineIdentity, artifactName: String,
        state: inout RecordingArtifactReconciliationState
    ) throws -> ReconciliationSessionMetadata? {
        guard let metadata = try reconciliationMetadata(
            for: identity.sessionID, artifactName: artifactName, state: &state
        ) else {
            return nil
        }
        let canonicalName = "\(identity.mediaID.uuidString).mp4"
        guard quarantineMediaIsLinked(identity, canonicalName: canonicalName, session: metadata.session) else {
            appendDiagnostic(artifactName, reason: .sessionMetadataInvalid, to: &state)
            return nil
        }
        return metadata
    }

    func isAvailableRestoreDestination(_ url: URL) throws -> Bool {
        if try isSymbolicLink(url) { return false }
        return try fileType(at: url) == nil
    }
}
