import Foundation
import Combine
import CoreMotion
import GuidanceEngine

/// Publishes device attitude + motion stability metrics for the guidance engine.
///
/// Uses CoreMotion device motion when available; on Simulator emits stable synthetic
/// pitch/roll so Live guidance still exercises the pure orientation path.
@MainActor
final class MotionService: ObservableObject {
    @Published private(set) var orientation = OrientationSample(pitchDegrees: 0, rollDegrees: 0, yawDegrees: 0)
    @Published private(set) var motionMetrics = MotionMetrics.stable

    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private var tracker = MotionStabilityTracker()
    private var generation = 0

    init() { queue.maxConcurrentOperationCount = 1 }

    /// Start ~15 Hz device-motion updates (or synthetic values in Simulator).
    func start() {
        generation &+= 1
        let activeGeneration = generation
        tracker.reset()
        guard manager.isDeviceMotionAvailable else {
            startSyntheticMotion()
            return
        }
        manager.deviceMotionUpdateInterval = 1.0 / 15.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] motion, error in
            guard let motion else {
                self?.handleUnavailableMotion(error, generation: activeGeneration)
                return
            }
            self?.publish(motion, error: error, generation: activeGeneration)
        }
    }

    private func startSyntheticMotion() {
        orientation = OrientationSample(pitchDegrees: 3, rollDegrees: 1, yawDegrees: 0)
        motionMetrics = .stable
    }

    private nonisolated func handleUnavailableMotion(_ error: Error?, generation: Int) {
        guard error != nil else { return }
        Task { @MainActor [weak self] in
            guard let self, self.generation == generation else { return }
            self.manager.stopDeviceMotionUpdates()
        }
    }

    private nonisolated func publish(_ motion: CMDeviceMotion, error: Error?, generation: Int) {
        let gravity = motion.gravity
        // Gravity, not Euler attitude: Euler angles are measured from a flat phone and break for an
        // upright tripod mount (yaw is unstable in portrait). Panning is covered by the gyro rate below.
        let sample = OrientationSample(
            gravityX: gravity.x,
            gravityY: gravity.y,
            gravityZ: gravity.z,
            mount: .inferred(gravityX: gravity.x, gravityY: gravity.y)
        )
        let sampleTime = Date(timeIntervalSinceNow: motion.timestamp - ProcessInfo.processInfo.systemUptime)
        let gyro = motion.rotationRate
        let gyroMagnitude = sqrt(gyro.x * gyro.x + gyro.y * gyro.y + gyro.z * gyro.z) * 180.0 / .pi
        Task { @MainActor [weak self] in
            self?.apply(sample, gyroMagnitude: gyroMagnitude, at: sampleTime, error: error, generation: generation)
        }
    }

    private func apply(
        _ sample: OrientationSample,
        gyroMagnitude: Double,
        at sampleTime: Date,
        error: Error?,
        generation: Int
    ) {
        guard self.generation == generation else { return }
        var metrics = tracker.update(orientation: sample, at: sampleTime)
        let blended = max(metrics.angularSpeedDegreesPerSecond, gyroMagnitude * 0.85)
        let smoothed = 0.35 * blended + 0.65 * metrics.smoothedAngularSpeed
        metrics = MotionMetrics(
            angularSpeedDegreesPerSecond: blended,
            isStable: smoothed <= GuidanceConfig.default.maxSmoothedAngularSpeed,
            smoothedAngularSpeed: smoothed
        )
        orientation = sample
        motionMetrics = metrics
    }

    /// Stop hardware updates and reset the stability tracker.
    func stop() {
        generation &+= 1
        manager.stopDeviceMotionUpdates()
        tracker.reset()
    }
}
