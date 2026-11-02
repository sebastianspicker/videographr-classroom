/// Direct technical assessment of device and frame placement.
public struct PlacementAssessment: Equatable, Sendable {
    public var quality: PlacementQualityLevel
    public var score: Double
    public var summaryDE: String
    public var dimensions: [PlacementDimension]

    public init(quality: PlacementQualityLevel, score: Double, summaryDE: String, dimensions: [PlacementDimension]) {
        self.quality = quality
        self.score = min(1, max(0, score))
        self.summaryDE = summaryDE
        self.dimensions = dimensions
    }

    public var directSignalsPass: Bool { quality == .directSignalsPass }

    public struct AssessmentInput: Sendable {
        public var orientation: OrientationSample
        public var frame: FrameMetrics
        public var tips: [GuidanceTip] = []
        public var config: GuidanceConfig = .default
        public var cv: CVFeatures = .empty
        public var motion: MotionMetrics = .stable

        public init(orientation: OrientationSample, frame: FrameMetrics) {
            self.orientation = orientation
            self.frame = frame
        }
    }

    public static func assess(_ input: AssessmentInput) -> PlacementAssessment {
        let dimensions = directDimensions(input)
        let score = Double(dimensions.filter(\.ok).count) / Double(max(1, dimensions.count))
        let quality: PlacementQualityLevel
        if input.tips.contains(where: { $0.severity == .critical }) || score < 0.45 {
            quality = .defective
        } else if !dimensions.allSatisfy(\.ok) || input.tips.contains(where: { $0.severity == .warning }) {
            quality = .needsAdjustment
        } else {
            quality = .directSignalsPass
        }
        let failed = dimensions.filter { !$0.ok }.map(\.labelDE).joined(separator: ", ")
        let summary: String
        switch quality {
        case .directSignalsPass:
            summary = "Direkte technische Aufnahmesignale im konfigurierten Bereich; keine Aussage zur Unterrichts- oder Forschungsqualität."
        case .needsAdjustment:
            summary = "Vor der Aufnahme anpassen: \(failed)."
        case .defective:
            summary = "Direkte technische Aufnahmesignale außerhalb der konfigurierten Grenzwerte: \(failed)."
        }
        return PlacementAssessment(quality: quality, score: score, summaryDE: summary, dimensions: dimensions)
    }

    private static func directDimensions(_ input: AssessmentInput) -> [PlacementDimension] {
        let frame = input.frame
        let config = input.config
        let levelOK = abs(input.orientation.rollDegrees) <= config.rollWarningDegrees
        let pitchOK = input.orientation.pitchDegrees <= config.pitchUpWarningDegrees
            && input.orientation.pitchDegrees >= config.pitchDownWarningDegrees
        let board = CVFeatureFusion.effectiveBoardScore(frame: frame, cv: input.cv)
        let lightOK = frame.backlightScore < config.backlightWarningScore
            && frame.clippedHighlightFraction <= config.maxHighlightClipFraction
        let compositionOK = frame.emptyEdgeFraction <= config.emptyEdgeCritical
            && frame.averageLuminance >= config.tooDarkLuminance
            && frame.averageLuminance <= config.tooBrightLuminance
            && frame.globalContrast >= config.minGlobalContrast
        let stable = input.motion.isStable && input.motion.smoothedAngularSpeed <= config.maxSmoothedAngularSpeed
        return [
            dimension("horizon", "Horizont / Roll", levelOK, levelOK ? "Bildkante waagerecht." : "Stativ nivellieren."),
            dimension("pitch", "Neigung / Höhe", pitchOK, pitchOK ? "Neigung im Arbeitsbereich." : "Höhe oder Neigung anpassen."),
            dimension("ceiling", "Deckenanteil", frame.ceilingFraction <= config.ceilingWarningFraction, "Direkt aus dem Bildanteil gemessen."),
            dimension("floor", "Bodenanteil", frame.floorFraction <= config.floorWarningFraction, "Direkt aus dem Bildanteil gemessen."),
            dimension("writingSurface", "Schreibfläche", board >= config.boardMinScore, "Direktes Bildsignal (Score \(percentText(board)))."),
            dimension("light", "Gegenlicht / Belichtung", lightOK, "Direkte Belichtungs- und Clipping-Signale."),
            dimension("composition", "Bildausschnitt / Kontrast", compositionOK, "Direkte Bildstruktur und Belichtung."),
            dimension("stability", "Kameraruhe", stable, "Direkt aus Gerätebewegung gemessen.")
        ]
    }

    private static func dimension(_ id: String, _ label: String, _ ok: Bool, _ detail: String) -> PlacementDimension {
        PlacementDimension(id: id, labelDE: label, ok: ok, detailDE: detail)
    }


}
