import Foundation
import GuidanceEngine
import SessionCore

@MainActor
private struct ExportPreparation {
    let eventID: UUID
    let projection: StudyExportProjection
    let authorizationTime: Date
    let source: CaptureSession
}

extension AppStore {
    /// Builds from a fresh persisted snapshot and durably writes an outbox row before disclosure.
    func prepareExportForSharing() async -> PreparedExport? {
        guard persistenceIsReady else { return nil }
        guard await flushPendingChanges() else { return nil }
        do {
            return try await preparePersistedExport(sessionID: session.id)
        } catch {
            studyPackageURL = nil
            lastStoreError = "Forschungspaket konnte nicht freigegeben werden: \(error.localizedDescription)"
            return nil
        }
    }

    private func preparePersistedExport(sessionID: UUID) async throws -> PreparedExport {
        guard let source = try await asyncStore.load(id: sessionID) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let preparation = try makeExportPreparation(from: source)
        let packageURL = try await packageWriter.build(
            session: source,
            exportID: preparation.eventID,
            provenance: BuildProvenanceFactory.export
        )
        do {
            let manifest = try await packageWriter.validatedManifest(at: packageURL, expectedSessionID: sessionID)
            let attempt = makeExportAttempt(preparation, manifest: manifest)
            let persisted = try await persistExportAttempt(attempt, sessionID: sessionID, projection: preparation.projection)
            applyPersistedSession(persisted)
            studyPackageURL = packageURL
            await reloadListAsync()
            return PreparedExport(id: preparation.eventID, sessionID: sessionID, packageURL: packageURL)
        } catch {
            await packageWriter.removePackage(at: packageURL)
            throw error
        }
    }

    private func makeExportPreparation(from source: CaptureSession) throws -> ExportPreparation {
        let projection = StudyExportProjection.make(from: source)
        let authorizationTime = Date()
        guard projection.requiredScopes.allSatisfy({ source.authorizes($0, at: authorizationTime) }) else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [
                NSLocalizedDescriptionKey: "Für Sekundärnutzung und externe Freigabe fehlen aktive, inhaltsbezogene Freigaben."
            ])
        }
        return ExportPreparation(
            eventID: UUID(),
            projection: projection,
            authorizationTime: authorizationTime,
            source: source
        )
    }

    private func makeExportAttempt(
        _ preparation: ExportPreparation,
        manifest: StudyExportManifest
    ) -> ExportEvent {
        var values = ExportEvent.Values()
        values.id = preparation.eventID
        values.exportedAt = preparation.authorizationTime
        values.operatorPseudonym = preparation.source.consentGrants
            .last(where: { $0.authorizes(.externalSharing, at: preparation.authorizationTime) })?
            .participantGroupPseudonym ?? "local-operator"
        values.operatorAuthenticationMethod = Self.currentOperatorAuthenticationMethod
        values.includedScopes = manifest.includedScopes
        values.fileDigests = manifest.fileDigests
        values.shareActivityIdentifier = "pending"
        values.status = .attempted
        return ExportEvent(values)
    }

    private func persistExportAttempt(
        _ attempt: ExportEvent,
        sessionID: UUID,
        projection: StudyExportProjection
    ) async throws -> CaptureSession {
        try await asyncStore.mutateSession(id: sessionID, includeJournals: true) { target in
            guard projection.requiredScopes.allSatisfy({ target.authorizes($0) }),
                  StudyExportProjection.make(from: target) == projection
            else {
                throw CocoaError(.fileWriteNoPermission, userInfo: [
                    NSLocalizedDescriptionKey: "Die Sitzung oder Freigabe hat sich während der Exportvorbereitung geändert. Bitte erneut versuchen."
                ])
            }
            target.exportEvents.append(attempt)
            target.updatedAt = Date()
        }
    }

    /// Finalizes an existing disclosure outbox row even if consent expires during the share sheet.
    func recordExportOutcome(
        _ prepared: PreparedExport,
        completed: Bool,
        shareActivityIdentifier: String?,
        failureDescription: String?
    ) async {
        let status = exportStatus(completed: completed, failureDescription: failureDescription)
        do {
            let persisted = try await persistExportOutcome(
                prepared,
                status: status,
                shareActivityIdentifier: shareActivityIdentifier,
                failureDescription: failureDescription
            )
            applyPersistedSession(persisted)
            await reloadListAsync()
        } catch {
            lastStoreError = exportOutcomeError(completed: completed, error: error)
        }
        await clearPreparedExport(prepared)
    }

    private func exportStatus(completed: Bool, failureDescription: String?) -> ExportEventStatus {
        guard completed else { return failureDescription == nil ? .cancelled : .failed }
        return .completed
    }

    private func persistExportOutcome(
        _ prepared: PreparedExport,
        status: ExportEventStatus,
        shareActivityIdentifier: String?,
        failureDescription: String?
    ) async throws -> CaptureSession {
        try await asyncStore.mutateSession(id: prepared.sessionID) { target in
            guard let index = target.exportEvents.firstIndex(where: { $0.id == prepared.id }) else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [
                    NSLocalizedDescriptionKey: "Der vorbereitete Exportversuch fehlt im lokalen Auditprotokoll."
                ])
            }
            guard target.exportEvents[index].finish(
                status: status,
                shareActivityIdentifier: shareActivityIdentifier,
                failureDescription: failureDescription
            ) else { return }
            target.updatedAt = Date()
        }
    }

    private func exportOutcomeError(completed: Bool, error: Error) -> String {
        completed
            ? "Export wurde geteilt; der vorbereitete Auditdatensatz bleibt offen, weil der Abschluss nicht gespeichert werden konnte: \(error.localizedDescription)"
            : "Exportstatus konnte nicht gespeichert werden: \(error.localizedDescription)"
    }

    private func clearPreparedExport(_ prepared: PreparedExport) async {
        await packageWriter.removePackage(at: prepared.packageURL)
        if studyPackageURL == prepared.packageURL { studyPackageURL = nil }
    }
}
