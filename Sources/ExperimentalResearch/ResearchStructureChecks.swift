import Foundation
import GuidanceEngine
import SessionCore

struct ResearchStructureContext {
    let cv: CVFeatures
    let signals: ExperimentalCaptureSignals
    let scene: TeachingSceneAssessment
    let situation: TeachingSituationID
    let preset: TeachingSituationPreset
    let config: GuidanceConfig

    init(
        cv: CVFeatures,
        scene: TeachingSceneAssessment,
        situation: TeachingSituationID,
        signals: ExperimentalCaptureSignals
    ) {
        self.cv = cv
        self.signals = signals
        self.scene = scene
        self.situation = situation
        preset = TeachingSituationCatalogue.preset(for: situation)
        config = GuidanceConfig.forTeachingSituation(situation)
    }

    var board: Double { max(cv.multiCueBoardQuality, cv.boardConfidence) }
    var peopleCount: Int { max(cv.personCount, cv.faceCount) }
    var spatialUsefulness: Double { cv.peopleSpatialUsefulness }
    var midBandOccupancy: Double { cv.personMidBandOccupancy }
    var coPresence: Double { CVFeatureFusion.coPresenceScore(from: cv) }
    var interactionDensity: Double { signals.interactionDensity }
    var secondaryWritingSupport: Double { cv.secondaryWritingSurfaceSupport }
    var boardTextDensity: Double { cv.boardTextDensity }
    var stability: Double { cv.observationStability }

    var layoutFit: Double {
        if preset.preferredLayouts.isEmpty { return 0.55 }
        if preset.preferredLayouts.contains(signals.layoutPattern) { return 0.92 }
        return max(scene.layoutSignal, 0.15)
    }
}

extension ResearchStructureAssessor {
    static func structureChecks(_ context: ResearchStructureContext) -> [ResearchStructureCheck] {
        var checks = boardChecks(context)
        checks.append(peopleCountCheck(context))
        checks.append(peopleSpatialCheck(context))
        checks.append(coPresenceCheck(context))
        checks.append(layoutCheck(context))
        checks.append(sceneCheck(context))
        checks.append(stabilityCheck(context))
        checks.append(interactionDensityCheck(context))
        return checks
    }

    private static func boardChecks(_ context: ResearchStructureContext) -> [ResearchStructureCheck] {
        context.preset.requiresBoard ? requiredBoardChecks(context) : optionalBoardChecks(context)
    }

    private static func requiredBoardChecks(_ context: ResearchStructureContext) -> [ResearchStructureCheck] {
        let bar = max(context.config.minMultiCueBoardQuality, context.preset.minResearchBoardScore)
        let boardPasses = context.board >= bar * 0.92
        let textBar = context.preset.minResearchBoardTextDensity
        return [
            ResearchStructureCheck((
                id: "board",
                labelDE: "Schreibfläche multi-cue",
                ok: boardPasses,
                score: context.board,
                detailDE: boardDetail(context, bar: bar, passes: boardPasses)
            )),
            ResearchStructureCheck((
                id: "boardText",
                labelDE: "Tafel-Text / Zielsichtbarkeit",
                ok: boardTextPasses(context, bar: textBar),
                score: max(context.boardTextDensity, context.board * 0.5),
                detailDE: "Text-Dichte \(percentText(context.boardTextDensity)) (Bar \(percentText(textBar)))."
            ))
        ]
    }

    private static func boardDetail(
        _ context: ResearchStructureContext,
        bar: Double,
        passes: Bool
    ) -> String {
        if passes {
            return "Tafel/Board brauchbar (\(percentText(context.board)); Text \(percentText(context.boardTextDensity)); secondary \(percentText(context.secondaryWritingSupport)))."
        }
        return "Schreibfläche schwach (\(percentText(context.board)) < \(percentText(bar))) - für „\(context.preset.titleDE)“ erforderlich."
    }

    private static func boardTextPasses(_ context: ResearchStructureContext, bar: Double) -> Bool {
        bar <= 0.05 || context.boardTextDensity >= bar * 0.75 || context.board >= 0.7
    }

    private static func optionalBoardChecks(_ context: ResearchStructureContext) -> [ResearchStructureCheck] {
        [
            ResearchStructureCheck((
                id: "board",
                labelDE: "Schreibfläche (optional)",
                ok: true,
                score: max(context.board, 0.5),
                detailDE: "Für diese Situation optional (Score \(percentText(context.board)))."
            )),
            ResearchStructureCheck((
                id: "boardText",
                labelDE: "Tafel-Text (optional)",
                ok: true,
                score: max(context.boardTextDensity, 0.4),
                detailDE: "Optional für „\(context.preset.titleDE)“."
            ))
        ]
    }

    private static func peopleCountCheck(_ context: ResearchStructureContext) -> ResearchStructureCheck {
        let passes = context.peopleCount >= context.preset.minPeople
        return ResearchStructureCheck((
            id: "peopleCount",
            labelDE: "Akteurszahl",
            ok: passes,
            score: min(1, Double(context.peopleCount) / Double(max(1, context.preset.minPeople))),
            detailDE: peopleCountDetail(context, passes: passes)
        ))
    }

    private static func peopleCountDetail(_ context: ResearchStructureContext, passes: Bool) -> String {
        passes
            ? "Akteure n=\(context.peopleCount) ≥ \(context.preset.minPeople)."
            : "Zu wenige Akteure (n=\(context.peopleCount), erwartet ≥ \(context.preset.minPeople))."
    }

    private static func peopleSpatialCheck(_ context: ResearchStructureContext) -> ResearchStructureCheck {
        let useful = context.spatialUsefulness >= context.config.minPeopleSpatialUsefulness
        let centered = context.preset.minPeople == 0
            || context.midBandOccupancy >= context.config.minPersonMidBandOccupancy * 0.85
        return ResearchStructureCheck((
            id: "peopleSpatial",
            labelDE: "Räumliche Nutzbarkeit",
            ok: (useful && centered) || context.preset.minPeople == 0,
            score: context.spatialUsefulness,
            detailDE: "Nutzbarkeit \(percentText(context.spatialUsefulness)), Mittelband \(percentText(context.midBandOccupancy)), Dichte \(percentText(context.interactionDensity))."
        ))
    }

    private static func coPresenceCheck(_ context: ResearchStructureContext) -> ResearchStructureCheck {
        let needed = context.preset.coPresenceEmphasis >= 0.55 && context.preset.requiresBoard
        let passes = !needed || context.coPresence >= context.preset.minResearchCoPresence * 0.9
        return ResearchStructureCheck((
            id: "coPresence",
            labelDE: "Person–Tafel Co-Präsenz",
            ok: passes,
            score: context.coPresence,
            detailDE: coPresenceDetail(context, needed: needed, passes: passes)
        ))
    }

    private static func coPresenceDetail(
        _ context: ResearchStructureContext,
        needed: Bool,
        passes: Bool
    ) -> String {
        guard needed else { return "Co-Präsenz \(percentText(context.coPresence)) (niedrige Gewichtung)." }
        if passes { return "Co-Präsenz \(percentText(context.coPresence))." }
        return "Co-Präsenz zu schwach (\(percentText(context.coPresence)) < \(percentText(context.preset.minResearchCoPresence)))."
    }

    private static func layoutCheck(_ context: ResearchStructureContext) -> ResearchStructureCheck {
        let bar = context.preset.minResearchLayoutFit
        let passes = context.layoutFit >= bar * 0.85 || context.preset.preferredLayouts.isEmpty
        return ResearchStructureCheck((
            id: "layout",
            labelDE: "Layout-Struktur",
            ok: passes,
            score: context.layoutFit,
            detailDE: "Layout \(context.signals.layoutPattern.titleDE) · Fit \(percentText(context.layoutFit)) (Bar \(percentText(bar)))."
        ))
    }

    private static func sceneCheck(_ context: ResearchStructureContext) -> ResearchStructureCheck {
        ResearchStructureCheck((
            id: "sceneMatch",
            labelDE: "Unterrichtsszene / Preset",
            ok: context.scene.matchesPreset && context.scene.presetMatchScore >= 0.45,
            score: context.scene.presetMatchScore,
            detailDE: context.scene.summaryDE
        ))
    }

    private static func stabilityCheck(_ context: ResearchStructureContext) -> ResearchStructureCheck {
        ResearchStructureCheck((
            id: "stability",
            labelDE: "Beobachtungsstabilität",
            ok: context.stability >= 0.35,
            score: context.stability,
            detailDE: "Stabilität \(percentText(context.stability))."
        ))
    }

    private static func interactionDensityCheck(_ context: ResearchStructureContext) -> ResearchStructureCheck {
        let bar = context.preset.minResearchInteractionDensity
        return ResearchStructureCheck((
            id: "interactionDensity",
            labelDE: "Interaktionsdichte",
            ok: bar <= 0.05 || context.interactionDensity >= bar * 0.85,
            score: context.interactionDensity,
            detailDE: "Interaktionsdichte \(percentText(context.interactionDensity)) (Bar \(percentText(bar)))."
        ))
    }

}
