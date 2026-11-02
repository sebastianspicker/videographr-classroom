import Foundation

/// Live device-motion metrics compared with the configured placement-stability threshold.
public struct MotionMetrics: Equatable, Sendable {
    /// Combined angular speed estimate (deg/s) from attitude deltas.
    public var angularSpeedDegreesPerSecond: Double
    /// True when smoothed motion is at or below the configured threshold.
    public var isStable: Bool
    /// Rolling mean of angular speed (deg/s).
    public var smoothedAngularSpeed: Double

    public init(
        angularSpeedDegreesPerSecond: Double = 0,
        isStable: Bool = true,
        smoothedAngularSpeed: Double = 0
    ) {
        self.angularSpeedDegreesPerSecond = max(0, angularSpeedDegreesPerSecond)
        self.isStable = isStable
        self.smoothedAngularSpeed = max(0, smoothedAngularSpeed)
    }

    public static let stable = MotionMetrics(angularSpeedDegreesPerSecond: 0.5, isStable: true, smoothedAngularSpeed: 0.4)
}

/// Pure tracker: sequential orientation samples → motion smoothness metrics.
public struct MotionStabilityTracker: Sendable {
    public var stableMaxDegreesPerSecond: Double
    public var smoothingAlpha: Double

    private var previous: OrientationSample?
    private var previousTime: Date?
    private var smoothed: Double = 0

    public init(stableMaxDegreesPerSecond: Double = 12, smoothingAlpha: Double = 0.35) {
        self.stableMaxDegreesPerSecond = stableMaxDegreesPerSecond
        self.smoothingAlpha = smoothingAlpha
    }

    public mutating func reset() {
        previous = nil
        previousTime = nil
        smoothed = 0
    }

    public mutating func update(
        orientation: OrientationSample,
        at time: Date = Date()
    ) -> MotionMetrics {
        defer {
            previous = orientation
            previousTime = time
        }
        guard let prev = previous, let t0 = previousTime else {
            return MotionMetrics(angularSpeedDegreesPerSecond: 0, isStable: true, smoothedAngularSpeed: 0)
        }
        let dt = time.timeIntervalSince(t0)
        guard dt > 0.001, dt < 2.0 else {
            return MotionMetrics(
                angularSpeedDegreesPerSecond: smoothed,
                isStable: smoothed <= stableMaxDegreesPerSecond,
                smoothedAngularSpeed: smoothed
            )
        }
        let dPitch = abs(orientation.pitchDegrees - prev.pitchDegrees)
        let dRoll = angleDifference(orientation.rollDegrees, prev.rollDegrees)
        let dYaw = angleDifference(orientation.yawDegrees, prev.yawDegrees)
        let speed = (dPitch + dRoll + dYaw) / dt
        smoothed = smoothingAlpha * speed + (1 - smoothingAlpha) * smoothed
        return MotionMetrics(
            angularSpeedDegreesPerSecond: speed,
            isStable: smoothed <= stableMaxDegreesPerSecond,
            smoothedAngularSpeed: smoothed
        )
    }

    /// Stateless helper for tests: two samples and Δt.
    public static func angularSpeed(
        from a: OrientationSample,
        to b: OrientationSample,
        deltaSeconds: Double
    ) -> Double {
        guard deltaSeconds > 0 else { return 0 }
        let d = abs(b.pitchDegrees - a.pitchDegrees)
            + angleDifference(b.rollDegrees, a.rollDegrees)
            + angleDifference(b.yawDegrees, a.yawDegrees)
        return d / deltaSeconds
    }
}

/// Smallest absolute difference between two angles in degrees (wrap-aware).
private func angleDifference(_ a: Double, _ b: Double) -> Double {
    let raw = abs(a - b).truncatingRemainder(dividingBy: 360)
    return min(raw, 360 - raw)
}
