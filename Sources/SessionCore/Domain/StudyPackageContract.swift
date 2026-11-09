import Foundation

public enum StudyPackageContract: Sendable {
    public static let manifestFile = "manifest.json"
    public static let sessionFile = "session.json"
    public static let annotationsFile = "annotations.jsonl"
    public static let observationsFile = "observations.jsonl"
    public static let codingSnapshotsFile = "coding-snapshots.jsonl"
    /// Content members in manifest (sorted) order.
    public static let expectedContentFiles = [
        annotationsFile, codingSnapshotsFile, observationsFile, sessionFile
    ]
    public static let expectedPackageFiles = [manifestFile] + expectedContentFiles
    public static let maximumContentFileBytes = 32 * 1_024 * 1_024

    /// Validates the semantic package contract independently of filesystem I/O.
    /// Filesystem callers must additionally reject links and non-regular files.
    public static func validate(
        manifest: StudyExportManifest,
        expectedSessionID: UUID,
        fileData: [String: Data]
    ) -> [String] {
        var failures = manifestFailures(manifest, expectedSessionID: expectedSessionID, fileData: fileData)
        failures.append(contentsOf: fileFailures(manifest, fileData: fileData))
        return failures.sorted()
    }

    private static func manifestFailures(
        _ manifest: StudyExportManifest,
        expectedSessionID: UUID,
        fileData: [String: Data]
    ) -> [String] {
        schemaFailures(manifest, expectedSessionID: expectedSessionID)
            + contentFailures(manifest, fileData: fileData)
            + scopeFailures(manifest)
            + provenanceFailures(manifest)
    }

    private static func schemaFailures(
        _ manifest: StudyExportManifest,
        expectedSessionID: UUID
    ) -> [String] {
        var failures = manifest.schemaVersion == StudyExportManifest.schemaVersion ? [] : ["unsupported-schema"]
        if manifest.sessionID != expectedSessionID { failures.append("session-mismatch") }
        return failures
    }

    private static func contentFailures(
        _ manifest: StudyExportManifest,
        fileData: [String: Data]
    ) -> [String] {
        var failures: [String] = []
        if manifest.contentFiles != expectedContentFiles
            || Set(manifest.contentFiles).count != manifest.contentFiles.count {
            failures.append("unexpected-content-files")
        }
        if Set(manifest.fileDigests.keys) != Set(expectedContentFiles) {
            failures.append("unexpected-digest-files")
        }
        if Set(fileData.keys) != Set(expectedContentFiles) {
            failures.append("missing-or-extra-data")
        }
        return failures
    }

    private static func scopeFailures(_ manifest: StudyExportManifest) -> [String] {
        var failures: [String] = []
        let requiredScopes: Set<ConsentScope> = [.collection, .secondaryUse, .externalSharing]
        if !requiredScopes.isSubset(of: manifest.includedScopes) {
            failures.append("missing-required-scope")
        }
        failures += modeScopeFailures(for: manifest)
        return failures
    }

    private static func modeScopeFailures(for manifest: StudyExportManifest) -> [String] {
        let includesResearch = manifest.includedScopes.contains(.researchProcessing)
        let failureByModeAndResearchScope: [OperatingMode: [Bool: [String]]] = [
            .evidenceSafe: [true: ["safe-mode-research-scope"], false: []],
            .experimentalResearch: [true: [], false: ["experimental-scope-missing"]]
        ]
        return failureByModeAndResearchScope[manifest.operatingMode]?[includesResearch] ?? []
    }

    private static func provenanceFailures(_ manifest: StudyExportManifest) -> [String] {
        var failures: [String] = []
        if manifest.provenance.algorithmVersion?.isEmpty != false
            || manifest.provenance.evidenceRegistryVersion?.isEmpty != false {
            failures.append("incomplete-generator-provenance")
        }
        return failures
    }

    private static func fileFailures(
        _ manifest: StudyExportManifest,
        fileData: [String: Data]
    ) -> [String] {
        var failures: [String] = []
        for name in expectedContentFiles {
            guard let data = fileData[name] else { continue }
            failures.append(contentsOf: fileFailure(name: name, data: data, manifest: manifest))
        }
        return failures
    }

    private static func fileFailure(
        name: String,
        data: Data,
        manifest: StudyExportManifest
    ) -> [String] {
        var failures: [String] = []
        if data.count > maximumContentFileBytes { failures.append("oversized:\(name)") }
        let actual = SessionCoding.sha256Hex(data)
        if manifest.fileDigests[name] != actual { failures.append("digest-mismatch:\(name)") }
        return failures
    }
}

enum StudyPackageFilesystemError: Error {
    case invalidPackageRoot
    case invalidMember(String)
    case unexpectedMembers
}
