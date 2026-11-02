import Foundation
import GuidanceEngine
import SessionCore

// MARK: - Experimental structure rules (preset-conditional, not placement alone)

/// Result of an unvalidated rule comparing classroom CV and scene signals with the selected preset.
///
/// Literature informed the candidate signals, but the thresholds have no human-rater or
/// construct validation.
public struct ResearchStructureSufficiency: Equatable, Sendable {
    public struct Values: Equatable, Sendable {
        public var sufficient = false
        public var score = 0.0
        public var teachingSituation = TeachingSituationID.frontalBoardInstruction
        public var sceneType = TeachingSceneType.emptyOrUnusable
        public var layoutPattern = ClassroomLayoutPattern.unknown
        public var checks: [ResearchStructureCheck] = []
        public var summaryDE = ""
        public var actionHintDE = ""

        public init() {}
    }

    public var sufficient: Bool
    /// 0...1 composite rule score for the selected preset.
    public var score: Double
    public var teachingSituation: TeachingSituationID
    public var sceneType: TeachingSceneType
    public var layoutPattern: ClassroomLayoutPattern
    public var checks: [ResearchStructureCheck]
    public var summaryDE: String
    public var actionHintDE: String

    public init(_ values: Values = Values()) {
        sufficient = values.sufficient
        score = min(1, max(0, values.score))
        teachingSituation = values.teachingSituation
        sceneType = values.sceneType
        layoutPattern = values.layoutPattern
        checks = values.checks
        summaryDE = values.summaryDE
        actionHintDE = values.actionHintDE
    }
}

public struct ResearchQualityDimension: Equatable, Identifiable, Sendable {
    public typealias Values = (id: String, labelDE: String, ok: Bool, score: Double, detailDE: String)

    public var id: String
    public var labelDE: String
    public var ok: Bool
    public var score: Double
    public var detailDE: String

    public init(_ values: Values) {
        id = values.id
        labelDE = values.labelDE
        ok = values.ok
        score = min(1, max(0, values.score))
        detailDE = values.detailDE
    }
}

/// Compatibility alias that reuses the `ResearchQualityDimension` data shape.
/// Neither type name denotes validated research quality.
public typealias ResearchStructureCheck = ResearchQualityDimension

/// Pure unvalidated assessor for CV features, scene assessment, and the selected preset.
enum ResearchStructureAssessor: Sendable {

    public static func assess(
        cv: CVFeatures,
        scene: TeachingSceneAssessment,
        teachingSituation: TeachingSituationID,
        signals: ExperimentalCaptureSignals
    ) -> ResearchStructureSufficiency {
        let context = ResearchStructureContext(
            cv: cv,
            scene: scene,
            situation: teachingSituation,
            signals: signals
        )
        guard cv.analysisSucceeded else { return unavailableResult(context) }
        return assessedResult(context, checks: structureChecks(context))
    }

    private static func unavailableResult(_ context: ResearchStructureContext) -> ResearchStructureSufficiency {
        var values = ResearchStructureSufficiency.Values()
        values.teachingSituation = context.situation
        values.sceneType = context.scene.sceneType
        values.layoutPattern = context.signals.layoutPattern
        values.checks = [ResearchStructureCheck((
            id: "cvPipeline",
            labelDE: "Struktur-CV",
            ok: false,
            score: 0,
            detailDE: "CV-Analyse fehlgeschlagen - keine erfundenen Forschungsstrukturen."
        ))]
        values.summaryDE = "Struktur-CV fehlgeschlagen - experimentelle Regelprüfung für „\(context.preset.titleDE)“ nicht verfügbar."
        values.actionHintDE = "Kamera freigeben, Beleuchtung prüfen, Ausschnitt ruhig halten."
        return ResearchStructureSufficiency(values)
    }

    private static func assessedResult(
        _ context: ResearchStructureContext,
        checks: [ResearchStructureCheck]
    ) -> ResearchStructureSufficiency {
        let score = checks.map(\.score).reduce(0, +) / Double(max(1, checks.count))
        let sufficient = checksAreSufficient(checks, score: score)
        var values = ResearchStructureSufficiency.Values()
        values.sufficient = sufficient
        values.score = score
        values.teachingSituation = context.situation
        values.sceneType = context.scene.sceneType
        values.layoutPattern = context.signals.layoutPattern
        values.checks = checks
        values.summaryDE = structureSummary(context, checks: checks, score: score, sufficient: sufficient)
        values.actionHintDE = structureAction(context, sufficient: sufficient)
        return ResearchStructureSufficiency(values)
    }

    private static func checksAreSufficient(_ checks: [ResearchStructureCheck], score: Double) -> Bool {
        let hardIDs: Set<String> = ["board", "peopleCount", "sceneMatch", "coPresence"]
        let hardPass = checks.filter { hardIDs.contains($0.id) }.allSatisfy(\.ok)
        let enoughPass = checks.filter(\.ok).count >= checks.count - 1
        return hardPass && score >= 0.48 && enoughPass
    }

    private static func structureSummary(
        _ context: ResearchStructureContext,
        checks: [ResearchStructureCheck],
        score: Double,
        sufficient: Bool
    ) -> String {
        if sufficient {
            return "Struktur-CV genügt „\(context.preset.titleDE)“ (Score \(percentText(score)), Szene \(context.scene.sceneType.titleDE))."
        }
        let failures = checks.filter { !$0.ok }.map(\.labelDE).joined(separator: ", ")
        return "Struktur unzureichend für „\(context.preset.titleDE)“: \(failures)."
    }

    private static func structureAction(_ context: ResearchStructureContext, sufficient: Bool) -> String {
        if sufficient { return "Stativ fixieren; kontinuierliche Aufnahme starten." }
        return context.preset.mismatchHintDE.isEmpty
            ? context.preset.captureGuidanceDE
            : context.preset.mismatchHintDE
    }
}
