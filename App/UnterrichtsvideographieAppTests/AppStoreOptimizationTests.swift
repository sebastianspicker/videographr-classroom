import Foundation
import GuidanceEngine
import SessionCore
import XCTest

@testable import Unterrichtsvideographie

final class AppStoreOptimizationTests: XCTestCase {
    private enum ExpectedFailure: Error {
        case injected
    }

    private actor PersistenceGate {
        private var started = false
        private var startWaiters: [CheckedContinuation<Void, Never>] = []
        private var releaseContinuation: CheckedContinuation<Void, Never>?

        func block() async {
            started = true
            startWaiters.forEach { $0.resume() }
            startWaiters.removeAll()
            await withCheckedContinuation { releaseContinuation = $0 }
        }

        func waitUntilStarted() async {
            if started { return }
            await withCheckedContinuation { startWaiters.append($0) }
        }

        func release() {
            releaseContinuation?.resume()
            releaseContinuation = nil
        }
    }

    @MainActor
    func testDeferredBootstrapCannotPersistPlaceholderAndRecoversExistingSession() async throws {
        let root = try makeRoot()
        let store = SessionStore(rootDirectory: root)
        let existing = session(title: "Persisted session")
        try store.save(existing)
        let appStore = AppStore(store: store, bootstrapMode: .deferred)
        let placeholderID = appStore.session.id

        appStore.edit { $0.title = "Unsaved placeholder" }
        let flushedWhileLoading = await appStore.flushPendingChanges()

        XCTAssertFalse(flushedWhileLoading)
        XCTAssertNil(try store.load(id: placeholderID))
        XCTAssertEqual(appStore.bootstrapState, .loading)

        await appStore.bootstrap()

        XCTAssertEqual(appStore.bootstrapState, .ready)
        XCTAssertEqual(appStore.session.id, existing.id)
        XCTAssertEqual(appStore.session.title, existing.title)
    }

    @MainActor
    func testAutosaveUpsertsActiveSummaryAndRetainsSortedOtherSession() async throws {
        let root = try makeRoot()
        let store = SessionStore(rootDirectory: root)
        try store.save(session(title: "First"))
        try store.save(session(title: "Second"))
        let expectedIDs = try store.listSessionsWithDiagnostics().sessions.map(\.id)
        let appStore = AppStore(store: store, bootstrapMode: .deferred)
        await appStore.bootstrap()
        let activeID = try XCTUnwrap(expectedIDs.first)

        appStore.edit { $0.title = "Updated active" }
        let flushed = await appStore.flushPendingChanges()

        XCTAssertTrue(flushed)
        XCTAssertEqual(appStore.allSessions.count, 2)
        XCTAssertEqual(appStore.allSessions.first?.id, activeID)
        XCTAssertEqual(appStore.allSessions.first?.title, "Updated active")
        XCTAssertEqual(Set(appStore.allSessions.map(\.id)), Set(expectedIDs))
    }

    @MainActor
    func testOlderPersistenceContinuationCannotOverrideNewerSavedState() async throws {
        let root = try makeRoot()
        let store = SessionStore(rootDirectory: root)
        try store.save(session(title: "Initial"))
        let appStore = AppStore(store: store, bootstrapMode: .deferred)
        await appStore.bootstrap()
        let generation = appStore.activeSessionGeneration
        let gate = PersistenceGate()
        appStore.persistenceDidStoreHook = { operation in
            if operation == 1 { await gate.block() }
        }
        var draft = appStore.session
        draft.title = "Older draft"
        appStore.replaceSession(draft)
        appStore.editRevision = 1
        appStore.saveState = .unsaved
        let olderPersistence = Task {
            await appStore.persistCurrentSession(revision: 1, generation: generation)
        }
        await gate.waitUntilStarted()

        draft = appStore.session
        draft.title = "Newest draft"
        appStore.replaceSession(draft)
        appStore.editRevision = 2
        let newerSucceeded = await appStore.persistCurrentSession(
            revision: 2,
            generation: generation
        )
        await gate.release()
        let olderSucceeded = await olderPersistence.value

        XCTAssertTrue(newerSucceeded)
        XCTAssertTrue(olderSucceeded)
        XCTAssertEqual(appStore.session.title, "Newest draft")
        XCTAssertEqual(appStore.savedRevision, 2)
        XCTAssertEqual(appStore.saveState, .saved)
        XCTAssertEqual(try store.load(id: appStore.session.id)?.title, "Newest draft")
    }

    @MainActor
    func testRuntimePersistenceInvalidatesOlderAutosaveApplication() async throws {
        let root = try makeRoot()
        let store = SessionStore(rootDirectory: root)
        try store.save(session(title: "Initial"))
        let appStore = AppStore(store: store, bootstrapMode: .deferred)
        await appStore.bootstrap()
        let generation = appStore.activeSessionGeneration
        let gate = PersistenceGate()
        appStore.persistenceWillStoreHook = { operation in
            if operation == 1 { await gate.block() }
        }
        var draft = appStore.session
        draft.title = "Draft title"
        appStore.replaceSession(draft)
        appStore.editRevision = 1
        appStore.saveState = .unsaved
        let olderPersistence = Task {
            await appStore.persistCurrentSession(revision: 1, generation: generation)
        }
        await gate.waitUntilStarted()

        var runtime = try XCTUnwrap(store.load(id: appStore.session.id))
        runtime.captureDecisions.append(CaptureDecision())
        try store.save(runtime)
        let persistedRuntime = try XCTUnwrap(store.load(id: runtime.id))
        appStore.applyPersistedSession(persistedRuntime)
        await gate.release()
        _ = await olderPersistence.value
        let convergenceTask = try XCTUnwrap(appStore.autosaveTask)
        await convergenceTask.value

        XCTAssertEqual(appStore.session.title, "Draft title")
        XCTAssertEqual(appStore.session.captureDecisions.count, 1)
        XCTAssertEqual(appStore.savedRevision, 1)
        XCTAssertEqual(appStore.saveState, .saved)
        XCTAssertEqual(
            appStore.allSessions.first(where: { $0.id == appStore.session.id })?.title,
            "Draft title"
        )
        let durable = try XCTUnwrap(store.load(id: appStore.session.id))
        XCTAssertEqual(durable.title, "Draft title")
        XCTAssertEqual(durable.captureDecisions.count, 1)
    }

    @MainActor
    func testStaleAutosaveFailureSchedulesAutomaticConvergence() async throws {
        let root = try makeRoot()
        let store = SessionStore(rootDirectory: root)
        try store.save(session(title: "Initial"))
        let appStore = AppStore(store: store, bootstrapMode: .deferred)
        await appStore.bootstrap()
        let generation = appStore.activeSessionGeneration
        let gate = PersistenceGate()
        appStore.persistenceWillStoreHook = { operation in
            guard operation == 1 else { return }
            await gate.block()
            throw ExpectedFailure.injected
        }
        var draft = appStore.session
        draft.title = "Draft after failure"
        appStore.replaceSession(draft)
        appStore.editRevision = 1
        appStore.saveState = .unsaved
        let failingPersistence = Task {
            await appStore.persistCurrentSession(revision: 1, generation: generation)
        }
        await gate.waitUntilStarted()

        var runtime = try XCTUnwrap(store.load(id: appStore.session.id))
        runtime.captureDecisions.append(CaptureDecision())
        try store.save(runtime)
        appStore.applyPersistedSession(try XCTUnwrap(store.load(id: runtime.id)))
        await gate.release()
        _ = await failingPersistence.value
        let convergenceTask = try XCTUnwrap(appStore.autosaveTask)
        await convergenceTask.value

        XCTAssertEqual(appStore.saveState, .saved)
        XCTAssertEqual(appStore.savedRevision, 1)
        XCTAssertEqual(appStore.session.title, "Draft after failure")
        XCTAssertEqual(appStore.session.captureDecisions.count, 1)
        let durable = try XCTUnwrap(store.load(id: appStore.session.id))
        XCTAssertEqual(durable.title, "Draft after failure")
        XCTAssertEqual(durable.captureDecisions.count, 1)
    }

    @MainActor
    func testPersistentConvergenceFailureSurfacesWithoutAnotherRetry() async throws {
        let root = try makeRoot()
        let store = SessionStore(rootDirectory: root)
        try store.save(session(title: "Initial"))
        let appStore = AppStore(store: store, bootstrapMode: .deferred)
        await appStore.bootstrap()
        let generation = appStore.activeSessionGeneration
        let gate = PersistenceGate()
        appStore.persistenceWillStoreHook = { operation in
            if operation == 1 { await gate.block() }
            throw ExpectedFailure.injected
        }
        var draft = appStore.session
        draft.title = "Unsaved draft"
        appStore.replaceSession(draft)
        appStore.editRevision = 1
        appStore.saveState = .unsaved
        let staleFailure = Task {
            await appStore.persistCurrentSession(revision: 1, generation: generation)
        }
        await gate.waitUntilStarted()

        var runtime = try XCTUnwrap(store.load(id: appStore.session.id))
        runtime.captureDecisions.append(CaptureDecision())
        try store.save(runtime)
        appStore.applyPersistedSession(try XCTUnwrap(store.load(id: runtime.id)))
        await gate.release()
        _ = await staleFailure.value
        let convergenceTask = try XCTUnwrap(appStore.autosaveTask)
        await convergenceTask.value

        guard case .failed = appStore.saveState else {
            return XCTFail("Persistent convergence failure was not surfaced")
        }
        XCTAssertEqual(appStore.persistenceOperationSequence, 3)
        XCTAssertEqual(appStore.savedRevision, 0)
        XCTAssertEqual(appStore.session.title, "Unsaved draft")
        XCTAssertEqual(appStore.session.captureDecisions.count, 1)
    }

    @MainActor
    func testMalformedImportedMediaIsRolledBackAfterInspectionFailure() async throws {
        let root = try makeRoot()
        let store = SessionStore(rootDirectory: root)
        let existing = session(title: "Import", grants: [grant(scopes: [.localReflection])])
        try store.save(existing)
        let appStore = AppStore(store: store, bootstrapMode: .deferred)
        await appStore.bootstrap()
        let source = root.appendingPathComponent("malformed.mp4")
        try Data(repeating: 0x41, count: 32).write(to: source)

        await appStore.importMedia(from: source)

        XCTAssertNotNil(appStore.lastStoreError)
        XCTAssertTrue(appStore.session.mediaAssets.isEmpty)
        XCTAssertTrue(try XCTUnwrap(store.load(id: existing.id)).mediaAssets.isEmpty)
        let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: recordings.path), [])
    }

    @MainActor
    func testImmediateInMemoryConsentRevocationRejectsObservationBeforeAutosave() async throws {
        let root = try makeRoot()
        let store = SessionStore(rootDirectory: root)
        let existing = session(title: "Consent", grants: [grant(scopes: [.collection])])
        try store.save(existing)
        let appStore = AppStore(store: store, bootstrapMode: .deferred)
        await appStore.bootstrap()
        appStore.updateConsentGrant(ConsentGrantDraft(
            scopes: [.localReflection],
            documentIdentifier: "consent-form",
            documentVersion: "2",
            participantGroupPseudonym: "group-a",
            expiresAt: nil
        ))
        var values = CaptureObservation.Values()
        values.observedAt = Date().addingTimeInterval(1)

        await appStore.attachCaptureObservation(
            CaptureObservation(values),
            for: existing.id
        )
        _ = await appStore.flushPendingChanges()

        XCTAssertEqual(try store.loadCaptureObservations(forSession: existing.id), [])
    }

    @MainActor
    func testBurstPackageInvalidationCoalescesAndPreservesLeasedPackage() async throws {
        let builder = StudyPackageWriter()
        let exportSession = session(
            title: "Export",
            grants: [grant(scopes: [.collection, .secondaryUse, .externalSharing])]
        )
        let packageURL = try await builder.build(
            session: exportSession,
            exportID: UUID(),
            provenance: BuildProvenanceFactory.export
        )
        defer { try? FileManager.default.removeItem(at: packageURL) }

        for _ in 0..<20 {
            await builder.scheduleUnleasedPackageRemoval(for: exportSession.id)
        }
        await builder.flushScheduledInvalidations()
        let passCount = await builder.scheduledInvalidationPassCount

        XCTAssertEqual(passCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.path))
        await builder.removePackage(at: packageURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: packageURL.path))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
            .appendingPathComponent("AppStoreOptimizationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func session(
        title: String,
        grants: [ConsentGrant] = []
    ) -> CaptureSession {
        CaptureSession({
            var values = CaptureSession.Values()
            values.title = title
            values.consentGrants = grants
            return values
        }())
    }

    private func grant(scopes: Set<ConsentScope>) -> ConsentGrant {
        ConsentGrant({
            var values = ConsentGrant.Values()
            values.scopes = scopes
            values.documentIdentifier = "consent-form"
            values.documentVersion = "1"
            values.participantGroupPseudonym = "group-a"
            values.grantedAt = Date().addingTimeInterval(-60)
            return values
        }())
    }
}
