import Foundation
import GuidanceEngine
import SessionCore
import UIKit

@MainActor
extension AppStore {
    func prepareSessionForRecording(_ preparation: RecordingPreparation) async -> PreparedRecording? {
        guard persistenceIsReady else { return nil }
        guard await flushPendingChanges() else { return nil }
        if await !pendingInterruptedTakeIDs().isEmpty {
            lastStoreError = "Eine unterbrochene Aufnahme wartet in Reflektieren auf Prüfung oder Verwerfen."
            return nil
        }
        let preparedAt = Date()
        let admission: RecordingAdmission.Admission
        switch RecordingAdmission.evaluate(
            session: session,
            readiness: preparation.readiness,
            runtimeStatus: preparation.runtimeStatus,
            overrideReason: preparation.overrideReason,
            operatorPseudonym: preparation.operatorPseudonym,
            operatorAuthenticationMethod: Self.currentOperatorAuthenticationMethod,
            at: preparedAt
        ) {
        case let .success(admitted):
            admission = admitted
        case let .failure(refusal):
            lastStoreError = refusal.messageDE
            return nil
        }
        let authorization = admission.authorization
        let decision = admission.decision

        do {
            let artifacts = try await makePreparedRecordingArtifacts(
                for: preparation,
                authorization: authorization,
                decision: decision,
                preparedAt: preparedAt
            )
            recordingTransactionsOfThisLaunch.insert(preparation.transactionID)
            let persisted = try await persistPreparedRecording(artifacts)
            applyPersistedSession(persisted)
            invalidateCachedPackages(for: persisted.id)
            await reloadListAsync()
            return PreparedRecording(
                sessionID: persisted.id,
                transactionID: preparation.transactionID,
                mediaAssetID: artifacts.asset.id,
                url: artifacts.url,
                stagedURL: artifacts.stagedURL,
                authorization: authorization,
                plannedDurationMinutes: artifacts.session.plannedDurationMinutes
            )
        } catch {
            lastStoreError = error.localizedDescription
            return nil
        }
    }

    private struct PreparedRecordingArtifacts {
        let session: CaptureSession
        let url: URL
        let stagedURL: URL
        let asset: SessionMediaAsset
        let decision: CaptureDecision
        let provenance: BuildProvenance
        let manifest: CaptureTakeManifest
        let preparedAt: Date
    }

    private struct PreparedRecordingManifestInput {
        let transactionID: UUID
        let session: CaptureSession
        let asset: SessionMediaAsset
        let decision: CaptureDecision
        let provenance: BuildProvenance
        let authorization: CaptureAuthorizationSnapshot
        let runtimeStatus: CaptureRuntimeStatus
    }

    private func makePreparedRecordingArtifacts(
        for preparation: RecordingPreparation,
        authorization: CaptureAuthorizationSnapshot,
        decision: CaptureDecision,
        preparedAt: Date
    ) async throws -> PreparedRecordingArtifacts {
        try verifyStorageCapacity(for: session.plannedDurationMinutes)
        let frozen = session
        let url = try await asyncStore.prepareRecordingURL(for: frozen)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [
                NSLocalizedDescriptionKey: "Der geschützte Aufnahmeplatz ist bereits belegt."
            ])
        }
        let stagedURL = try await asyncStore.prepareStagedRecordingURL(
            for: frozen.id,
            transactionID: preparation.transactionID
        )
        let asset = preparedRecordingAsset(at: url)
        let provenance = BuildProvenanceFactory.capture(for: frozen.operatingMode)
        let manifest = preparedRecordingManifest(PreparedRecordingManifestInput(
            transactionID: preparation.transactionID,
            session: frozen,
            asset: asset,
            decision: decision,
            provenance: provenance,
            authorization: authorization,
            runtimeStatus: preparation.runtimeStatus
        ))
        return PreparedRecordingArtifacts(
            session: frozen,
            url: url,
            stagedURL: stagedURL,
            asset: asset,
            decision: decision,
            provenance: provenance,
            manifest: manifest,
            preparedAt: preparedAt
        )
    }

    private func preparedRecordingAsset(at url: URL) -> SessionMediaAsset {
        var values = SessionMediaAsset.Values()
        values.role = .ownRecorded
        values.relativePath = url.lastPathComponent
        values.originalFileName = url.lastPathComponent
        return SessionMediaAsset(values)
    }

    private func preparedRecordingManifest(
        _ input: PreparedRecordingManifestInput
    ) -> CaptureTakeManifest {
        var values = CaptureTakeManifest.Values()
        values.id = input.transactionID
        values.sessionID = input.session.id
        values.mediaAssetID = input.asset.id
        values.decision = input.decision
        values.provenance = input.provenance
        values.cameraConfiguration = [
            "negotiated": input.runtimeStatus.videoConfiguration,
            "plannedDurationMinutes": String(input.session.plannedDurationMinutes),
            "batteryPercent": input.runtimeStatus.batteryPercent.map(String.init) ?? "unavailable",
            "thermalState": input.runtimeStatus.thermalState
        ]
        values.audioConfiguration = [
            "route": input.runtimeStatus.audioRoute,
            "spokenAudioPlaybackCheck": input.runtimeStatus.spokenAudioCheckCompleted ? "completed" : "overridden-or-missing"
        ]
        values.deviceDescription = "\(UIDevice.current.model) · \(UIDevice.current.systemName)"
        values.operatingSystemVersion = UIDevice.current.systemVersion
        values.lifecycleState = .prepared
        values.authorization = input.authorization
        return CaptureTakeManifest(values)
    }

    private func persistPreparedRecording(
        _ artifacts: PreparedRecordingArtifacts
    ) async throws -> CaptureSession {
        try await asyncStore.mutateSession(id: artifacts.session.id) { current in
            guard let authorization = artifacts.manifest.authorization,
                  current.authorizes(authorization, at: Date()),
                  !current.mediaAssets.contains(where: { $0.role == .ownRecorded }),
                  current.recordingRelativePath == nil
            else {
                throw CocoaError(.fileWriteNoPermission, userInfo: [
                    NSLocalizedDescriptionKey: "Die vorbereitende Freigabe ist nicht mehr aktiv oder der Aufnahmeplatz ist belegt."
                ])
            }
            guard RecordingStateMachine.prepare(
                PreparedRecordingMutation(
                    transactionID: artifacts.manifest.id,
                    asset: artifacts.asset,
                    decision: artifacts.decision,
                    manifest: artifacts.manifest,
                    provenance: artifacts.provenance,
                    preparedAt: artifacts.preparedAt
                ),
                in: &current
            ) else {
                throw CocoaError(.fileWriteNoPermission, userInfo: [
                    NSLocalizedDescriptionKey: "Die vorbereitende Freigabe ist nicht mehr aktiv oder der Aufnahmeplatz ist belegt."
                ])
            }
        }
    }

    func cancelPreparedRecording(_ prepared: PreparedRecording) async {
        await failPreparedRecording(
            sessionID: prepared.sessionID,
            transactionID: prepared.transactionID,
            stagedURL: prepared.stagedURL,
            reason: "AVFoundation hat den vorbereiteten Start nicht angenommen."
        )
    }

    func recordingAuthorizationIsValid(_ prepared: PreparedRecording, at date: Date = Date()) -> Bool {
        let target = session.id == prepared.sessionID
            ? session
            : allSessions.first(where: { $0.id == prepared.sessionID })
        return target?.authorizes(prepared.authorization, at: date) ?? false
    }

    func markRecordingBegan(_ transaction: RecordingTransaction) async {
        do {
            let persisted = try await mutateRecordingTransaction(transaction) { target, index in
                _ = RecordingStateMachine.began(
                    transactionID: target.takeManifests[index].id,
                    in: &target,
                    at: Date()
                )
            }
            if session.id == persisted.id { applyPersistedSession(persisted) }
        } catch {
            lastStoreError = error.localizedDescription
        }
    }

    func recordingDidFail(_ transaction: RecordingTransaction, reason: String) async {
        await failPreparedRecording(
            sessionID: transaction.sessionID,
            transactionID: transaction.transactionID,
            stagedURL: nil,
            reason: reason
        )
    }

}
