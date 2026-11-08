import Foundation
import SessionCore

extension AppStore {
    @discardableResult
    func recordingCompletionIsUnknown(_ transaction: RecordingTransaction) async -> Bool {
        do {
            let persisted = try await mutateRecordingTransaction(transaction) { target, index in
                _ = RecordingStateMachine.completionUnknown(
                    transactionID: target.takeManifests[index].id,
                    in: &target,
                    at: Date()
                )
            }
            if session.id == persisted.id { applyPersistedSession(persisted) }
            return true
        } catch {
            lastStoreError = "Unbestätigter Aufnahmeabschluss konnte nicht dauerhaft markiert werden: \(error.localizedDescription)"
            return false
        }
    }

    func mutateRecordingTransaction(
        _ transaction: RecordingTransaction,
        _ mutation: @escaping @Sendable (inout CaptureSession, Int) -> Void
    ) async throws -> CaptureSession {
        try await asyncStore.mutateSession(id: transaction.sessionID) { target in
            guard let index = target.takeManifests.firstIndex(where: {
                $0.id == transaction.transactionID
            }) else { return }
            mutation(&target, index)
        }
    }

    func failPreparedRecording(sessionID: UUID, transactionID: UUID, stagedURL: URL?, reason: String) async {
        do {
            if let stagedURL { try? await asyncStore.discardStagedRecording(at: stagedURL) }
            let failedAt = Date()
            let persisted = try await asyncStore.mutateSession(id: sessionID) {
                _ = RecordingStateMachine.failed(
                    transactionID: transactionID,
                    reason: reason,
                    in: &$0,
                    at: failedAt
                )
            }
            await applyFailedRecordingSession(persisted)
        } catch {
            lastStoreError = "Fehlgeschlagener Take konnte nicht dauerhaft geschlossen werden: \(error.localizedDescription)"
        }
    }

    private func applyFailedRecordingSession(_ persisted: CaptureSession) async {
        if session.id == persisted.id { applyPersistedSession(persisted) }
        invalidateCachedPackages(for: persisted.id)
        await reloadListAsync()
    }
}

/// Takes cut off by app termination: their media was kept at startup and waits for an explicit
/// operator decision. Recovery re-checks the frozen consent and reads the media before it is
/// attached through the ordinary finalization path; discarding is never implicit.
@MainActor
extension AppStore {
    static let interruptedTakeFinalRoute = "Nach App-Abbruch wiederhergestellt; Audioroute am Aufnahmeende unbekannt"

    /// Unresolved takes of `session` that no capture in this process owns.
    func interruptedTakeCandidateIDs(in session: CaptureSession) -> [UUID] {
        session.takeManifests
            .filter { $0.effectiveLifecycleState == .completionUnknown }
            .map(\.id)
            .filter { !recordingTransactionsOfThisLaunch.contains($0) }
    }

    /// Interrupted takes of the active session whose media still exists, staged or (after a
    /// recovery cut off between promotion and attachment) under the canonical name.
    func pendingInterruptedTakeIDs() async -> [UUID] {
        let current = session
        var pending: [UUID] = []
        for transactionID in interruptedTakeCandidateIDs(in: current) {
            if (try? await asyncStore.interruptedTakeURL(sessionID: current.id, transactionID: transactionID)) != nil {
                pending.append(transactionID)
            } else if await interruptedTakeHasCanonicalMedia(transactionID, in: current) {
                pending.append(transactionID)
            }
        }
        return pending
    }

    private func interruptedTakeHasCanonicalMedia(_ transactionID: UUID, in session: CaptureSession) async -> Bool {
        guard let assetID = session.takeManifests.first(where: { $0.id == transactionID })?.mediaAssetID,
              let asset = session.mediaAssets.first(where: { $0.id == assetID })
        else { return false }
        return (try? await asyncStore.validatedMediaURL(for: asset, sessionID: session.id)) != nil
    }

    /// A take of this launch whose written media could not be attached for any reason other than a
    /// refused frozen consent. Its media is kept as an interrupted take and offered in Reflect now;
    /// it is never marked `failed`, because failed media is removed at the next launch.
    func keepUnresolvedTake(_ transaction: RecordingTransaction, reason: String) async {
        let marked = await recordingCompletionIsUnknown(transaction)
        // If demotion fails the media stays under the canonical name, which is offered as well.
        try? await asyncStore.demoteInterruptedTake(
            sessionID: transaction.sessionID,
            transactionID: transaction.transactionID
        )
        recordingTransactionsOfThisLaunch.remove(transaction.transactionID)
        invalidateCachedPackages(for: transaction.sessionID)
        await reloadListAsync()
        // On failure the real error set by recordingCompletionIsUnknown stays visible.
        guard marked else { return }
        lastStoreError = "Aufnahme konnte nicht übernommen werden und bleibt aufbewahrt: \(reason) "
            + "In Reflektieren „Prüfen und übernehmen“ oder „Verwerfen“ wählen."
    }

    /// Verifies and attaches an interrupted take. Returns the operator-facing outcome. Every
    /// failure keeps the media as an interrupted take; only `discardInterruptedTake` removes it.
    func recoverInterruptedTake(_ transactionID: UUID) async -> String {
        guard persistenceIsReady else { return "Die lokale Ablage ist noch nicht bereit." }
        let sessionID = session.id
        let canonicalURL: URL
        do {
            guard let current = try await asyncStore.load(id: sessionID),
                  let manifest = current.takeManifests.first(where: { $0.id == transactionID }),
                  manifest.effectiveLifecycleState == .completionUnknown,
                  !recordingTransactionsOfThisLaunch.contains(transactionID),
                  let authorization = manifest.authorization
            else { return "Diese unterbrochene Aufnahme ist nicht mehr offen." }
            guard current.authorizes(authorization, at: Date()) else {
                return "Die Aufnahmefreigabe dieses Takes ist nicht mehr aktiv. Die Aufnahme kann nur verworfen werden."
            }
            if let staged = try await asyncStore.interruptedTakeURL(sessionID: sessionID, transactionID: transactionID) {
                // Read the media before it takes the canonical name; unreadable media stays staged.
                _ = try await mediaInspector.inspect(url: staged)
                _ = try await asyncStore.promoteInterruptedTake(sessionID: sessionID, transactionID: transactionID)
            }
            canonicalURL = try await asyncStore.prepareRecordingURL(for: current)
        } catch {
            return "Unterbrochene Aufnahme konnte nicht geprüft werden und bleibt aufbewahrt: \(error.localizedDescription)"
        }
        do {
            try await attachFinalizedMedia(
                for: RecordingTransaction(sessionID: sessionID, transactionID: transactionID, generation: 0),
                finalizedURL: canonicalURL,
                runtimeStatus: CaptureRuntimeStatus(audioRoute: Self.interruptedTakeFinalRoute)
            )
            return "Unterbrochene Aufnahme geprüft und als Take übernommen."
        } catch {
            let reason = error.localizedDescription
            do {
                try await asyncStore.demoteInterruptedTake(sessionID: sessionID, transactionID: transactionID)
            } catch {
                // The take stays completionUnknown with canonical media, which is offered again.
                return "Unterbrochene Aufnahme konnte nicht übernommen werden und bleibt unter dem Sitzungsnamen aufbewahrt: \(reason)"
            }
            return "Unterbrochene Aufnahme konnte nicht übernommen werden und bleibt aufbewahrt: \(reason)"
        }
    }

    /// Removes an interrupted take's media on the operator's explicit request and closes the take.
    func discardInterruptedTake(_ transactionID: UUID) async -> String {
        guard persistenceIsReady else { return "Die lokale Ablage ist noch nicht bereit." }
        let current = session
        let sessionID = current.id
        guard interruptedTakeCandidateIDs(in: current).contains(transactionID) else {
            return "Diese unterbrochene Aufnahme ist nicht mehr offen."
        }
        do {
            if try await asyncStore.interruptedTakeURL(sessionID: sessionID, transactionID: transactionID) == nil,
               await interruptedTakeHasCanonicalMedia(transactionID, in: current) {
                // Media left under the canonical name by a cut-off recovery is staged again first.
                try await asyncStore.demoteInterruptedTake(sessionID: sessionID, transactionID: transactionID)
            }
            if let staged = try await asyncStore.interruptedTakeURL(sessionID: sessionID, transactionID: transactionID) {
                try await asyncStore.discardStagedRecording(at: staged)
            }
        } catch {
            return "Unterbrochene Aufnahme konnte nicht verworfen werden: \(error.localizedDescription)"
        }
        await failPreparedRecording(
            sessionID: sessionID,
            transactionID: transactionID,
            stagedURL: nil,
            reason: "Unterbrochene Aufnahme vom Operator verworfen."
        )
        let closed = session.id != sessionID
            || session.takeManifests.first(where: { $0.id == transactionID })?.effectiveLifecycleState == .failed
        return closed
            ? "Unterbrochene Aufnahme verworfen."
            : "Unterbrochene Aufnahme konnte nicht geschlossen werden: \(lastStoreError ?? "unbekannter Fehler")"
    }
}
