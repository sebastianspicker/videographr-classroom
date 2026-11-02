import Foundation

public struct CaptureSession: Codable, Equatable, Identifiable, Sendable {
    public struct Values: Sendable {
        public var id = UUID()
        public var createdAt = Date()
        public var updatedAt = Date()
        public var title = "Neue Aufnahme"
        public var plannedDurationMinutes = 45
        public var purpose: CapturePurpose = .ownTeaching
        public var analysisIntent: AnalysisIntent = .lessonAnalysis
        public var teachingSituation: TeachingSituationID = .frontalBoardInstruction
        public var context = SessionContext()
        public var consent = ConsentRecord()
        public var recordingRelativePath: String?
        public var reflection = ReflectionAnswers()
        public var latestCodingSnapshot: ResearchCodingSnapshot?
        public var codingSnapshots: [ResearchCodingSnapshot] = []
        public var codingTimeline = CodingSegmentTimeline()
        public var operatingMode: OperatingMode = .evidenceSafe
        public var experimentalProtocol: ResearchProtocolReference?
        public var mediaAssets: [SessionMediaAsset] = []
        public var evidenceAnnotations: [EvidenceAnnotation] = []
        public var captureDecisions: [CaptureDecision] = []
        public var takeManifests: [CaptureTakeManifest] = []
        public var captureObservations: [CaptureObservation] = []
        public var consentGrants: [ConsentGrant] = []
        public var retentionPolicy = RetentionPolicy()
        public var exportEvents: [ExportEvent] = []
        public var buildProvenance: BuildProvenance?

        public init() {}
    }

    /// Schema version is upgraded on decode; legacy records never gain new consent authority.
    public var schemaVersion: Int
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var title: String
    /// Persisted capture plan used for storage/resource estimation; bounded to a practical take length.
    public var plannedDurationMinutes: Int
    public var purpose: CapturePurpose
    public var analysisIntent: AnalysisIntent
    /// Teaching-situation preset (interaction structure expected in the capture).
    public var teachingSituation: TeachingSituationID
    public var context: SessionContext
    public var consent: ConsentRecord
    public var recordingRelativePath: String?
    public var reflection: ReflectionAnswers
    /// Latest research coding snapshot (IPN/TIMSS/GTI + scene/layout) from Live capture.
    public var latestCodingSnapshot: ResearchCodingSnapshot?
    /// Bounded history of coding snapshots for session-level research reports (max 24).
    public var codingSnapshots: [ResearchCodingSnapshot]
    /// Continuous-take segment timeline (scene/TIMSS changes).
    public var codingTimeline: CodingSegmentTimeline
    /// V2 evidence-safe contracts. `recordingRelativePath` remains for legacy callers.
    public var operatingMode: OperatingMode
    public var experimentalProtocol: ResearchProtocolReference?
    public var mediaAssets: [SessionMediaAsset]
    public var evidenceAnnotations: [EvidenceAnnotation]
    public var captureDecisions: [CaptureDecision]
    public var takeManifests: [CaptureTakeManifest]
    /// Append-only session observations; unlike legacy coding snapshots this is never truncated.
    public var captureObservations: [CaptureObservation]
    public var consentGrants: [ConsentGrant]
    public var retentionPolicy: RetentionPolicy
    public var exportEvents: [ExportEvent]
    public var buildProvenance: BuildProvenance?

    public init(_ values: Values = Values()) {
        id = values.id
        createdAt = values.createdAt
        updatedAt = values.updatedAt
        title = values.title
        plannedDurationMinutes = CaptureCapacity.boundedDurationMinutes(values.plannedDurationMinutes)
        purpose = values.purpose
        analysisIntent = values.analysisIntent
        teachingSituation = values.teachingSituation
        context = values.context
        consent = values.consent
        recordingRelativePath = values.recordingRelativePath
        reflection = values.reflection
        latestCodingSnapshot = values.latestCodingSnapshot
        codingSnapshots = values.codingSnapshots
        codingTimeline = values.codingTimeline
        schemaVersion = SessionSchema.currentVersion
        operatingMode = values.operatingMode
        experimentalProtocol = values.experimentalProtocol
        mediaAssets = values.mediaAssets
        evidenceAnnotations = values.evidenceAnnotations
        captureDecisions = values.captureDecisions
        takeManifests = values.takeManifests
        captureObservations = values.captureObservations
        consentGrants = values.consentGrants
        retentionPolicy = values.retentionPolicy
        exportEvents = values.exportEvents
        buildProvenance = values.buildProvenance
    }

    public var setupComplete: Bool {
        canStartNewCapture
            && context.isMinimallyComplete
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Only v2 scoped grants can authorize a new action. Legacy acknowledgements are display-only.
    public func authorizes(_ scope: ConsentScope, at date: Date = Date()) -> Bool {
        consentGrants.contains { $0.authorizes(scope, at: date) }
    }

    public func activeGrant(for scope: ConsentScope, at date: Date = Date()) -> ConsentGrant? {
        consentGrants
            .filter { $0.authorizes(scope, at: date) }
            .sorted {
                let left = $0.expiresAt ?? .distantFuture
                let right = $1.expiresAt ?? .distantFuture
                return left == right
                    ? ($0.grantedAt == $1.grantedAt
                        ? $0.id.uuidString < $1.id.uuidString
                        : $0.grantedAt > $1.grantedAt)
                    : left > right
            }
            .first
    }

    /// Freezes the exact grants used for a capture start. Experimental capture additionally
    /// requires research-processing authority; normal recording never acquires it implicitly.
    public func captureAuthorizationSnapshot(at date: Date = Date()) -> CaptureAuthorizationSnapshot? {
        var required: Set<ConsentScope> = [.collection, .localReflection]
        var additionalExpiry: Date?
        var protocolIdentifier: String?
        if operatingMode == .experimentalResearch {
            guard let experimentalProtocol, experimentalProtocol.isUsable(at: date) else { return nil }
            required.insert(.researchProcessing)
            additionalExpiry = experimentalProtocol.expiresAt
            protocolIdentifier = experimentalProtocol.protocolIdentifier
        }
        let grantIDByScope = required.reduce(into: [ConsentScope: UUID]()) { bindings, scope in
            bindings[scope] = activeGrant(for: scope, at: date)?.id
        }
        guard grantIDByScope.count == required.count,
              grantIDByScope.values.allSatisfy({ grantID in
                  consentGrants.filter({ $0.id == grantID }).count == 1
              })
        else { return nil }
        let grants = consentGrants.filter { grantIDByScope.values.contains($0.id) }
        let expiries = grants.compactMap(\.expiresAt) + [additionalExpiry].compactMap { $0 }
        var values = CaptureAuthorizationSnapshot.Values()
        values.requiredScopes = required
        values.grantIDs = Array(grantIDByScope.values)
        values.grantIDByScope = grantIDByScope
        values.effectiveExpiresAt = expiries.min()
        values.preparedAt = date
        values.researchProtocolIdentifier = protocolIdentifier
        return CaptureAuthorizationSnapshot(values)
    }

    public var canStartNewCapture: Bool {
        authorizes(.collection) && authorizes(.localReflection)
    }

    public var canExportExternally: Bool {
        StudyExportProjection.requiredScopes(for: self).allSatisfy { authorizes($0) }
    }

    public var hasUsableExperimentalProtocol: Bool {
        hasUsableExperimentalProtocol(at: Date())
    }

    public func hasUsableExperimentalProtocol(at date: Date) -> Bool {
        operatingMode == .experimentalResearch
            && (experimentalProtocol?.isUsable(at: date) ?? false)
            && authorizes(.researchProcessing, at: date)
    }

    /// Append a coding snapshot without dropping earlier take evidence.
    public mutating func appendCodingSnapshot(_ snap: ResearchCodingSnapshot) {
        latestCodingSnapshot = snap
        codingTimeline.observe(snapshot: snap)
        if codingSnapshots.last?.id == snap.id { return }
        codingSnapshots.append(snap)
        updatedAt = Date()
    }

    /// Adds one durable observation. Callers may only append; existing history is preserved.
    public mutating func appendCaptureObservation(_ observation: CaptureObservation) {
        guard !captureObservations.contains(where: { $0.id == observation.id }) else { return }
        captureObservations.append(observation)
        captureObservations.sort { $0.observedAt == $1.observedAt ? $0.id.uuidString < $1.id.uuidString : $0.observedAt < $1.observedAt }
        updatedAt = Date()
    }

    /// Closes the active coding segment at media finalization, preventing an open tail segment.
    public mutating func closeCaptureTimeline(at finalizedAt: Date = Date()) {
        codingTimeline.close(at: finalizedAt)
        updatedAt = max(updatedAt, finalizedAt)
    }

    /// Applies interactive form state without replacing capture-owned or append-only fields.
    /// This is the merge boundary used by revision-independent autosave.
    public mutating func mergeDraftFields(from draft: CaptureSession) {
        precondition(id == draft.id, "Draft and persisted session must have the same identity.")
        title = draft.title
        plannedDurationMinutes = CaptureCapacity.boundedDurationMinutes(draft.plannedDurationMinutes)
        purpose = draft.purpose
        analysisIntent = draft.analysisIntent
        teachingSituation = draft.teachingSituation
        context = draft.context
        consent = draft.consent
        reflection = draft.reflection
        operatingMode = draft.operatingMode
        experimentalProtocol = draft.experimentalProtocol
        evidenceAnnotations = draft.evidenceAnnotations
        consentGrants = draft.consentGrants
        retentionPolicy = draft.retentionPolicy
        updatedAt = max(updatedAt, draft.updatedAt)
        if takeManifests.isEmpty { buildProvenance = draft.buildProvenance }
    }

    // Backward-compatible decode: sessions saved before teachingSituation / coding snapshots.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        title = try c.decode(String.self, forKey: .title)
        plannedDurationMinutes = CaptureCapacity.boundedDurationMinutes(
            try c.decodeIfPresent(Int.self, forKey: .plannedDurationMinutes) ?? 45
        )
        purpose = try c.decode(CapturePurpose.self, forKey: .purpose)
        analysisIntent = try c.decode(AnalysisIntent.self, forKey: .analysisIntent)
        teachingSituation = try c.decodeIfPresent(TeachingSituationID.self, forKey: .teachingSituation)
            ?? .frontalBoardInstruction
        context = try c.decode(SessionContext.self, forKey: .context)
        consent = try c.decode(ConsentRecord.self, forKey: .consent)
        recordingRelativePath = try c.decodeIfPresent(String.self, forKey: .recordingRelativePath)
        reflection = try c.decode(ReflectionAnswers.self, forKey: .reflection)
        latestCodingSnapshot = try c.decodeIfPresent(ResearchCodingSnapshot.self, forKey: .latestCodingSnapshot)
        codingSnapshots = try c.decodeIfPresent([ResearchCodingSnapshot].self, forKey: .codingSnapshots) ?? []
        codingTimeline = try c.decodeIfPresent(CodingSegmentTimeline.self, forKey: .codingTimeline)
            ?? CodingSegmentTimeline()
        let decodedVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        schemaVersion = decodedVersion
        operatingMode = try c.decodeIfPresent(OperatingMode.self, forKey: .operatingMode) ?? .evidenceSafe
        experimentalProtocol = try c.decodeIfPresent(ResearchProtocolReference.self, forKey: .experimentalProtocol)
        mediaAssets = try c.decodeIfPresent([SessionMediaAsset].self, forKey: .mediaAssets) ?? []
        evidenceAnnotations = try c.decodeIfPresent([EvidenceAnnotation].self, forKey: .evidenceAnnotations) ?? []
        captureDecisions = try c.decodeIfPresent([CaptureDecision].self, forKey: .captureDecisions) ?? []
        takeManifests = try c.decodeIfPresent([CaptureTakeManifest].self, forKey: .takeManifests) ?? []
        captureObservations = try c.decodeIfPresent([CaptureObservation].self, forKey: .captureObservations) ?? []
        consentGrants = try c.decodeIfPresent([ConsentGrant].self, forKey: .consentGrants) ?? []
        retentionPolicy = try c.decodeIfPresent(RetentionPolicy.self, forKey: .retentionPolicy) ?? RetentionPolicy()
        exportEvents = try c.decodeIfPresent([ExportEvent].self, forKey: .exportEvents) ?? []
        buildProvenance = try c.decodeIfPresent(BuildProvenance.self, forKey: .buildProvenance)
        // Decoding remains non-mutating; legacy media is synthesized in memory and persisted by the next save.
        if decodedVersion < SessionSchema.currentVersion,
           mediaAssets.isEmpty,
           let recordingRelativePath
        {
            var values = SessionMediaAsset.Values()
            values.role = .ownRecorded
            values.relativePath = recordingRelativePath
            mediaAssets = [SessionMediaAsset(values)]
        }
    }
}
