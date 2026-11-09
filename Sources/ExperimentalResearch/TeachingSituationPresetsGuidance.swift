import GuidanceEngine
import SessionCore

public extension GuidanceConfig {
    /// Threshold profile derived from a teaching-situation preset.
    /// Placement geometry (roll, pitch, light) stays shared; scene-sensitive bars adapt.
    static func forTeachingSituation(_ id: TeachingSituationID) -> GuidanceConfig {
        let p = TeachingSituationCatalogue.preset(for: id)
        var c = GuidanceConfig.default

        Self.configureBoard(&c, for: p)
        Self.configurePeople(&c, for: p)

        Self.situationAdjustments[id]?(&c)

        return c
    }
}

private extension GuidanceConfig {
    static func configureBoard(_ config: inout GuidanceConfig, for preset: TeachingSituationPreset) {
        if preset.requiresBoard {
            config.boardMinScore = 0.38 + 0.06 * preset.boardEmphasis
            config.minMultiCueBoardQuality = 0.34 + 0.08 * preset.boardEmphasis
            config.minPersonBoardCoPresence = max(0.28, 0.18 + 0.55 * preset.coPresenceEmphasis)
        } else {
            config.boardMinScore = 0.12 + 0.12 * preset.boardEmphasis
            config.minMultiCueBoardQuality = 0.10 + 0.12 * preset.boardEmphasis
            config.minPersonBoardCoPresence = 0.08 + 0.15 * preset.coPresenceEmphasis
        }
    }

    static func configurePeople(_ config: inout GuidanceConfig, for preset: TeachingSituationPreset) {
        if preset.minPeople >= 3 || preset.prefersMultiPerson {
            config.minPersonCoverage = 0.045 + 0.02 * preset.peopleEmphasis
            config.minPeopleSpatialUsefulness = 0.30 + 0.12 * preset.peopleEmphasis
            config.minPersonMidBandOccupancy = 0.28 + 0.10 * preset.peopleEmphasis
        } else if preset.minPeople >= 1 {
            config.minPersonCoverage = 0.02
            config.minPeopleSpatialUsefulness = 0.24 + 0.08 * preset.peopleEmphasis
            config.minPersonMidBandOccupancy = 0.22 + 0.08 * preset.peopleEmphasis
        } else {
            config.minPersonCoverage = 0
            config.minPeopleSpatialUsefulness = 0
            config.minPersonMidBandOccupancy = 0
        }
    }

    static let situationAdjustments: [TeachingSituationID: @Sendable (inout GuidanceConfig) -> Void] = [
        .frontalBoardInstruction: { c in c.boardMinScore = max(c.boardMinScore, 0.40); c.minPersonBoardCoPresence = max(c.minPersonBoardCoPresence, 0.32) },
        .teacherLedDialogue: { c in c.emptyEdgeCritical = 0.34; c.minGlobalContrast = 0.20; c.minPeopleSpatialUsefulness = max(c.minPeopleSpatialUsefulness, 0.34); c.minPersonMidBandOccupancy = max(c.minPersonMidBandOccupancy, 0.32) },
        .partnerWork: { c in c.emptyEdgeCritical = 0.32; c.minGlobalContrast = 0.20; c.minPeopleSpatialUsefulness = max(c.minPeopleSpatialUsefulness, 0.36); c.minPersonCoverage = max(c.minPersonCoverage, 0.03) },
        .studentBoardPresentation: { c in c.emptyEdgeCritical = 0.34; c.minGlobalContrast = 0.22; c.boardMinScore = max(c.boardMinScore, 0.45); c.minMultiCueBoardQuality = max(c.minMultiCueBoardQuality, 0.40); c.minPersonBoardCoPresence = max(c.minPersonBoardCoPresence, 0.50) },
        .collaborativeGroupWork: { c in c.minPersonCoverage = max(c.minPersonCoverage, 0.05); c.minPeopleSpatialUsefulness = max(c.minPeopleSpatialUsefulness, 0.36); c.boardMinScore = min(c.boardMinScore, 0.22) },
        .classroomManagementOverview: { c in c.emptyEdgeCritical = 0.50; c.floorWarningFraction = 0.34; c.minPersonCoverage = max(c.minPersonCoverage, 0.06); c.minPeopleSpatialUsefulness = max(c.minPeopleSpatialUsefulness, 0.34) },
        .circleOrPlenumDiscussion: { c in c.emptyEdgeCritical = 0.50; c.floorWarningFraction = 0.34; c.minPersonCoverage = max(c.minPersonCoverage, 0.06); c.minPeopleSpatialUsefulness = max(c.minPeopleSpatialUsefulness, 0.34) },
        .handsOnExperiment: { c in c.emptyEdgeCritical = 0.44; c.boardMinScore = 0.10; c.minMultiCueBoardQuality = 0.08; c.minPersonCoverage = max(c.minPersonCoverage, 0.04); c.minPeopleSpatialUsefulness = max(c.minPeopleSpatialUsefulness, 0.30) },
        .individualSeatwork: { c in c.emptyEdgeCritical = 0.48; c.boardMinScore = 0.10; c.minMultiCueBoardQuality = 0.08; c.minPersonCoverage = max(c.minPersonCoverage, 0.04); c.minPeopleSpatialUsefulness = max(c.minPeopleSpatialUsefulness, 0.28); c.minPersonMidBandOccupancy = max(c.minPersonMidBandOccupancy, 0.30) },
        .teacherDemonstration: { c in c.boardMinScore = max(c.boardMinScore, 0.48); c.minMultiCueBoardQuality = max(c.minMultiCueBoardQuality, 0.42); c.minPersonBoardCoPresence = max(c.minPersonBoardCoPresence, 0.48); c.minGlobalContrast = 0.22 },
        .transitionOrganization: { c in c.emptyEdgeCritical = 0.52; c.floorWarningFraction = 0.36; c.minPersonCoverage = max(c.minPersonCoverage, 0.07); c.minPeopleSpatialUsefulness = max(c.minPeopleSpatialUsefulness, 0.32); c.boardMinScore = min(c.boardMinScore, 0.2) },
        .formativeAssessmentDialogue: { c in c.emptyEdgeCritical = 0.32; c.minGlobalContrast = 0.22; c.minPeopleSpatialUsefulness = max(c.minPeopleSpatialUsefulness, 0.38); c.minPersonMidBandOccupancy = max(c.minPersonMidBandOccupancy, 0.35); c.minPersonCoverage = max(c.minPersonCoverage, 0.035) }
    ]
}
