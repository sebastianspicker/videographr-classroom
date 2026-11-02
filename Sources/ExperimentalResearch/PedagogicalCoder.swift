import Foundation
import GuidanceEngine
import SessionCore

struct PedagogicalCodingInput {
    let board: Double
    let people: Double
    let co: Double
    let multi: Double
    let peopleN: Int
    let mid: Double
    let stable: Double
    let interaction: Double
    let layout: ClassroomLayoutPattern
    let layoutFit: Double
    let clusteredness: Double
    let textDensity: Double
    let interactDensity: Double
    let coverageDelta: Double
    let secondaryBoard: Double
    let actorScaleVariance: Double
    let poseConfidenceMean: Double
    let scene: TeachingSceneType

    init(signals: ExperimentalCaptureSignals, scene: TeachingSceneAssessment, frame: FrameMetrics) {
        let cv = signals.cv
        board = max(scene.boardSignal, max(cv.multiCueBoardQuality, cv.boardConfidence))
        people = max(scene.peopleSignal, cv.peopleSpatialUsefulness)
        co = max(scene.coPresenceSignal, CVFeatureFusion.coPresenceScore(from: cv))
        multi = scene.multiPersonSignal
        peopleN = max(cv.personCount, cv.faceCount)
        mid = cv.personMidBandOccupancy
        stable = cv.observationStability
        interaction = signals.framingScore(
            frame: frame,
            orientation: OrientationSample(pitchDegrees: 0, rollDegrees: 0)
        )
        layout = signals.layoutPattern != .unknown ? signals.layoutPattern : scene.layoutPattern
        layoutFit = scene.layoutSignal
        clusteredness = cv.personClusteredness
        textDensity = cv.boardTextDensity
        interactDensity = signals.interactionDensity
        coverageDelta = cv.personCoverageDelta
        secondaryBoard = cv.secondaryWritingSurfaceSupport
        actorScaleVariance = cv.actorScaleVariance
        poseConfidenceMean = cv.poseConfidenceMean
        self.scene = scene.sceneType
    }

}

func stablePedagogicalAssignmentOrder(
    _ lhs: PedagogicalCodeAssignment,
    _ rhs: PedagogicalCodeAssignment
) -> Bool {
    lhs.level == rhs.level ? lhs.code < rhs.code : lhs.level > rhs.level
}

public enum PedagogicalCoder: Sendable {
    public static func code(_ request: PedagogicalCodeInput) -> PedagogicalCodingResult {
        let signals = request.signals
        guard request.cv.analysisSucceeded else {
            return .empty(situation: request.teachingSituation, scene: request.scene.sceneType)
        }
        guard request.scene.sceneType != .emptyOrUnusable else {
            return emptySceneResult(
                situation: request.teachingSituation,
                layout: signals.layoutPattern,
                focus: request.analysisFocus
            )
        }

        let preset = TeachingSituationCatalogue.preset(for: request.teachingSituation)
        let input = PedagogicalCodingInput(signals: signals, scene: request.scene, frame: request.frame)
        let confidence = codingConfidence(
            input: input, request: request
        )
        let ipn = codeIPN(input: input, preset: preset, focus: request.analysisFocus, confidence: confidence)
        let timss = codeTIMSS(input: input, preset: preset, confidence: confidence)
        let gti = codeGTI(input: input, preset: preset, focus: request.analysisFocus, confidence: confidence)
        let result = CodingResultInput(ipn: ipn, timss: timss, gti: gti, input: input, preset: preset, request: request)
        return codingResult(result)
    }

    private static func emptySceneResult(
        situation: TeachingSituationID,
        layout: ClassroomLayoutPattern,
        focus: CodingAnalysisFocus?
    ) -> PedagogicalCodingResult {
        let code = TIMSSActivityCode.unclearOrNonInstructional
        let identity = PedagogicalCodeAssignment.Identity(id: "timss-\(code.rawValue)", family: .timssActivityScript)
        let descriptor = PedagogicalCodeAssignment.Descriptor(code: code.rawValue, labelDE: code.titleDE)
        let measurement = PedagogicalCodeAssignment.Measurement(level: 0.95, confidence: 0.7)
        let assignmentValues = PedagogicalCodeAssignment.Values(identity: identity, descriptor: descriptor, measurement: measurement, rationaleDE: "Leere Szene - die unvalidierte Regel ordnet keine instruktionale Aktivität zu.")
        let assignment = PedagogicalCodeAssignment(assignmentValues)
        let assignments = PedagogicalCodingResult.Assignments(ipnDimensions: [], timssActivities: [assignment])
        let primaryCodes = PedagogicalCodingResult.PrimaryCodes(timss: code, gti: .classroomManagement)
        let content = PedagogicalCodingResult.Content(assignments: assignments, primaryCodes: primaryCodes, overallConfidence: 0.15, summaryDE: "Keine pädagogische Kodierung - unzureichende Szenen-/CV-Signale.")
        let context = PedagogicalCodingResult.Context(sceneType: .emptyOrUnusable, teachingSituation: situation, layoutPattern: layout == .unknown ? .empty : layout, analysisFocus: focus)
        return PedagogicalCodingResult(.init(content: content, context: context))
    }
}

private func codingConfidence(
    input: PedagogicalCodingInput,
    request: PedagogicalCodeInput
) -> Double {
    let scene = request.scene
    let richness = min(
        1,
        0.18 * input.board + 0.22 * input.people + 0.12 * input.co + 0.10 * input.stable
            + 0.10 * scene.confidence + 0.10 * input.layoutFit + 0.08 * input.mid
            + 0.06 * input.interactDensity + 0.04 * input.secondaryBoard
    )
    let match = min(1.0, max(0.30, 0.35 + 0.65 * scene.presetMatchScore))
    let structure = ResearchStructureAssessor.assess(
        cv: request.cv, scene: scene, teachingSituation: request.teachingSituation, signals: request.signals
    )
    let factor = min(1.0, max(0.45, 0.55 + 0.45 * structure.score))
    return min(0.92, 0.35 + 0.55 * richness) * match * factor
}

private struct CodingResultInput {
    let ipn: [PedagogicalCodeAssignment]
    let timss: [PedagogicalCodeAssignment]
    let gti: [PedagogicalCodeAssignment]
    let input: PedagogicalCodingInput
    let preset: TeachingSituationPreset
    let request: PedagogicalCodeInput
}

private func codingResult(_ result: CodingResultInput) -> PedagogicalCodingResult {
    let primary = result.timss.sorted(by: stablePedagogicalAssignmentOrder).first.flatMap { TIMSSActivityCode(rawValue: $0.code) }
        ?? .unclearOrNonInstructional
    let primaryGTI = result.gti.sorted(by: stablePedagogicalAssignmentOrder).first.flatMap { GTIQualityCode(rawValue: $0.code) }
        ?? .instructionalQuality
    let overall = averageConfidence(in: [result.ipn, result.timss, result.gti])
    let focusNote = result.request.analysisFocus.map { " Fokus: \($0.titleDE)." } ?? ""
    let aligned = result.preset.expectedTIMSSActivities.contains(primary.rawValue) || primary == .unclearOrNonInstructional
    let alignmentNote = aligned ? "" : " TIMSS-Primär weicht von Preset-Erwartung ab."
    let topIPN = result.ipn.sorted(by: stablePedagogicalAssignmentOrder).prefix(2).map(\.labelDE).joined(separator: ", ")
    let summary = "IPN: \(topIPN). TIMSS: \(primary.titleDE). GTI: \(primaryGTI.titleDE). Szene: \(result.input.scene.titleDE) · Layout: \(result.input.layout.titleDE).\(focusNote)\(alignmentNote)"
    let assignments = PedagogicalCodingResult.Assignments(ipnDimensions: result.ipn, timssActivities: result.timss, gtiDimensions: result.gti)
    let primaryCodes = PedagogicalCodingResult.PrimaryCodes(timss: primary, gti: primaryGTI)
    let content = PedagogicalCodingResult.Content(assignments: assignments, primaryCodes: primaryCodes, overallConfidence: overall, summaryDE: summary)
    let context = PedagogicalCodingResult.Context(sceneType: result.input.scene, teachingSituation: result.request.teachingSituation, layoutPattern: result.input.layout, analysisFocus: result.request.analysisFocus)
    return PedagogicalCodingResult(.init(content: content, context: context))
}

private func averageConfidence(in families: [[PedagogicalCodeAssignment]]) -> Double {
    let averages = families.map { family in
        family.map(\.confidence).reduce(0, +) / Double(max(1, family.count))
    }
    return min(1, averages.reduce(0, +) / Double(averages.count))
}
