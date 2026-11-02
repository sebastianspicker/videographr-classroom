import Foundation
import GuidanceEngine
import SessionCore

// MARK: - Session-level research capture report

/// Aggregated research capture report from one or more coding snapshots (seminar / study log).
public struct ResearchCaptureReport: Equatable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var appVersion: String
    public var captureProvenance: ResearchArtifactProvenance
    public var generatorProvenance: ResearchArtifactProvenance
    public var sessionTitle: String
    public var teachingSituation: String
    public var analysisFocus: String?
    public var snapshotCount: Int
    public var dominantSceneType: String
    public var dominantLayout: String
    public var meanPresetMatch: Double
    public var meanOverallConfidence: Double
    public var primaryTIMSS: String
    public var primaryGTI: String
    public var meanIPN: [String: Double]
    public var meanGTI: [String: Double]
    public var meanTIMSS: [String: Double]
    public var summaryDE: String
    public var researchBoundaryDE: String

    public struct Values: Sendable {
        public var id = UUID()
        public var createdAt = Date()
        public var sessionTitle = ""
        public var teachingSituation = ""
        public var analysisFocus: String?
        public var snapshotCount = 0
        public var dominantSceneType = ""
        public var dominantLayout = ""
        public var meanPresetMatch = 0.0
        public var meanOverallConfidence = 0.0
        public var primaryTIMSS = ""
        public var primaryGTI = ""
        public var meanIPN: [String: Double] = [:]
        public var meanGTI: [String: Double] = [:]
        public var meanTIMSS: [String: Double] = [:]
        public var summaryDE = ""
        public var researchBoundaryDE = "Software-Strukturproxies (IPN/TIMSS/GTI) - keine multi-rater-validierten Human-Codes."

        public init(captureProvenance: ResearchArtifactProvenance, generatorProvenance: ResearchArtifactProvenance) {
            self.captureProvenance = captureProvenance
            self.generatorProvenance = generatorProvenance
        }

        public let captureProvenance: ResearchArtifactProvenance
        public let generatorProvenance: ResearchArtifactProvenance
    }

    public init(_ values: Values) {
        id = values.id
        createdAt = values.createdAt
        appVersion = values.generatorProvenance.displayVersion
        captureProvenance = values.captureProvenance
        generatorProvenance = values.generatorProvenance
        sessionTitle = values.sessionTitle
        teachingSituation = values.teachingSituation
        analysisFocus = values.analysisFocus
        snapshotCount = values.snapshotCount
        dominantSceneType = values.dominantSceneType
        dominantLayout = values.dominantLayout
        meanPresetMatch = values.meanPresetMatch
        meanOverallConfidence = values.meanOverallConfidence
        primaryTIMSS = values.primaryTIMSS
        primaryGTI = values.primaryGTI
        meanIPN = values.meanIPN
        meanGTI = values.meanGTI
        meanTIMSS = values.meanTIMSS
        summaryDE = values.summaryDE
        researchBoundaryDE = values.researchBoundaryDE
    }

    public struct BuildInput: Sendable {
        public var id = UUID()
        public var createdAt = Date()
        public var sessionTitle = ""
        public var teachingSituation: TeachingSituationID = .frontalBoardInstruction
        public var analysisFocus: CodingAnalysisFocus?
        public var snapshots: [ResearchCodingSnapshot] = []
        public var captureProvenance: ResearchArtifactProvenance?
        public var generatorProvenance: ResearchArtifactProvenance?

        public init() {}
    }

    public static func build(_ input: BuildInput) -> ResearchCaptureReport? {
        guard let captureProvenance = input.captureProvenance,
              let generatorProvenance = input.generatorProvenance
        else { return nil }
        let snapshots = input.snapshots
        guard let latestSnapshot = snapshots.last,
              snapshots.allSatisfy({
                  $0.appVersion == captureProvenance.displayVersion
                      && $0.provenance == captureProvenance
              })
        else { return nil }

        let aggregate = snapshotAggregate(snapshots, latest: latestSnapshot)
        let meanIPN = meanLevels(snapshots.map(\.ipn))
        let meanGTI = meanLevels(snapshots.map(\.gti))
        let meanTIMSS = meanLevels(snapshots.map(\.timss))

        let situationTitle = TeachingSituationCatalogue.preset(for: input.teachingSituation).titleDE
        let summary = "Report (\(snapshots.count) Snapshots): Situation \u{201E}\(situationTitle)\u{201C} · Szene \(aggregate.scene) · Layout \(aggregate.layout) · TIMSS \(aggregate.timss) · GTI \(aggregate.gti) · Match \(percentText(aggregate.meanMatch))."

        var values = Values(captureProvenance: captureProvenance, generatorProvenance: generatorProvenance)
        values.id = input.id
        values.createdAt = input.createdAt
        values.sessionTitle = input.sessionTitle
        values.teachingSituation = input.teachingSituation.rawValue
        values.analysisFocus = input.analysisFocus?.rawValue
        values.snapshotCount = snapshots.count
        values.dominantSceneType = aggregate.scene
        values.dominantLayout = aggregate.layout
        values.meanPresetMatch = aggregate.meanMatch
        values.meanOverallConfidence = aggregate.meanConfidence
        values.primaryTIMSS = aggregate.timss
        values.primaryGTI = aggregate.gti
        values.meanIPN = meanIPN
        values.meanGTI = meanGTI
        values.meanTIMSS = meanTIMSS
        values.summaryDE = summary
        return ResearchCaptureReport(values)
    }

    private static func meanLevels(_ rows: [[ResearchCodeRow]]) -> [String: Double] {
        var sums: [String: (s: Double, n: Int)] = [:]
        for list in rows {
            for row in list {
                let current = sums[row.code] ?? (0, 0)
                sums[row.code] = (current.s + row.level, current.n + 1)
            }
        }
        return Dictionary(uniqueKeysWithValues: sums.map { ($0.key, $0.value.n > 0 ? $0.value.s / Double($0.value.n) : 0) })
    }

    private static func snapshotAggregate(
        _ snapshots: [ResearchCodingSnapshot],
        latest: ResearchCodingSnapshot
    ) -> (scene: String, layout: String, timss: String, gti: String, meanMatch: Double, meanConfidence: Double) {
        var sceneCounts: [String: Int] = [:]
        var layoutCounts: [String: Int] = [:]
        var timssCounts: [String: Int] = [:]
        var gtiCounts: [String: Int] = [:]
        var matchSum = 0.0
        var confidenceSum = 0.0
        for snapshot in snapshots {
            sceneCounts[snapshot.sceneType, default: 0] += 1
            layoutCounts[snapshot.layoutPattern, default: 0] += 1
            timssCounts[snapshot.primaryTIMSS, default: 0] += 1
            gtiCounts[snapshot.primaryGTI, default: 0] += 1
            matchSum += snapshot.presetMatchScore
            confidenceSum += snapshot.overallConfidence
        }
        let count = Double(snapshots.count)
        return (
            mostRecentFrequentValue(in: snapshots.map(\.sceneType), counts: sceneCounts) ?? latest.sceneType,
            mostRecentFrequentValue(in: snapshots.map(\.layoutPattern), counts: layoutCounts) ?? latest.layoutPattern,
            mostRecentFrequentValue(in: snapshots.map(\.primaryTIMSS), counts: timssCounts) ?? latest.primaryTIMSS,
            mostRecentFrequentValue(in: snapshots.map(\.primaryGTI), counts: gtiCounts) ?? latest.primaryGTI,
            matchSum / count,
            confidenceSum / count
        )
    }
}

// MARK: - Reflection scaffolds from coding (LAF support)

/// Seeds LAF reflection prompts with software coding / scene context (not auto-answers).
/// Keys match SessionCore `ReflectionPromptID.rawValue` (lessonGoals, studentLearningEvidence, …).
public enum CodingInformedReflection: Sendable {
    public static let lessonGoalsKey = "lessonGoals"
    public static let studentLearningEvidenceKey = "studentLearningEvidence"
    public static let instructionalStrategiesKey = "instructionalStrategies"
    public static let alternativesKey = "alternatives"

    public static func scaffoldNotes(
        coding: PedagogicalCodingResult,
        scene: TeachingSceneAssessment,
        situation: TeachingSituationID
    ) -> [String: String] {
        let preset = TeachingSituationCatalogue.preset(for: situation)
        let topIPN = coding.ipnDimensions.sorted(by: stableAssignmentOrder).prefix(3)
        let topGTI = coding.gtiDimensions.sorted(by: stableAssignmentOrder).prefix(2)
        let ipnLine = topIPN.map { "\($0.labelDE) (\(percentText($0.level)))" }.joined(separator: "; ")
        let gtiLine = topGTI.map { "\($0.labelDE) (\(percentText($0.level)))" }.joined(separator: "; ")

        return [
            lessonGoalsKey: """
            Capture-Kontext: Situation \u{201E}\(preset.titleDE)\u{201C}. Szene \(scene.sceneType.titleDE) (Match \(percentText(scene.presetMatchScore))). \
            TIMSS-Aktivität (Software): \(coding.primaryTIMSS.titleDE). \
            IPN-Zielklarheit-Proxy: \(level(of: IPNDimensionCode.goalOrientation.rawValue, in: coding.ipnDimensions)). \
            GTI fachliche Klarheit: \(level(of: GTIQualityCode.subjectClarity.rawValue, in: coding.gtiDimensions)). \
            Belege Lernziele am Video - Codes sind Strukturproxies, keine Validierung.
            """,
            studentLearningEvidenceKey: """
            Struktur-Signale: Personen-Nutzbarkeit \(percentText(scene.peopleSignal)), Mittelband/Layout \(scene.layoutPattern.titleDE), \
            Co-Präsenz \(percentText(scene.coPresenceSignal)). \
            GTI Engagement-Proxy: \(level(of: GTIQualityCode.studentEngagementProxy.rawValue, in: coding.gtiDimensions)). \
            Welche SuS-Äußerungen/Handlungen im Video stützen oder widerlegen die Software-Hypothese?
            """,
            instructionalStrategiesKey: """
            IPN-Schwerpunkte (Software): \(ipnLine.isEmpty ? "-" : ipnLine). \
            GTI (Software): \(gtiLine.isEmpty ? "-" : gtiLine). \
            TIMSS-Skript: \(coding.primaryTIMSS.titleDE). \
            Welche Strategien der Lehrperson passen zu diesen Strukturhinweisen - und welche nicht?
            """,
            alternativesKey: """
            Preset-Hinweis: \(preset.mismatchHintDE) \
            Capture-Guidance: \(preset.captureGuidanceDE) \
            Wenn Match schwach (\(percentText(scene.presetMatchScore))): welche alternative Kameraposition oder Unterrichtsphase würde die Analyseziele besser tragen?
            """
        ]
    }

    private static func level(of code: String, in rows: [PedagogicalCodeAssignment]) -> String {
        guard let row = rows.first(where: { $0.code == code }) else { return "-" }
        return percentText(row.level)
    }

    private static func stableAssignmentOrder(
        _ lhs: PedagogicalCodeAssignment,
        _ rhs: PedagogicalCodeAssignment
    ) -> Bool {
        lhs.level == rhs.level ? lhs.code < rhs.code : lhs.level > rhs.level
    }
}
