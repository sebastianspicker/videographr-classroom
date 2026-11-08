import Foundation
import GuidanceEngine
import SessionCore

public struct PedagogicalCodeInput: Sendable {
    public struct Context: Sendable {
        public var cv: CVFeatures
        public var scene: TeachingSceneAssessment
        public var signals: ExperimentalCaptureSignals?
        public init(cv: CVFeatures, scene: TeachingSceneAssessment, signals: ExperimentalCaptureSignals? = nil) {
            self.cv = cv; self.scene = scene; self.signals = signals
        }
    }
    public struct Settings: Sendable {
        public var teachingSituation: TeachingSituationID
        public var frame: FrameMetrics
        public var analysisFocus: CodingAnalysisFocus?
        public init(teachingSituation: TeachingSituationID = .frontalBoardInstruction, frame: FrameMetrics = FrameMetrics(), analysisFocus: CodingAnalysisFocus? = nil) { self.teachingSituation = teachingSituation; self.frame = frame; self.analysisFocus = analysisFocus }
    }
    public struct Values: Sendable {
        public var context: Context
        public var settings: Settings
        public init(context: Context, settings: Settings = .init()) { self.context = context; self.settings = settings }
    }
    public let cv: CVFeatures
    public let scene: TeachingSceneAssessment
    /// Signals derived from `cv`; computed once by the caller to avoid re-deriving them per frame.
    public let signals: ExperimentalCaptureSignals
    public let teachingSituation: TeachingSituationID
    public let frame: FrameMetrics
    public let analysisFocus: CodingAnalysisFocus?

    public init(
        cv: CVFeatures,
        scene: TeachingSceneAssessment,
        settings: Settings = .init(),
        signals: ExperimentalCaptureSignals? = nil
    ) {
        self.init(.init(context: .init(cv: cv, scene: scene, signals: signals), settings: settings))
    }

    public init(_ values: Values) { cv = values.context.cv; scene = values.context.scene; signals = values.context.signals ?? ExperimentalCaptureSignals(cv: values.context.cv); teachingSituation = values.settings.teachingSituation; frame = values.settings.frame; analysisFocus = values.settings.analysisFocus }
}
