import Foundation
import SessionCore

@MainActor
extension AppStore {
    /// Attaches final media metadata to the originating transaction, never the selected session.
    func attachRecording(
        for transaction: RecordingTransaction,
        finalizedURL: URL,
        runtimeStatus: CaptureRuntimeStatus
    ) async -> Bool {
        guard persistenceIsReady else { return false }
        do {
            try await attachFinalizedMedia(
                for: transaction,
                finalizedURL: finalizedURL,
                runtimeStatus: runtimeStatus
            )
            return true
        } catch {
            let message = error.localizedDescription
            await recordingDidFail(transaction, reason: message)
            lastStoreError = message
            return false
        }
    }

    /// Inspects and attaches canonical media to its transaction. Throws without failing the take,
    /// so interrupted-take recovery can keep the media for another operator decision.
    func attachFinalizedMedia(
        for transaction: RecordingTransaction,
        finalizedURL: URL,
        runtimeStatus: CaptureRuntimeStatus
    ) async throws {
        let context = try await recordingFinalizationContext(
            for: transaction,
            finalizedURL: finalizedURL
        )
        let persisted = try await finalizeRecording(
            context,
            runtimeStatus: runtimeStatus
        )
        if session.id == persisted.id {
            applyPersistedSession(persisted)
            cacheMediaURL(
                context.canonicalURL,
                for: context.manifest.mediaAssetID,
                in: persisted
            )
        }
        invalidateCachedPackages(for: persisted.id)
        await reloadListAsync()
    }

    private struct RecordingFinalizationContext {
        let initial: CaptureSession
        let manifest: CaptureTakeManifest
        let authorization: CaptureAuthorizationSnapshot
        let endedAt: Date
        let canonicalURL: URL
    }

    private func recordingFinalizationContext(
        for transaction: RecordingTransaction,
        finalizedURL: URL
    ) async throws -> RecordingFinalizationContext {
        guard let initial = try await asyncStore.load(id: transaction.sessionID),
              let manifest = initial.takeManifests.first(where: { $0.id == transaction.transactionID }),
              let authorization = manifest.authorization,
              RecordingStateMachine.isFinalizable(manifest)
        else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSLocalizedDescriptionKey: "Abgeschlossene Aufnahme konnte keinem vorbereiteten Take zugeordnet werden."
            ])
        }
        guard initial.authorizes(authorization, at: Date()) else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [
                NSLocalizedDescriptionKey: "Die eingefrorene Aufnahmefreigabe war bei der Finalisierung nicht mehr aktiv."
            ])
        }
        let canonicalURL = try await asyncStore.prepareRecordingURL(for: initial)
        guard finalizedURL.standardizedFileURL == canonicalURL.standardizedFileURL else {
            throw CocoaError(.fileWriteInvalidFileName, userInfo: [
                NSLocalizedDescriptionKey: "Abgeschlossene Aufnahme hat keinen gültigen Sitzungsdateinamen."
            ])
        }
        try await asyncStore.secureFinalizedRecording(at: canonicalURL)
        return RecordingFinalizationContext(
            initial: initial,
            manifest: manifest,
            authorization: authorization,
            endedAt: Date(),
            canonicalURL: canonicalURL
        )
    }

    private func finalizeRecording(
        _ context: RecordingFinalizationContext,
        runtimeStatus: CaptureRuntimeStatus
    ) async throws -> CaptureSession {
        let inspected = try await mediaInspector.inspect(url: context.canonicalURL)
        let metadata = FinalizedMediaMetadata(
            durationMilliseconds: inspected.durationMilliseconds,
            sha256: inspected.sha256,
            codec: inspected.codec,
            resolution: inspected.resolution,
            frameRate: inspected.frameRate
        )
        return try await asyncStore.mutateSession(
            id: context.initial.id,
            includeJournals: true
        ) { target in
            guard let manifestIndex = target.takeManifests.firstIndex(where: { $0.id == context.manifest.id }),
                  RecordingStateMachine.isFinalizable(target.takeManifests[manifestIndex]),
                  target.authorizes(context.authorization, at: context.endedAt)
            else {
                throw CocoaError(.fileWriteNoPermission, userInfo: [
                    NSLocalizedDescriptionKey: "Die eingefrorene Aufnahmefreigabe ist bei der Finalisierung nicht mehr aktiv."
                ])
            }
            guard target.mediaAssets.contains(where: {
                $0.id == target.takeManifests[manifestIndex].mediaAssetID
            }) else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [
                    NSLocalizedDescriptionKey: "Medienmanifest und Aufnahme stimmen nicht überein."
                ])
            }
            _ = RecordingStateMachine.finalized(
                transactionID: context.manifest.id,
                metadata: metadata,
                finalRoute: runtimeStatus.audioRoute,
                canonicalFileName: context.canonicalURL.lastPathComponent,
                in: &target,
                at: context.endedAt
            )
        }
    }

    func attachCaptureObservation(_ observation: CaptureObservation, for id: UUID) async {
        guard persistenceIsReady else { return }
        if session.id == id, !session.authorizes(.collection, at: observation.observedAt) {
            return
        }
        do {
            guard try await asyncStore.appendCaptureObservationIfAuthorized(
                observation,
                toSession: id,
                at: observation.observedAt
            ) else { return }
            applyCaptureObservation(observation, to: id)
            invalidateCachedPackages(for: id)
        } catch {
            lastStoreError = error.localizedDescription
        }
    }

    private func applyCaptureObservation(_ observation: CaptureObservation, to id: UUID) {
        guard session.id == id else { return }
        var updated = session
        if !updated.captureObservations.contains(where: { $0.id == observation.id }) {
            updated.captureObservations.append(observation)
        }
        updated.updatedAt = max(updated.updatedAt, observation.observedAt)
        replaceSession(updated)
    }

    func attachCodingSnapshot(_ snapshot: ResearchCodingSnapshot, for id: UUID, recordingIsActive: Bool) async {
        guard persistenceIsReady, recordingIsActive else { return }
        do {
            try await asyncStore.appendCodingSnapshot(snapshot, toSession: id)
            if session.id == id {
                var updated = session
                updated.appendCodingSnapshot(snapshot)
                replaceSession(updated)
            }
            invalidateCachedPackages(for: id)
        } catch {
            lastStoreError = error.localizedDescription
        }
    }
}
