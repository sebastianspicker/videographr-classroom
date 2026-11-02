import Foundation
import GuidanceEngine
import SessionCore

extension PedagogicalCoder {
    static func codeGTI(
        input: PedagogicalCodingInput,
        preset: TeachingSituationPreset,
        focus: CodingAnalysisFocus?,
        confidence: Double
    ) -> [PedagogicalCodeAssignment] {
        guard input.scene != .emptyOrUnusable else { return [] }
        return gtiLevels(input).map { code, raw in
            let level = gtiBoost(code, raw: raw, preset: preset, focus: focus)
            return gtiAssignment(code: code, level: level, confidence: confidence)
        }.sorted(by: stablePedagogicalAssignmentOrder)
    }
}

private func gtiLevels(_ input: PedagogicalCodingInput) -> [GTIQualityCode: Double] {
    [
        .classroomManagement: managementLevel(input),
        .socialEmotionalSupport: socialEmotionalLevel(input),
        .instructionalQuality: instructionLevel(input),
        .studentEngagementProxy: engagementLevel(input),
        .discourseQuality: discourseLevel(input),
        .subjectClarity: clarityLevel(input),
        .cognitiveEngagement: cognitiveLevel(input),
        .assessmentFeedback: assessmentLevel(input)
    ]
}

private func managementLevel(_ input: PedagogicalCodingInput) -> Double {
    0.26 * input.interaction + 0.18 * input.stable + 0.18 * managementScene(input.scene)
        + 0.14 * managementLayout(input.layout) + 0.12 * min(1, Double(input.peopleN) / 5.0)
        + 0.12 * min(1, input.coverageDelta * 1.2)
}

private func socialEmotionalLevel(_ input: PedagogicalCodingInput) -> Double {
    let layout = Set([ClassroomLayoutPattern.circleLike, .dyadClose]).contains(input.layout) ? 0.85 : 0.4
    return 0.30 * input.multi + 0.25 * input.people + 0.20 * input.mid + 0.15 * socialEmotionalScene(input.scene) + 0.10 * layout
}

private func instructionLevel(_ input: PedagogicalCodingInput) -> Double {
    let layout = Set([ClassroomLayoutPattern.presentationFocus, .frontalRows]).contains(input.layout) ? 0.85 : 0.45
    return 0.28 * input.board + 0.22 * input.co + 0.22 * instructionScene(input.scene) + 0.15 * input.people + 0.13 * layout
}

private func engagementLevel(_ input: PedagogicalCodingInput) -> Double {
    let variance = Set([TeachingSceneType.multiPersonGroup, .wholeRoomOverview]).contains(input.scene)
        ? input.actorScaleVariance : (1 - input.actorScaleVariance) * 0.5
    return 0.20 * input.people + 0.18 * input.mid + 0.14 * input.multi + 0.12 * input.layoutFit
        + 0.16 * input.interactDensity + 0.08 * input.poseConfidenceMean
        + 0.08 * (1.0 - abs(faceScaleProxy(input.peopleN) - 0.5)) + 0.04 * variance
}

private func discourseLevel(_ input: PedagogicalCodingInput) -> Double {
    let layout = Set([ClassroomLayoutPattern.dyadClose, .circleLike]).contains(input.layout) ? 0.9 : 0.35
    return 0.32 * discourseScene(input.scene) + 0.22 * input.people + 0.18 * input.mid + 0.15 * layout + 0.13 * input.multi
}

private func clarityLevel(_ input: PedagogicalCodingInput) -> Double {
    let scene = Set([TeachingSceneType.boardCentricFrontal, .teacherDemonstration, .studentAtBoard]).contains(input.scene) ? 0.85 : 0.3
    return 0.30 * input.board + 0.24 * input.textDensity + 0.18 * input.co + 0.12 * input.secondaryBoard + 0.16 * scene
}

private func cognitiveLevel(_ input: PedagogicalCodingInput) -> Double {
    0.30 * cognitiveScene(input.scene) + 0.25 * input.board + 0.20 * input.co + 0.15 * input.people + 0.10 * input.textDensity
}

private func assessmentLevel(_ input: PedagogicalCodingInput) -> Double {
    let layout = input.layout == .dyadClose ? 0.9 : 0.35
    return 0.35 * assessmentScene(input.scene) + 0.25 * input.people + 0.20 * input.mid + 0.12 * layout + 0.08 * input.co
}

private func gtiBoost(_ code: GTIQualityCode, raw: Double, preset: TeachingSituationPreset, focus: CodingAnalysisFocus?) -> Double {
    let presetFactor = preset.gtiEmphasis.contains(code.rawValue) ? 1.10 : 1.0
    let focusFactor = focus?.gtiBoosts.contains(code.rawValue) == true ? 1.06 : 1.0
    return min(1, raw * presetFactor * focusFactor)
}

private func gtiAssignment(code: GTIQualityCode, level: Double, confidence: Double) -> PedagogicalCodeAssignment {
    let identity = PedagogicalCodeAssignment.Identity(id: "gti-\(code.rawValue)", family: .gtiQuality)
    let descriptor = PedagogicalCodeAssignment.Descriptor(code: code.rawValue, labelDE: code.titleDE)
    let measurement = PedagogicalCodeAssignment.Measurement(level: level, confidence: confidence * (0.82 + 0.18 * level))
    let values = PedagogicalCodeAssignment.Values(identity: identity, descriptor: descriptor, measurement: measurement, rationaleDE: gtiRationale(code))
    return PedagogicalCodeAssignment(values)
}

private func gtiRationale(_ code: GTIQualityCode) -> String {
    let values: [GTIQualityCode: String] = [
        .classroomManagement: "GTI/TALIS domain management: Organisation, Stabilität, Raumstruktur.",
        .socialEmotionalSupport: "GTI domain social-emotional support: Interaktionsdichte und Layout (Kreis/Gruppe/Dialog).",
        .instructionalQuality: "GTI domain instruction (composite): Tafel-, Dialog- und Aktivierungsstruktur.",
        .studentEngagementProxy: "Engagement-Proxy aus Akteuren, Mittelband und Layout - nicht validiertes Outcome.",
        .discourseQuality: "TALIS Video discourse practices: Dialog/Plenum/Rezitation aus Szene und Layout.",
        .subjectClarity: "GTI subject clarity: Schreibfläche, Text-Dichte und Co-Präsenz (zielsichtbare Struktur).",
        .cognitiveEngagement: "GTI cognitive engagement: Tafelarbeit, Experiment, Präsentation als Aktivierungs-Proxy.",
        .assessmentFeedback: "GTI formative assessment: Dialog- und Unterstützungsstruktur als Feedback-Proxy."
    ]
    return values[code] ?? "GTI-Strukturproxy."
}

private func faceScaleProxy(_ peopleN: Int) -> Double { min(1, Double(max(1, peopleN)) / 5.0) }

private func sceneValue(_ scene: TeachingSceneType, values: [TeachingSceneType: Double], fallback: Double) -> Double { values[scene] ?? fallback }
private func managementScene(_ scene: TeachingSceneType) -> Double { sceneValue(scene, values: [.wholeRoomOverview: 0.9, .transitionMoment: 0.9, .boardCentricFrontal: 0.7, .teacherDemonstration: 0.7, .multiPersonGroup: 0.55, .circleDiscussion: 0.55, .experimentSpread: 0.5, .individualSeatwork: 0.5], fallback: 0.35) }
private func managementLayout(_ layout: ClassroomLayoutPattern) -> Double { [.wholeRoomDense: 0.85, .frontalRows: 0.85, .multiCluster: 0.65, .circleLike: 0.65][layout] ?? 0.4 }
private func socialEmotionalScene(_ scene: TeachingSceneType) -> Double { sceneValue(scene, values: [.circleDiscussion: 0.88, .multiPersonGroup: 0.88, .dialoguePair: 0.7, .wholeRoomOverview: 0.5, .individualSeatwork: 0.35], fallback: 0.4) }
private func instructionScene(_ scene: TeachingSceneType) -> Double { sceneValue(scene, values: [.boardCentricFrontal: 0.88, .studentAtBoard: 0.88, .teacherDemonstration: 0.88, .dialoguePair: 0.7, .experimentSpread: 0.7, .multiPersonGroup: 0.6, .circleDiscussion: 0.6, .transitionMoment: 0.3], fallback: 0.35) }
private func discourseScene(_ scene: TeachingSceneType) -> Double { sceneValue(scene, values: [.dialoguePair: 0.9, .circleDiscussion: 0.9, .boardCentricFrontal: 0.55, .multiPersonGroup: 0.55, .studentAtBoard: 0.45, .teacherDemonstration: 0.45], fallback: 0.25) }
private func cognitiveScene(_ scene: TeachingSceneType) -> Double { sceneValue(scene, values: [.studentAtBoard: 0.85, .teacherDemonstration: 0.85, .boardCentricFrontal: 0.85, .experimentSpread: 0.82, .dialoguePair: 0.55, .multiPersonGroup: 0.55, .individualSeatwork: 0.5], fallback: 0.25) }
private func assessmentScene(_ scene: TeachingSceneType) -> Double { sceneValue(scene, values: [.dialoguePair: 0.88, .circleDiscussion: 0.7, .studentAtBoard: 0.7, .boardCentricFrontal: 0.45, .multiPersonGroup: 0.45], fallback: 0.22) }

public enum GTIQualityCode: String, Codable, CaseIterable, Sendable, Identifiable {
    case classroomManagement, socialEmotionalSupport, instructionalQuality, studentEngagementProxy
    case discourseQuality, subjectClarity, cognitiveEngagement, assessmentFeedback
    public var id: String { rawValue }
    public var domain: String {
        if self == .classroomManagement { return "classroomManagement" }
        if self == .socialEmotionalSupport || self == .studentEngagementProxy { return "socialEmotionalSupport" }
        return "instruction"
    }
    public var titleDE: String {
        let titles: [GTIQualityCode: String] = [.classroomManagement: "Klassenführung (GTI)", .socialEmotionalSupport: "Sozial-emotionale Unterstützung (GTI)", .instructionalQuality: "Unterrichtsqualität / Instruction (GTI)", .studentEngagementProxy: "SuS-Engagement (Proxy)", .discourseQuality: "Diskursqualität (GTI/TALIS)", .subjectClarity: "Fachliche Klarheit (GTI)", .cognitiveEngagement: "Kognitive Aktivierung (GTI)", .assessmentFeedback: "Formatives Feedback (GTI)"]
        return titles[self] ?? rawValue
    }
    public var researchNoteDE: String { "OECD GTI / TALIS Video software proxy - not multi-rater validated ground truth." }
}
