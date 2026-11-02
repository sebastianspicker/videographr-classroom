import Foundation

/// Pure, testable capture observability guidance. It reports direct camera,
/// frame, CV, and motion signals without interpreting teaching or research quality.
public struct GuidanceEngine: Sendable {
    public var config: GuidanceConfig

    public init(config: GuidanceConfig = .default) {
        self.config = config
    }

    public func evaluate(_ input: GuidanceInput) -> GuidanceResult {
        let observability = CaptureObservabilityAssessment.assess(
            orientation: input.orientation,
            frame: input.frame,
            cv: input.cv,
            motion: input.motion,
            config: config
        )
        let tips = captureTips(input)
        var placementInput = PlacementAssessment.AssessmentInput(
            orientation: input.orientation,
            frame: input.frame
        )
        placementInput.tips = tips
        placementInput.config = config
        placementInput.cv = input.cv
        placementInput.motion = input.motion
        let placement = PlacementAssessment.assess(placementInput)
        return evidenceSafeResult(tips: tips, placement: placement, observability: observability)
    }

    private func captureTips(_ input: GuidanceInput) -> [GuidanceTip] {
        var tips = evaluateOrientation(input.orientation)
        tips += evaluateCeilingAndFloor(input.orientation, frame: input.frame)
        tips += evaluateBlackboard(frame: input.frame, cv: input.cv)
        tips += evaluateBacklight(input.frame)
        tips += evaluateComposition(input.frame)
        tips += evaluateExposureStructure(input.frame)
        tips += evaluatePeopleCV(input.cv)
        tips += evaluateMotion(input.motion)
        return tips
    }
}
