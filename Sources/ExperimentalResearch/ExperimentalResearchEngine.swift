import Foundation
import GuidanceEngine
import SessionCore

/// Explicitly opt-in, unvalidated research evaluation. This is separate from
/// `GuidanceEngine.evaluate`, whose output remains direct observability only.
public struct ExperimentalResearchResult: Equatable, Sendable {
    public var observability: GuidanceResult
    public var teachingSituation: TeachingSituationID
    public var scene: TeachingSceneAssessment
    public var coding: PedagogicalCodingResult
    public var hypotheses: ExperimentalHypothesisSet
}

public struct ExperimentalResearchEngine: Sendable {
    public var guidance: GuidanceEngine

    public init(guidance: GuidanceEngine = GuidanceEngine()) {
        self.guidance = guidance
    }

    public func evaluate(
        orientation: OrientationSample,
        frame: FrameMetrics,
        cv: CVFeatures = .empty,
        motion: MotionMetrics = .stable,
        teachingSituation: TeachingSituationID,
        analysisFocus: CodingAnalysisFocus? = nil,
        experimentalSignals: ExperimentalCaptureSignals? = nil
    ) -> ExperimentalResearchResult {
        var safeInput = GuidanceInput.Values(orientation: orientation, frame: frame)
        safeInput.cv = cv
        safeInput.motion = motion
        let safe = guidance.evaluate(GuidanceInput(safeInput))
        return evaluate(
            observability: safe,
            frame: frame,
            cv: cv,
            teachingSituation: teachingSituation,
            analysisFocus: analysisFocus,
            experimentalSignals: experimentalSignals
        )
    }

    /// Runs only the opt-in research rules when direct observability was already evaluated by
    /// the caller for the same frame. This avoids repeating the direct engine on each frame.
    public func evaluate(
        observability: GuidanceResult,
        frame: FrameMetrics,
        cv: CVFeatures = .empty,
        teachingSituation: TeachingSituationID,
        analysisFocus: CodingAnalysisFocus? = nil,
        experimentalSignals: ExperimentalCaptureSignals? = nil
    ) -> ExperimentalResearchResult {
        let signals = experimentalSignals ?? ExperimentalCaptureSignals(cv: cv)
        let scene = TeachingSceneAssessor.assess(signals: signals, frame: frame, preset: teachingSituation)
        let coding = PedagogicalCoder.code(PedagogicalCodeInput(
            cv: cv,
            scene: scene,
            settings: .init(teachingSituation: teachingSituation, frame: frame, analysisFocus: analysisFocus),
            signals: signals
        ))
        return ExperimentalResearchResult(
            observability: observability,
            teachingSituation: teachingSituation,
            scene: scene,
            coding: coding,
            hypotheses: ExperimentalHypothesisSet(
                hypotheses: (coding.ipnDimensions + coding.timssActivities + coding.gtiDimensions).map(ExperimentalHypothesis.init)
            )
        )
    }
}
