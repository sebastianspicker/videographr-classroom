import Foundation
import GuidanceEngine

public extension CVFeatures {
    /// Fixture: board present mid-frame, people in interaction band (research-style classroom).
    static func fixtureClassroomPresent() -> CVFeatures {
        let board = ImageNormalizedRect(x: 0.22, y: 0.18, width: 0.56, height: 0.32)
        return CVFeatures.make { values in
            values.source = .fixture
            values.boardConfidence = 0.82
            values.boardRect = board
            values.boardAspectQuality = 0.88
            values.boardGeometryQuality = 0.85
            values.boardEdgeSupport = 0.72
            values.personCount = 4
            values.personCoverage = 0.18
            values.faceCount = 2
            values.personMidBandOccupancy = 0.78
            values.personCentroidY = 0.58
            values.personCentroidX = 0.48
            values.personBoardCoPresence = 0.74
            values.observationStability = 0.9
            values.personHorizontalSpread = 0.32
            values.personVerticalSpread = 0.18
            values.personClusteredness = 0.42
            values.estimatedClusterCount = 2
            values.faceScaleScore = 0.45
            values.boardTextDensity = 0.55
            values.analysisSucceeded = true
        }
    }

    /// Fixture: empty room / wrong aim - no board, no people.
    static func fixtureEmptyRoom() -> CVFeatures {
        CVFeatures.make { values in
            values.source = .fixture
            values.boardConfidence = 0.08
            values.boardRect = nil
            values.boardAspectQuality = 0.1
            values.boardGeometryQuality = 0.05
            values.boardEdgeSupport = 0.05
            values.personCount = 0
            values.personCoverage = 0
            values.faceCount = 0
            values.personMidBandOccupancy = 0
            values.personCentroidY = nil
            values.personCentroidX = nil
            values.personBoardCoPresence = 0
            values.observationStability = 0.85
            values.personHorizontalSpread = 0
            values.personVerticalSpread = 0
            values.personClusteredness = 0
            values.estimatedClusterCount = 0
            values.faceScaleScore = 0
            values.boardTextDensity = 0
            values.analysisSucceeded = true
        }
    }

    /// Fixture: people present but board missing (e.g. facing wrong wall).
    static func fixturePeopleNoBoard() -> CVFeatures {
        CVFeatures.make { values in
            values.source = .fixture
            values.boardConfidence = 0.12
            values.boardRect = nil
            values.boardAspectQuality = 0.15
            values.boardGeometryQuality = 0.1
            values.boardEdgeSupport = 0.08
            values.personCount = 3
            values.personCoverage = 0.22
            values.faceCount = 1
            values.personMidBandOccupancy = 0.65
            values.personCentroidY = 0.55
            values.personCentroidX = 0.5
            values.personBoardCoPresence = 0.05
            values.observationStability = 0.8
            values.personHorizontalSpread = 0.28
            values.personVerticalSpread = 0.2
            values.personClusteredness = 0.4
            values.estimatedClusterCount = 1
            values.faceScaleScore = 0.4
            values.boardTextDensity = 0.05
            values.analysisSucceeded = true
        }
    }

    /// Fixture: board-dominated frame without usable people / interaction (empty lecture wall).
    static func fixtureBoardNoPeople() -> CVFeatures {
        let board = ImageNormalizedRect(x: 0.15, y: 0.12, width: 0.7, height: 0.4)
        return CVFeatures.make { values in
            values.source = .fixture
            values.boardConfidence = 0.88
            values.boardRect = board
            values.boardAspectQuality = 0.9
            values.boardGeometryQuality = 0.8
            values.boardEdgeSupport = 0.75
            values.personCount = 0
            values.personCoverage = 0
            values.faceCount = 0
            values.personMidBandOccupancy = 0
            values.personCentroidY = nil
            values.personCentroidX = nil
            values.personBoardCoPresence = 0
            values.observationStability = 0.88
            values.personHorizontalSpread = 0
            values.personVerticalSpread = 0
            values.personClusteredness = 0
            values.estimatedClusterCount = 0
            values.faceScaleScore = 0
            values.boardTextDensity = 0.4
            values.analysisSucceeded = true
        }
    }

    /// Fixture: people present but clustered far from board / outside interaction band.
    static func fixturePeopleOffZone() -> CVFeatures {
        let board = ImageNormalizedRect(x: 0.2, y: 0.1, width: 0.55, height: 0.28)
        return CVFeatures.make { values in
            values.source = .fixture
            values.boardConfidence = 0.8
            values.boardRect = board
            values.boardAspectQuality = 0.85
            values.boardGeometryQuality = 0.82
            values.boardEdgeSupport = 0.7
            values.personCount = 2
            values.personCoverage = 0.12
            values.faceCount = 1
            values.personMidBandOccupancy = 0.15
            values.personCentroidY = 0.92
            values.personCentroidX = 0.15
            values.personBoardCoPresence = 0.12
            values.observationStability = 0.75
            values.personHorizontalSpread = 0.35
            values.personVerticalSpread = 0.25
            values.personClusteredness = 0.3
            values.estimatedClusterCount = 1
            values.faceScaleScore = 0.3
            values.boardTextDensity = 0.15
            values.analysisSucceeded = true
        }
    }

    /// Fixture: multi-person group work (board weak/secondary, people cluster mid-band).
    static func fixtureGroupWork() -> CVFeatures {
        CVFeatures.make { values in
            values.source = .fixture
            values.boardConfidence = 0.28
            values.boardRect = ImageNormalizedRect(x: 0.05, y: 0.08, width: 0.25, height: 0.18)
            values.boardAspectQuality = 0.5
            values.boardGeometryQuality = 0.4
            values.boardEdgeSupport = 0.3
            values.personCount = 5
            values.personCoverage = 0.28
            values.faceCount = 3
            values.personMidBandOccupancy = 0.72
            values.personCentroidY = 0.58
            values.personCentroidX = 0.52
            values.personBoardCoPresence = 0.22
            values.observationStability = 0.88
            values.personHorizontalSpread = 0.35
            values.personVerticalSpread = 0.22
            values.personClusteredness = 0.55
            values.estimatedClusterCount = 2
            values.faceScaleScore = 0.5
            values.boardTextDensity = 0.12
            values.analysisSucceeded = true
        }
    }
}
