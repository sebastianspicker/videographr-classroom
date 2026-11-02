import Foundation

/// A direct, non-pedagogical measurement reported by the capture pipeline.
public struct CaptureObservabilityDimension: Equatable, Identifiable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case pass
        case warn
        case fail
        case unavailable
    }

    public var id: String
    public var labelDE: String
    public var status: Status
    public var value: Double?
    public var detailDE: String

    public struct Values: Equatable, Sendable {
        public var id: String
        public var labelDE: String
        public var status: Status
        public var value: Double?
        public var detailDE = ""

        public init(id: String, labelDE: String, status: Status) {
            self.id = id
            self.labelDE = labelDE
            self.status = status
        }
    }

    public init(_ values: Values) {
        id = values.id
        labelDE = values.labelDE
        status = values.status
        value = values.value.map { min(1, max(0, $0)) }
        detailDE = values.detailDE
    }
}

/// Capture-only evidence. It deliberately does not infer teaching quality,
/// engagement, discourse, feedback, or other pedagogical constructs.
public struct CaptureObservabilityAssessment: Equatable, Sendable {
    public var dimensions: [CaptureObservabilityDimension]

    public init(dimensions: [CaptureObservabilityDimension]) {
        self.dimensions = dimensions
    }

    public var unavailableDimensionIDs: [String] {
        dimensions.filter { $0.status == .unavailable }.map(\.id)
    }

    public static func assess(
        orientation: OrientationSample,
        frame: FrameMetrics,
        cv: CVFeatures,
        motion: MotionMetrics,
        config: GuidanceConfig
    ) -> CaptureObservabilityAssessment {
        let cvUnavailable = !cv.analysisSucceeded
        // Limits mirror the tip thresholds so a dimension fails exactly when a critical tip fires.
        let roll = abs(orientation.rollDegrees)
        let levelError = min(1, roll / config.rollCriticalDegrees)
        let level: CaptureObservabilityDimension.Status =
            roll > config.rollCriticalDegrees ? .fail : (roll > config.rollWarningDegrees ? .warn : .pass)
        let exposure = max(frame.clippedHighlightFraction, frame.clippedShadowFraction, frame.backlightScore)
        // Clipping has only warning-level tips (shadow clipping has none), so it never fails.
        let exposureStatus: CaptureObservabilityDimension.Status
        if frame.backlightScore >= config.backlightCriticalScore {
            exposureStatus = .fail
        } else if frame.backlightScore >= config.backlightWarningScore
            || max(frame.clippedHighlightFraction, frame.clippedShadowFraction) > config.maxHighlightClipFraction {
            exposureStatus = .warn
        } else {
            exposureStatus = .pass
        }
        let stable = motion.isStable && motion.smoothedAngularSpeed <= config.maxSmoothedAngularSpeed

        return CaptureObservabilityAssessment(dimensions: [
            dimension((
                identity: ("level", "Horizont"),
                status: level,
                value: 1 - levelError,
                detail: "Gemessen aus Geräte-Rollwinkel."
            )),
            dimension((
                identity: ("stability", "Kameraruhe"),
                status: stable ? .pass : .warn,
                value: min(1, 1 - motion.smoothedAngularSpeed / 24),
                detail: "Gemessen aus geglätteter Winkelgeschwindigkeit."
            )),
            dimension((
                identity: ("exposure", "Belichtung"),
                status: exposureStatus,
                value: 1 - exposure,
                detail: "Gemessen aus Clipping- und Gegenlichtsignalen."
            )),
            cvDimension(("writingSurface", "Schreibfläche sichtbar", cv.multiCueBoardQuality, 0.45, 0.22), unavailable: cvUnavailable),
            cvDimension(("actors", "Akteure sichtbar", cv.peopleSpatialUsefulness, 0.35, 0.12), unavailable: cvUnavailable),
            cvDimension(("coPresence", "Akteure und Schreibfläche gemeinsam sichtbar", cv.personBoardCoPresence, 0.35, 0.12), unavailable: cvUnavailable),
            cvDimension(("signalStability", "Struktursignal stabil", cv.observationStability, 0.65, 0.35), unavailable: cvUnavailable)
        ])
    }

    private typealias CVDimensionValues = (
        id: String,
        label: String,
        value: Double,
        passMinimum: Double,
        warnMinimum: Double
    )

    private static func cvDimension(
        _ input: CVDimensionValues,
        unavailable: Bool
    ) -> CaptureObservabilityDimension {
        guard !unavailable else {
            return dimension((
                identity: (input.id, input.label),
                status: .unavailable,
                value: nil,
                detail: "Strukturmessung nicht verfügbar."
            ))
        }
        let status = thresholdStatus(
            value: input.value,
            passMinimum: input.passMinimum,
            warnMinimum: input.warnMinimum
        )
        return dimension((
            identity: (input.id, input.label),
            status: status,
            value: input.value,
            detail: "Direktes Bildsignal; keine pädagogische Bewertung."
        ))
    }

    private typealias DimensionValues = (
        identity: (id: String, label: String),
        status: CaptureObservabilityDimension.Status,
        value: Double?,
        detail: String
    )

    private static func dimension(_ input: DimensionValues) -> CaptureObservabilityDimension {
        var values = CaptureObservabilityDimension.Values(
            id: input.identity.id,
            labelDE: input.identity.label,
            status: input.status
        )
        values.value = input.value
        values.detailDE = input.detail
        return CaptureObservabilityDimension(values)
    }

    private static func thresholdStatus(
        value: Double,
        passMinimum: Double,
        warnMinimum: Double
    ) -> CaptureObservabilityDimension.Status {
        if value >= passMinimum { return .pass }
        return value >= warnMinimum ? .warn : .fail
    }
}

