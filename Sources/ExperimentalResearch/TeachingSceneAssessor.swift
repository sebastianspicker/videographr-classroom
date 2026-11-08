import Foundation
import GuidanceEngine
import SessionCore

struct SceneInput {
    let board: Double
    let peopleN: Int
    let peopleSignal: Double
    let co: Double
    let multi: Double
    let mid: Double
    let layout: ClassroomLayoutPattern
    let textDensity: Double
    let secondaryBoard: Double
    let stability: Double
    let preset: TeachingSituationPreset

    init(signals: ExperimentalCaptureSignals, preset: TeachingSituationPreset) {
        let cv = signals.cv
        board = max(cv.multiCueBoardQuality, cv.boardConfidence)
        peopleN = max(cv.personCount, cv.faceCount)
        peopleSignal = max(cv.peopleSpatialUsefulness, min(1, Double(peopleN) / 4.0))
        co = CVFeatureFusion.coPresenceScore(from: cv)
        multi = min(1, Double(max(0, peopleN - 1)) / 4.0)
        mid = cv.personMidBandOccupancy
        layout = signals.layoutPattern
        textDensity = cv.boardTextDensity
        secondaryBoard = cv.secondaryWritingSurfaceSupport
        stability = cv.observationStability
        self.preset = preset
    }

    var effectiveBoard: Double { min(1, board + 0.08 * textDensity + 0.06 * secondaryBoard) }
    var hasBoard: Bool { effectiveBoard >= 0.40 }
    var hasPeople: Bool { peopleN > 0 || peopleSignal >= 0.15 }
}

private struct MatchScoreInput {
    let scene: TeachingSceneType
    let confidence: Double
    let preset: TeachingSituationPreset
    let peopleN: Int
    let board: Double
    let co: Double
    let layout: ClassroomLayoutPattern
    let layoutFit: Double
}

public enum TeachingSceneAssessor: Sendable {
    public static func assess(
        cv: CVFeatures,
        frame: FrameMetrics = FrameMetrics(),
        preset: TeachingSituationID = .frontalBoardInstruction
    ) -> TeachingSceneAssessment {
        assess(signals: ExperimentalCaptureSignals(cv: cv), frame: frame, preset: preset)
    }

    public static func assess(
        signals: ExperimentalCaptureSignals,
        frame: FrameMetrics = FrameMetrics(),
        preset: TeachingSituationID = .frontalBoardInstruction
    ) -> TeachingSceneAssessment {
        let presetDef = TeachingSituationCatalogue.preset(for: preset)
        guard signals.cv.analysisSucceeded else { return unavailableAssessment(frame: frame) }
        let input = SceneInput(signals: signals, preset: presetDef)
        let candidate = classify(input)
        let layoutFit = layoutFitScore(pattern: input.layout, preset: presetDef)
        let confidence = classifiedConfidence(candidate.1, input: input, layoutFit: layoutFit)
        let matchInput = MatchScoreInput(scene: candidate.0, confidence: confidence, preset: presetDef, peopleN: input.peopleN, board: input.board, co: input.co, layout: input.layout, layoutFit: layoutFit)
        let match = matchScore(matchInput)
        let matches = matchesPreset(scene: candidate.0, confidence: confidence, match: match, input: input)
        let result = AssessmentResultInput(scene: candidate.0, confidence: confidence, match: match, matches: matches, input: input, layoutFit: layoutFit)
        return assessedResult(result)
    }
}

private func unavailableAssessment(frame: FrameMetrics) -> TeachingSceneAssessment {
    let classification = TeachingSceneAssessment.Classification(sceneType: .emptyOrUnusable, confidence: 0, presetMatchScore: 0, matchesPreset: false)
    let signals = TeachingSceneAssessment.StructureSignals(boardSignal: frame.boardRegionScore * 0.3)
    let values = TeachingSceneAssessment.Values(classification: classification, summaryDE: "CV-Analyse fehlgeschlagen - keine Unterrichtsszene ableitbar.", structureSignals: signals)
    return TeachingSceneAssessment(values)
}

private func classifiedConfidence(_ raw: Double, input: SceneInput, layoutFit: Double) -> Double {
    let boost = input.layout == .unknown || input.layout == .empty ? 1.0 : 0.92 + 0.08 * layoutFit
    return min(1, raw * (0.72 + 0.28 * input.stability) * boost)
}

private func matchesPreset(scene: TeachingSceneType, confidence: Double, match: Double, input: SceneInput) -> Bool {
    guard requirementsMet(input) && confidence >= 0.25 else { return false }
    return match >= 0.55 || expectedMatch(scene, score: match, input: input) || acceptableMatch(scene, score: match, input: input)
}
private func expectedMatch(_ scene: TeachingSceneType, score: Double, input: SceneInput) -> Bool { score >= 0.48 && input.preset.expectedScenes.contains(scene) }
private func acceptableMatch(_ scene: TeachingSceneType, score: Double, input: SceneInput) -> Bool { score >= 0.40 && input.preset.acceptableScenes.contains(scene) }

private func requirementsMet(_ input: SceneInput) -> Bool {
    boardRequirement(input) && peopleRequirement(input) && coPresenceRequirement(input)
}
private func boardRequirement(_ input: SceneInput) -> Bool { !input.preset.requiresBoard || input.board >= 0.35 }
private func peopleRequirement(_ input: SceneInput) -> Bool { input.peopleN >= input.preset.minPeople }
private func coPresenceRequirement(_ input: SceneInput) -> Bool { input.preset.coPresenceEmphasis < 0.7 || input.co >= 0.25 || !input.preset.requiresBoard }

private struct AssessmentResultInput {
    let scene: TeachingSceneType
    let confidence: Double
    let match: Double
    let matches: Bool
    let input: SceneInput
    let layoutFit: Double
}

private func assessedResult(_ result: AssessmentResultInput) -> TeachingSceneAssessment {
    let summary = result.matches
        ? "Szene „\(result.scene.titleDE)“ passt zur Situation „\(result.input.preset.titleDE)“ (Match \(percentText(result.match)))."
        : "Szene „\(result.scene.titleDE)“ weicht von „\(result.input.preset.titleDE)“ ab (Match \(percentText(result.match))). \(result.input.preset.mismatchHintDE)"
    let classification = TeachingSceneAssessment.Classification(sceneType: result.scene, confidence: result.confidence, presetMatchScore: result.match, matchesPreset: result.matches)
    let people = TeachingSceneAssessment.PeopleSignals(peopleSignal: result.input.peopleSignal, coPresenceSignal: result.input.co, multiPersonSignal: result.input.multi)
    let structure = TeachingSceneAssessment.StructureSignals(boardSignal: result.input.board, layoutSignal: result.layoutFit, layoutPattern: result.input.layout)
    let values = TeachingSceneAssessment.Values(classification: classification, summaryDE: summary, peopleSignals: people, structureSignals: structure)
    return TeachingSceneAssessment(values)
}

private func matchScore(_ input: MatchScoreInput) -> Double {
    guard input.scene != .emptyOrUnusable else { return 0.05 * input.confidence }
    let base = input.preset.expectedScenes.contains(input.scene) ? 0.72 + 0.28 * input.confidence
        : (input.preset.acceptableScenes.contains(input.scene) ? 0.48 + 0.25 * input.confidence : relatedness(input.scene, preset: input.preset) * (0.35 + 0.25 * input.confidence))
    return layoutAdjusted(base * requirementMultiplier(input), input: input)
}

private func requirementMultiplier(_ input: MatchScoreInput) -> Double {
    let board = boardMultiplier(input)
    let people = max(0.15, 1.0 - 0.25 * Double(max(0, input.preset.minPeople - input.peopleN)))
    return board * people * coMultiplier(input) * multiMultiplier(input)
}
private func boardMultiplier(_ input: MatchScoreInput) -> Double { input.preset.requiresBoard && input.board < 0.35 ? 0.45 : 1.0 }
private func coMultiplier(_ input: MatchScoreInput) -> Double { input.preset.coPresenceEmphasis >= 0.7 && input.co < 0.3 ? 0.55 : 1.0 }
private func multiMultiplier(_ input: MatchScoreInput) -> Double { input.preset.prefersMultiPerson && input.peopleN < 3 ? 0.5 : 1.0 }

private func layoutAdjusted(_ score: Double, input: MatchScoreInput) -> Double {
    guard hasLayoutPreference(input) else { return score }
    if input.layoutFit >= 0.7 { return min(1, score * 1.08 + 0.04) }
    if input.layoutFit < 0.25 { return score * 0.82 }
    return min(1, score * (0.92 + 0.12 * input.layoutFit))
}
private func hasLayoutPreference(_ input: MatchScoreInput) -> Bool { input.layout != .unknown && input.layout != .empty && !input.preset.preferredLayouts.isEmpty }

private let relatedLayouts: [ClassroomLayoutPattern: Set<ClassroomLayoutPattern>] = [.frontalRows: [.presentationFocus], .presentationFocus: [.frontalRows], .dyadClose: [.frontalRows, .seatworkScattered], .multiCluster: [.sparseSpread, .circleLike, .wholeRoomDense], .circleLike: [.multiCluster, .wholeRoomDense], .sparseSpread: [.multiCluster, .seatworkScattered, .wholeRoomDense], .wholeRoomDense: [.multiCluster, .sparseSpread, .circleLike], .seatworkScattered: [.sparseSpread, .multiCluster], .unknown: [], .empty: []]
private func layoutFitScore(pattern: ClassroomLayoutPattern, preset: TeachingSituationPreset) -> Double { guard pattern != .unknown && pattern != .empty else { return 0.4 }; if preset.preferredLayouts.contains(pattern) { return 0.92 }; return preset.preferredLayouts.contains { relatedLayouts[pattern, default: []].contains($0) } ? 0.55 : 0.18 }
private func relatedness(_ scene: TeachingSceneType, preset: TeachingSituationPreset) -> Double { preset.acceptableScenes.contains(scene) ? 0.55 : 0.2 }
