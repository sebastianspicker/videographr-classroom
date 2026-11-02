import Foundation

extension GuidanceEngine {
    func backlightTips(_ frame: FrameMetrics) -> [GuidanceTip] {
        backlightSeverityTips(frame) + windowSideTips(frame)
    }

    private func backlightSeverityTips(_ frame: FrameMetrics) -> [GuidanceTip] {
        if frame.backlightScore >= config.backlightCriticalScore {
            return [GuidanceTip((
                id: "backlight-critical",
                category: .backlight,
                severity: .critical,
                message: "Starkes Gegenlicht: helle Fenster hinter dem Geschehen. Gesichter und Tafel sind unterbelichtet; Details sind schwer erkennbar.",
                actionHint: "Standort wechseln: Fenster im Rücken oder seitlich der Kamera. Alternativ Vorhänge und manuelle Belichtung auf Tafel/Lehrperson."
            ))]
        }
        guard frame.backlightScore >= config.backlightWarningScore else { return [] }
        return [GuidanceTip((
            id: "backlight-warning",
            category: .backlight,
            severity: .warning,
            message: "Hinweis auf Gegenlicht (hell hinten / dunkel vorne).",
            actionHint: "Nicht frontal gegen Fenster filmen - 1–2 m seitlich versetzen und Bild helligkeitsmäßig prüfen."
        ))]
    }

    private func windowSideTips(_ frame: FrameMetrics) -> [GuidanceTip] {
        guard frame.horizontalBrightnessImbalance > config.imbalanceWarning else { return [] }
        let side = frame.leftBandLuminance > frame.rightBandLuminance ? "links" : "rechts"
        let move = side == "links" ? "rechts" : "links"
        return [GuidanceTip((
            id: "window-side",
            category: .backlight,
            severity: .info,
            message: "Einseitig hell (\(side)) - typisch Fensterfront.",
            actionHint: "Bei Überstrahlung Standort nach \(move) oder Kamera so drehen, dass die hellere Seite nicht den Hauptakteur überstrahlt."
        ))]
    }

    func compositionTips(_ frame: FrameMetrics) -> [GuidanceTip] {
        compositionEdgeTips(frame) + compositionLuminanceTips(frame)
    }

    private func compositionEdgeTips(_ frame: FrameMetrics) -> [GuidanceTip] {
        guard frame.emptyEdgeFraction > config.emptyEdgeCritical else { return [] }
        return [GuidanceTip((
            id: "composition-loose",
            category: .composition,
            severity: .warning,
            message: "Randbereiche deutlich heller oder dunkler als mittlere Helligkeit.",
            actionHint: "Bildausschnitt und Belichtung prüfen; bei Bedarf Abstand oder Zoom anpassen, bis die Interaktionszone den Rahmen füllt."
        ))]
    }

    private func compositionLuminanceTips(_ frame: FrameMetrics) -> [GuidanceTip] {
        if frame.averageLuminance < config.tooDarkLuminance {
            return [GuidanceTip((
                id: "too-dark",
                category: .composition,
                severity: .warning,
                message: "Gesamtbild zu dunkel - Mimik und Tafelbild schwer erkennbar.",
                actionHint: "Raumlicht erhöhen; Gegenlicht vermeiden; ggf. Belichtungskorrektur +0,5 bis +1 EV auf die Tafel."
            ))]
        }
        guard frame.averageLuminance > config.tooBrightLuminance else { return [] }
        return [GuidanceTip((
            id: "too-bright",
            category: .composition,
            severity: .info,
            message: "Gesamtbild sehr hell - Überstrahlung an Fenstern möglich.",
            actionHint: "Belichtung begrenzen oder Standort ändern, bis Gesichter und Tafel noch Zeichnung behalten."
        ))]
    }

    func exposureStructureTips(_ frame: FrameMetrics) -> [GuidanceTip] {
        highlightClipTips(frame) + contrastTips(frame) + structureTips(frame)
    }

    private func highlightClipTips(_ frame: FrameMetrics) -> [GuidanceTip] {
        guard frame.clippedHighlightFraction > config.maxHighlightClipFraction else { return [] }
        return [GuidanceTip((
            id: "highlight-clip",
            category: .composition,
            severity: .warning,
            message: "Viele überstrahlte Pixel (ca. \(percentText(frame.clippedHighlightFraction))) - Fenster/Leuchten fressen Zeichnung.",
            actionHint: "Belichtung senken oder Standort so wählen, dass helle Flächen nicht dominieren."
        ))]
    }

    private func contrastTips(_ frame: FrameMetrics) -> [GuidanceTip] {
        guard frame.globalContrast < config.minGlobalContrast else { return [] }
        return [GuidanceTip((
            id: "low-contrast",
            category: .composition,
            severity: .info,
            message: "Geringer Bildkontrast (ca. \(percentText(frame.globalContrast))) - Tafel und Personen schwer trennbar.",
            actionHint: "Belichtung/Standort prüfen; starkes Gegenlicht vermeiden."
        ))]
    }

    private func structureTips(_ frame: FrameMetrics) -> [GuidanceTip] {
        guard frame.edgeEnergy < config.minEdgeEnergy else { return [] }
        guard frame.boardRegionScore < config.boardMinScore else { return [] }
        return [GuidanceTip((
            id: "low-structure",
            category: .composition,
            severity: .info,
            message: "Wenig Kantenstruktur im Bild - häufig unscharf, zu weit oder eine leere Fläche.",
            actionHint: "Scharf stellen, Abstand und Bildausschnitt prüfen, dann Messwert erneut beobachten."
        ))]
    }

    func motionTips(_ motion: MotionMetrics) -> [GuidanceTip] {
        guard !motion.isStable || motion.smoothedAngularSpeed > config.maxSmoothedAngularSpeed else { return [] }
        return [GuidanceTip((
            id: "motion-unstable",
            category: .motion,
            severity: .warning,
            message: "Gerät bewegt sich zu stark (\(String(format: "%.0f", motion.smoothedAngularSpeed)) °/s gemittelt) - Bilddetails bleiben nicht stabil sichtbar.",
            actionHint: "Stativ verwenden und festziehen; nicht aus der Hand filmen; vor Start 2–3 s still halten."
        ))]
    }
}
