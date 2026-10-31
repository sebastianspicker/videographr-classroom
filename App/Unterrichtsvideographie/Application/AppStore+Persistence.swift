import Foundation
import GuidanceEngine
import SessionCore

@MainActor
extension AppStore {
    func scheduleAutosave(delayNanoseconds: UInt64) {
        autosaveTask?.cancel()
        let revision = editRevision
        let generation = activeSessionGeneration
        autosaveTask = Task { [weak self] in
            if delayNanoseconds > 0 {
                do { try await Task.sleep(nanoseconds: delayNanoseconds) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            guard let self else { return }
            _ = await self.persistCurrentSession(
                revision: revision,
                generation: generation
            )
        }
    }

    func persistCurrentSession(revision: Int, generation: Int) async -> Bool {
        guard activeSessionGeneration == generation else { return true }
        persistenceOperationSequence &+= 1
        let operation = persistenceOperationSequence
        let snapshot = session
        let previousMediaSignature = mediaSignature(for: snapshot)
        saveState = .saving
        do {
            try await persistenceWillStoreHook?(operation)
            let stored = try await asyncStore.mergeDraftSession(snapshot)
            await persistenceDidStoreHook?(operation)
            let resultStillTargetsActiveSession = activeSessionGeneration == generation
                && session.id == snapshot.id
            guard resultStillTargetsActiveSession,
                  revision >= savedRevision,
                  operation > latestAppliedPersistenceOperation
            else {
                if resultStillTargetsActiveSession, savedRevision < editRevision {
                    scheduleAutosave(delayNanoseconds: 0)
                }
                return true
            }
            latestAppliedPersistenceOperation = operation
            upsertSessionSummary(stored)
            let persisted = preservingHydratedHistories(in: stored, from: session)
            if editRevision == revision {
                replaceSession(persisted)
                savedRevision = revision
                saveState = .saved
            } else {
                var merged = persisted
                merged.mergeDraftFields(from: session)
                replaceSession(merged)
                saveState = .unsaved
            }
            if mediaSignature(for: session) != previousMediaSignature
                || mediaSignature(for: session) != mediaResolutionSignature {
                await refreshMediaURLs()
            }
            return true
        } catch {
            let failureStillTargetsActiveSession = activeSessionGeneration == generation
                && session.id == snapshot.id
            guard failureStillTargetsActiveSession,
                  operation > latestAppliedPersistenceOperation
            else {
                if failureStillTargetsActiveSession, savedRevision < editRevision {
                    scheduleAutosave(delayNanoseconds: 0)
                }
                return true
            }
            latestAppliedPersistenceOperation = operation
            let message = error.localizedDescription
            saveState = .failed(message)
            lastStoreError = message
            return false
        }
    }

    func reloadListAsync() async {
        do {
            let listing = try await asyncStore.listSessionSummariesWithDiagnostics()
            allSessions = listing.sessions
            applyListingDiagnostics(listing)
        } catch {
            lastStoreError = error.localizedDescription
        }
    }

    func applyPersistedSession(_ persisted: CaptureSession) {
        guard session.id == persisted.id else { return }
        persistenceOperationSequence &+= 1
        latestAppliedPersistenceOperation = persistenceOperationSequence
        let hydrated = preservingHydratedHistories(in: persisted, from: session)
        if savedRevision < editRevision {
            var merged = hydrated
            merged.mergeDraftFields(from: session)
            replaceSession(merged)
            saveState = .unsaved
        } else {
            replaceSession(hydrated)
            savedRevision = editRevision
            saveState = .saved
        }
        lastStoreError = nil
        upsertSessionSummary(persisted)
    }

    func preservingHydratedHistories(
        in persisted: CaptureSession,
        from current: CaptureSession
    ) -> CaptureSession {
        guard persisted.id == current.id else { return persisted }
        var merged = persisted
        if merged.captureObservations.isEmpty, !current.captureObservations.isEmpty {
            merged.captureObservations = current.captureObservations
        }
        if merged.codingSnapshots.isEmpty, !current.codingSnapshots.isEmpty {
            merged.codingSnapshots = current.codingSnapshots
        }
        return merged
    }

    func refreshMediaURLs() async {
        let current = session
        var resolved: [UUID: URL] = [:]
        for asset in current.mediaAssets {
            if let url = try? await asyncStore.validatedMediaURL(for: asset, sessionID: current.id) {
                resolved[asset.id] = url
            }
        }
        guard session.id == current.id,
              mediaSignature(for: session) == mediaSignature(for: current)
        else { return }
        replaceMediaURLs(resolved)
        mediaResolutionSignature = mediaSignature(for: current)
    }

    func invalidateCachedPackages(for sessionID: UUID) {
        if session.id == sessionID { studyPackageURL = nil }
        Task { [packageWriter] in
            await packageWriter.scheduleUnleasedPackageRemoval(for: sessionID)
        }
    }

    private func upsertSessionSummary(_ persisted: CaptureSession) {
        var summary = persisted
        summary.captureObservations.removeAll()
        summary.codingSnapshots.removeAll()
        allSessions.removeAll { $0.id == summary.id }
        allSessions.append(summary)
        allSessions.sort {
            $0.updatedAt == $1.updatedAt
                ? $0.id.uuidString < $1.id.uuidString
                : $0.updatedAt > $1.updatedAt
        }
    }

    func verifyStorageCapacity(for plannedMinutes: Int) throws {
        let values = try store.rootDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values.volumeAvailableCapacityForImportantUsage else { return }
        let required = Int64(plannedMinutes) * 60 * CaptureCapacity.estimatedBytesPerSecond
            + CaptureCapacity.minimumFreeCapacityBytes
        guard available >= required else {
            throw CocoaError(.fileWriteOutOfSpace, userInfo: [
                NSLocalizedDescriptionKey: "Zu wenig freier Speicher für \(plannedMinutes) Minuten plus Sicherheitsreserve."
            ])
        }
    }

    func applyListingDiagnostics(_ listing: SessionStoreListing) {
        guard !listing.failures.isEmpty else {
            if case .failed = saveState { return }
            lastStoreError = nil
            return
        }
        lastStoreError = listing.failures.map {
            "\($0.fileName): \($0.errorDescription)"
        }.joined(separator: "\n")
    }

    func applyReconciliationStatus(_ report: RecordingArtifactReconciliationReport) {
        var notes = reconciliationSummaryNotes(report)
        notes.append(contentsOf: report.diagnostics.map {
            "Aufnahmeartefakt \($0.fileName) wurde nicht verändert: \($0.reason.localizedDescription)"
        })
        guard !notes.isEmpty else { return }
        lastStoreError = [lastStoreError, notes.joined(separator: "\n")]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    private func reconciliationSummaryNotes(
        _ report: RecordingArtifactReconciliationReport
    ) -> [String] {
        [
            (report.removedStagingFileNames.count, "Unterbrochene Aufnahme bereinigt"),
            (
                report.preservedInterruptedTakeFileNames.count,
                "Unterbrochene Aufnahme aufbewahrt, in Reflektieren prüfen oder verwerfen"
            ),
            (report.relinkedSessionIDs.count, "Abgeschlossene Aufnahme wieder zugeordnet"),
            (report.restoredQuarantineFileNames.count, "Unterbrochene Medienbereinigung zurückgerollt"),
            (report.removedQuarantineFileNames.count, "Abgeschlossene Medienbereinigung abgeschlossen")
        ].compactMap { count, label in
            count == 0 ? nil : "\(label): \(count)"
        }
    }

    func applyPersistenceReconciliationStatus(_ report: PersistenceArtifactReconciliationReport) {
        var notes: [String] = []
        if !report.removedOrphanJournalFileNames.isEmpty {
            notes.append("Verwaiste Beobachtungsjournale bereinigt: \(report.removedOrphanJournalFileNames.count)")
        }
        if !report.removedOrphanImportedFileNames.isEmpty {
            notes.append("Nicht zugeordnete Videoimporte bereinigt: \(report.removedOrphanImportedFileNames.count)")
        }
        notes.append(contentsOf: report.diagnostics.map {
            "Persistenzartefakt \($0.fileName) wurde nicht verändert: \($0.reason.localizedDescription)"
        })
        guard !notes.isEmpty else { return }
        lastStoreError = [lastStoreError, notes.joined(separator: "\n")]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    static func makeSession(buildProvenance: BuildProvenance) -> CaptureSession {
        var values = CaptureSession.Values()
        values.buildProvenance = buildProvenance
        return CaptureSession(values)
    }

    static var currentOperatorAuthenticationMethod: String {
        return "deviceOwnerAuthentication"
    }

    static func defaultStore() -> SessionStore {
        return SessionStore()
    }

    func deleteSessionAndMedia(_ id: UUID) {
        Task { [weak self] in
            guard let self, await self.flushPendingChanges() else { return }
            do {
                try await self.asyncStore.deleteSessionAndMedia(id: id)
                await self.packageWriter.removeUnleasedPackages(for: id)
                self.lastStoreError = nil
                await self.reloadListAsync()
                if self.session.id == id {
                    if let nextID = self.allSessions.first?.id,
                       let loaded = try await self.asyncStore.load(id: nextID)
                    {
                        self.replaceSession(loaded)
                    } else {
                        self.replaceSession(Self.makeSession(buildProvenance: BuildProvenanceFactory.capture(for: .evidenceSafe)))
                    }
                    self.activeSessionGeneration &+= 1
                    self.editRevision = 0
                    self.savedRevision = 0
                    self.saveState = .saved
                    await self.refreshMediaURLs()
                    self.studyPackageURL = nil
                }
            } catch {
                self.lastStoreError = error.localizedDescription
            }
        }
    }
}
