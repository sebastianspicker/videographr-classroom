import Foundation

extension GuidanceEngine {
    func evaluateOrientation(_ o: OrientationSample) -> [GuidanceTip] {
        orientationTips(o)
    }

    func evaluateCeilingAndFloor(_ o: OrientationSample, frame: FrameMetrics) -> [GuidanceTip] {
        ceilingAndFloorTips(o, frame: frame)
    }

    func evaluateBlackboard(frame: FrameMetrics, cv: CVFeatures = .empty) -> [GuidanceTip] {
        blackboardTips(frame: frame, cv: cv)
    }

    func evaluateBacklight(_ frame: FrameMetrics) -> [GuidanceTip] {
        backlightTips(frame)
    }

    func evaluateComposition(_ frame: FrameMetrics) -> [GuidanceTip] {
        compositionTips(frame)
    }

    func evaluateExposureStructure(_ frame: FrameMetrics) -> [GuidanceTip] {
        exposureStructureTips(frame)
    }

    func evaluatePeopleCV(_ cv: CVFeatures) -> [GuidanceTip] {
        peopleCVTips(cv)
    }

    func evaluateMotion(_ motion: MotionMetrics) -> [GuidanceTip] {
        motionTips(motion)
    }

}

/// Whole-percent text for a 0...1 measure; a non-finite or absurd value reads as unavailable instead of trapping.
public func percentText(_ value: Double) -> String {
    guard value.isFinite, abs(value) <= 1_000 else { return "– %" }
    return "\(Int((value * 100).rounded())) %"
}
