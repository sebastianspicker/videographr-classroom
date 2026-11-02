import Foundation

extension GuidanceEngine {
    func orientationTips(_ orientation: OrientationSample) -> [GuidanceTip] {
        rollTips(orientation) + upwardPitchTips(orientation) + downwardPitchTips(orientation)
    }

    private func rollTips(_ orientation: OrientationSample) -> [GuidanceTip] {
        let roll = abs(orientation.rollDegrees)
        if roll > config.rollCriticalDegrees {
            return [GuidanceTip((
                id: "roll-critical",
                category: .orientation,
                severity: .critical,
                message: "Gerät stark verkippt (Roll \(Int(orientation.rollDegrees))°). Tafel und Blickrichtungen sind bei schiefem Horizont schwerer zu erkennen.",
                actionHint: "Stativ-Kugelkopf lösen → Wasserwaage/Displaykante parallel zum Fußboden → festziehen. Nicht aus der Hand halten."
            ))]
        }
        guard roll > config.rollWarningDegrees else { return [] }
        return [GuidanceTip((
            id: "roll-warning",
            category: .orientation,
            severity: .warning,
            message: "Leichte Schräglage (Roll \(Int(orientation.rollDegrees))°). Für Videostudien soll die Bildkante dem Raumhorizont folgen.",
            actionHint: "Seitliche Neigung am Stativ um ca. \(Int(roll))° ausgleichen, bis der Fußboden horizontal wirkt."
        ))]
    }

    private func upwardPitchTips(_ orientation: OrientationSample) -> [GuidanceTip] {
        if orientation.pitchDegrees > config.pitchUpCriticalDegrees {
            return [GuidanceTip((
                id: "pitch-up-critical",
                category: .orientation,
                severity: .critical,
                message: "Kamera zu steil nach oben (Pitch \(Int(orientation.pitchDegrees))°). Zu viel Decke, Lehr-Lern-Geschehen rutscht aus dem Bild.",
                actionHint: "Stativhöhe beibehalten oder senken; Neigungswinkel nach unten, bis Tafel und vordere SuS-Reihen die Bildmitte füllen."
            ))]
        }
        guard orientation.pitchDegrees > config.pitchUpWarningDegrees else { return [] }
        return [GuidanceTip((
            id: "pitch-up-warning",
            category: .orientation,
            severity: .warning,
            message: "Kamera leicht zu hoch geneigt (Pitch \(Int(orientation.pitchDegrees))°).",
            actionHint: "Etwas nach unten neigen (ca. 5–10°), damit weniger Decke und mehr Interaktionsraum sichtbar wird."
        ))]
    }

    private func downwardPitchTips(_ orientation: OrientationSample) -> [GuidanceTip] {
        if orientation.pitchDegrees < config.pitchDownCriticalDegrees {
            return [GuidanceTip((
                id: "pitch-down-critical",
                category: .orientation,
                severity: .critical,
                message: "Kamera zu steil nach unten (Pitch \(Int(orientation.pitchDegrees))°). Zu viel Boden/Bankreihen - Gesichter und Tafel unterrepräsentiert.",
                actionHint: "Stativ um 10–20 cm anheben und leicht nach oben neigen, bis die Schreibfläche und die vordere Interaktionszone im oberen Drittel des Bildes liegen."
            ))]
        }
        guard orientation.pitchDegrees < config.pitchDownWarningDegrees else { return [] }
        return [GuidanceTip((
            id: "pitch-down-warning",
            category: .orientation,
            severity: .warning,
            message: "Kamera etwas zu tief geneigt (Pitch \(Int(orientation.pitchDegrees))°).",
            actionHint: "Gerät leicht anheben oder minimal nach oben kippen - weniger Boden, mehr SuS/Lehrperson."
        ))]
    }

    func ceilingAndFloorTips(_ orientation: OrientationSample, frame: FrameMetrics) -> [GuidanceTip] {
        ceilingTips(frame) + floorTips(frame)
    }

    private func ceilingTips(_ frame: FrameMetrics) -> [GuidanceTip] {
        let ceiling = frame.ceilingFraction
        if ceiling > config.ceilingCriticalFraction {
            return [GuidanceTip((
                id: "ceiling-critical",
                category: .ceiling,
                severity: .critical,
                message: "Zu viel Decke (ca. \(percentText(ceiling))). Unterrichtsvideographie braucht den Interaktionsraum, nicht die Raumhöhe.",
                actionHint: "1) Neigung nach unten. 2) Optional Stativ 10 cm senken. Ziel: Decke nur noch schmaler Streifen am oberen Rand."
            ))]
        }
        if ceiling > config.ceilingWarningFraction {
            return [GuidanceTip((
                id: "ceiling-warning",
                category: .ceiling,
                severity: .warning,
                message: "Auffällig viel Deckenanteil (ca. \(percentText(ceiling))).",
                actionHint: "Leicht nach unten neigen und Bildausschnitt auf Tafel + vordere Sitzreihen legen."
            ))]
        }
        guard frame.topBandLuminance > 0.85 else { return [] }
        guard frame.averageLuminance < 0.55 else { return [] }
        return [GuidanceTip((
            id: "ceiling-lights",
            category: .ceiling,
            severity: .info,
            message: "Helle Deckenleuchten am oberen Rand können die Belichtung stehlen.",
            actionHint: "Minimal nach unten kippen oder Belichtungsmessung auf die Tafel legen (nicht auf die Leuchten)."
        ))]
    }

    private func floorTips(_ frame: FrameMetrics) -> [GuidanceTip] {
        let floor = frame.floorFraction
        if floor > config.floorCriticalFraction {
            return [GuidanceTip((
                id: "floor-critical",
                category: .composition,
                severity: .critical,
                message: "Zu viel Boden/Bänke im Bild (ca. \(percentText(floor))). Mimik und Tafelarbeit erscheinen klein im Bild.",
                actionHint: "Stativ anheben und leicht nach oben neigen; näher an die vordere Interaktionszone heranrücken (ohne SuS-Gesichter unnötig nah)."
            ))]
        }
        guard floor > config.floorWarningFraction else { return [] }
        return [GuidanceTip((
            id: "floor-warning",
            category: .composition,
            severity: .warning,
            message: "Bodenanteil hoch (ca. \(percentText(floor))).",
            actionHint: "Gerät etwas höher setzen oder 5–8° nach oben neigen."
        ))]
    }
}
