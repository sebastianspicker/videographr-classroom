import Foundation

public struct BuildProvenance: Codable, Equatable, Sendable {
    public struct Values: Sendable {
        public var semanticVersion = ""
        public var buildNumber = ""
        public var schemaVersion = SessionSchema.currentVersion
        public var algorithmVersion: String?
        public var evidenceRegistryVersion: String?

        public init() {}
    }

    public var semanticVersion: String
    public var buildNumber: String
    public var schemaVersion: Int
    public var algorithmVersion: String?
    public var evidenceRegistryVersion: String?

    public init(_ values: Values = Values()) {
        semanticVersion = values.semanticVersion
        buildNumber = values.buildNumber
        schemaVersion = values.schemaVersion
        algorithmVersion = values.algorithmVersion
        evidenceRegistryVersion = values.evidenceRegistryVersion
    }

    public var researchArtifactProvenance: ResearchArtifactProvenance? {
        guard let algorithmVersion,
              !algorithmVersion.isEmpty,
              let evidenceRegistryVersion,
              !evidenceRegistryVersion.isEmpty
        else { return nil }
        return ResearchArtifactProvenance((
            semanticVersion: semanticVersion,
            buildNumber: buildNumber,
            schemaVersion: schemaVersion,
            algorithmVersion: algorithmVersion,
            evidenceRegistryVersion: evidenceRegistryVersion
        ))
    }
}

public struct CaptureTakeManifest: Codable, Equatable, Identifiable, Sendable {
    public struct Values: Sendable {
        public var id = UUID()
        public var sessionID = UUID()
        public var mediaAssetID = UUID()
        public var startedAt = Date()
        public var endedAt: Date?
        public var durationMilliseconds: Int64?
        public var decision = CaptureDecision()
        public var provenance = BuildProvenance()
        public var cameraConfiguration: [String: String] = [:]
        public var audioConfiguration: [String: String] = [:]
        public var deviceDescription = ""
        public var operatingSystemVersion = ""
        public var finalizedAt: Date?
        public var lifecycleState: CaptureTakeLifecycleState? = .prepared
        public var authorization: CaptureAuthorizationSnapshot?
        public var failureReason: String?

        public init() {}
    }

    public var id: UUID
    public var sessionID: UUID
    public var mediaAssetID: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var durationMilliseconds: Int64?
    public var decision: CaptureDecision
    public var provenance: BuildProvenance
    public var cameraConfiguration: [String: String]
    public var audioConfiguration: [String: String]
    public var deviceDescription: String
    public var operatingSystemVersion: String
    public var finalizedAt: Date?
    public var lifecycleState: CaptureTakeLifecycleState?
    public var authorization: CaptureAuthorizationSnapshot?
    public var failureReason: String?

    public init(_ values: Values = Values()) {
        id = values.id
        sessionID = values.sessionID
        mediaAssetID = values.mediaAssetID
        startedAt = values.startedAt
        endedAt = values.endedAt
        durationMilliseconds = values.durationMilliseconds.map { max(0, $0) }
        decision = values.decision
        provenance = values.provenance
        cameraConfiguration = values.cameraConfiguration
        audioConfiguration = values.audioConfiguration
        deviceDescription = values.deviceDescription
        operatingSystemVersion = values.operatingSystemVersion
        finalizedAt = values.finalizedAt
        lifecycleState = values.lifecycleState
        authorization = values.authorization
        failureReason = values.failureReason
    }

    public var effectiveLifecycleState: CaptureTakeLifecycleState {
        lifecycleState ?? (finalizedAt == nil ? .prepared : .finalized)
    }
}

public enum CaptureObservationKind: String, Codable, Sendable {
    case periodic
    case transition
    case interruption
    case audioRouteChange
    case error
    case missing
}

/// Append-only capture record. `missingReason` prevents absent sensor data from being silently inferred.
public struct CaptureObservation: Codable, Equatable, Identifiable, Sendable {
    public struct Values: Sendable {
        public var id = UUID()
        public var observedAt = Date()
        public var kind: CaptureObservationKind = .periodic
        public var measurements: [String: Double] = [:]
        public var missingReason: String?
        public var note: String?

        public init() {}
    }

    public var id: UUID
    public var observedAt: Date
    public var kind: CaptureObservationKind
    public var measurements: [String: Double]
    public var missingReason: String?
    public var note: String?

    public init(_ values: Values = Values()) {
        id = values.id
        observedAt = values.observedAt
        kind = values.kind
        measurements = values.measurements
        missingReason = values.missingReason
        note = values.note
    }
}

/// Canonical package metadata. Archive I/O remains in the app/export layer.
public struct StudyExportManifest: Codable, Equatable, Sendable {
    public struct Values: Sendable {
        public var sessionID = UUID()
        public var generatedAt = Date()
        public var operatingMode: OperatingMode = .evidenceSafe
        public var provenance = BuildProvenance()
        public var fileDigests: [String: String] = [:]
        public var contentFiles: [String]?
        public var includedScopes: Set<ConsentScope> = []

        public init() {}
    }

    public static let schemaVersion = 3
    public var schemaVersion: Int
    public var sessionID: UUID
    public var generatedAt: Date
    public var operatingMode: OperatingMode
    public var provenance: BuildProvenance
    public var fileDigests: [String: String]
    /// Exact non-media package members; consumers must not infer omitted content.
    public var contentFiles: [String]
    /// Consent scopes actually required by the package projection, not every active grant.
    public var includedScopes: Set<ConsentScope>

    public init(_ values: Values = Values()) {
        schemaVersion = Self.schemaVersion
        sessionID = values.sessionID
        generatedAt = values.generatedAt
        operatingMode = values.operatingMode
        provenance = values.provenance
        fileDigests = values.fileDigests
        contentFiles = Array(Set(values.contentFiles ?? Array(values.fileDigests.keys))).sorted()
        includedScopes = values.includedScopes
    }

    public func canonicalJSONData() throws -> Data {
        try SessionCoding.canonicalEncoder().encode(self)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, sessionID, generatedAt, operatingMode, provenance, fileDigests, contentFiles, includedScopes
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(generatedAt, forKey: .generatedAt)
        try c.encode(operatingMode, forKey: .operatingMode)
        try c.encode(provenance, forKey: .provenance)
        try c.encode(fileDigests, forKey: .fileDigests)
        try c.encode(contentFiles, forKey: .contentFiles)
        try c.encode(SessionCoding.canonicalOrder(includedScopes), forKey: .includedScopes)
    }
}

/// Pure, testable projection used by the app package writer. Collections stored
/// as JSONL are removed from `session`, so each fact has one authoritative copy.
public struct StudyExportProjection: Equatable, Sendable {
    public var session: CaptureSession
    public var annotations: [EvidenceAnnotation]
    public var observations: [CaptureObservation]
    public var codingSnapshots: [ResearchCodingSnapshot]
    public var requiredScopes: Set<ConsentScope>

    public static func requiredScopes(for source: CaptureSession) -> Set<ConsentScope> {
        var scopes: Set<ConsentScope> = [.collection, .secondaryUse, .externalSharing]
        if !source.evidenceAnnotations.isEmpty || source.reflection.filledCount > 0 {
            scopes.insert(.localReflection)
        }
        if source.operatingMode == .experimentalResearch {
            scopes.insert(.researchProcessing)
        }
        return scopes
    }

    public static func make(from source: CaptureSession) -> StudyExportProjection {
        var projected = source
        if projected.operatingMode == .evidenceSafe {
            projected.latestCodingSnapshot = nil
            projected.codingSnapshots = []
            projected.codingTimeline = CodingSegmentTimeline()
            projected.experimentalProtocol = nil
        }

        let annotations = projected.evidenceAnnotations
        let observations = projected.captureObservations
        let codingSnapshots = projected.codingSnapshots
        // Disclosure attempts are a local outbox/audit trail. They describe where
        // earlier packages went and must never become content of a later package.
        projected.exportEvents = []
        // The imported file's name can identify a person; it stays local and out of the package.
        for index in projected.mediaAssets.indices { projected.mediaAssets[index].originalFileName = nil }
        projected.evidenceAnnotations = []
        projected.captureObservations = []
        projected.codingSnapshots = []

        return StudyExportProjection(
            session: projected,
            annotations: annotations,
            observations: observations,
            codingSnapshots: codingSnapshots,
            requiredScopes: requiredScopes(for: source)
        )
    }
}
