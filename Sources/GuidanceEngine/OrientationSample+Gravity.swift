import Foundation

/// How the phone is mounted, as the screen-plane direction gravity should point to when level.
public enum CaptureMountOrientation: Sendable, Equatable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight

    /// Expected in-plane "down" in the CoreMotion device frame (x right, y toward the top edge).
    var expectedDown: (x: Double, y: Double) {
        switch self {
        case .portrait: return (0, -1)
        case .portraitUpsideDown: return (0, 1)
        case .landscapeLeft: return (-1, 0)
        case .landscapeRight: return (1, 0)
        }
    }

    /// Mount whose expected down best matches the in-plane gravity.
    public static func inferred(gravityX: Double, gravityY: Double) -> CaptureMountOrientation {
        if abs(gravityX) > abs(gravityY) { return gravityX < 0 ? .landscapeLeft : .landscapeRight }
        return gravityY > 0 ? .portraitUpsideDown : .portrait
    }
}

extension OrientationSample {
    /// Builds a sample from the CoreMotion gravity vector (device frame; the back camera looks along -z).
    /// Pitch is camera elevation (positive = tilted up); roll is the signed in-plane angle
    /// between gravity and the mount's expected down direction.
    public init(
        gravityX: Double,
        gravityY: Double,
        gravityZ: Double,
        mount: CaptureMountOrientation,
        yawDegrees: Double = 0
    ) {
        let down = mount.expectedDown
        let roll = atan2(down.x * gravityY - down.y * gravityX, down.x * gravityX + down.y * gravityY)
        self.init(
            pitchDegrees: asin(min(1, max(-1, gravityZ))) * 180 / .pi,
            rollDegrees: roll * 180 / .pi,
            yawDegrees: yawDegrees
        )
    }
}
