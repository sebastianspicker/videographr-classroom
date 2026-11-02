import Foundation

extension GuidanceEngine {
    func blackboardTips(frame: FrameMetrics, cv: CVFeatures) -> [GuidanceTip] {
        let boardScore = CVFeatureFusion.effectiveBoardScore(frame: frame, cv: cv)
        let center = CVFeatureFusion.effectiveBoardCenter(frame: frame, cv: cv)
        let multiCue = cv.analysisSucceeded ? cv.multiCueBoardQuality : 0
        if boardScore < config.boardMinScore {
            return [boardMissingTip(cv: cv, multiCue: multiCue)]
        }
        if boardQualityNeedsWarning(cv: cv, multiCue: multiCue) {
            return [boardLowQualityTip(multiCue: multiCue)] + boardHighPlacementTips(center)
        }
        return boardPlacementTips(center)
    }

    private func boardMissingTip(cv: CVFeatures, multiCue: Double) -> GuidanceTip {
        GuidanceTip((
            id: "board-missing",
            category: .blackboard,
            severity: .warning,
            message: "Tafel/Board kaum erkennbar\(boardCVNote(cv, multiCue: multiCue)). Viele Analysezwecke brauchen die Schreibfläche im Bild.",
            actionHint: "Standort seitlich-frontal wählen (ca. 30–45° zur Tafel), so dass Tafel + Lehrperson + Teile der Lerngruppe gleichzeitig sichtbar sind."
        ))
    }

    private func boardCVNote(_ cv: CVFeatures, multiCue: Double) -> String {
        guard cv.analysisSucceeded else { return "" }
        guard cv.source == .vision || cv.source == .fixture else { return "" }
        return " (CV multi-cue \(percentText(multiCue)))"
    }

    private func boardQualityNeedsWarning(cv: CVFeatures, multiCue: Double) -> Bool {
        guard cv.analysisSucceeded else { return false }
        guard cv.source != .heuristic else { return false }
        guard multiCue < config.minMultiCueBoardQuality else { return false }
        return cv.boardConfidence >= config.boardMinScore
    }

    private func boardLowQualityTip(multiCue: Double) -> GuidanceTip {
        GuidanceTip((
            id: "board-low-quality",
            category: .blackboard,
            severity: .info,
            message: "Schreibfläche schwach abgesichert (Multi-Cue \(percentText(multiCue))) - Geometrie/Kanten unsicher.",
            actionHint: "Tafel vollständiger ins Bild holen (breitere Fläche, klare Kanten); seitlich-frontal statt extrem schräg."
        ))
    }

    private func boardHighPlacementTips(_ center: (x: Double, y: Double)) -> [GuidanceTip] {
        guard center.y < config.boardTooHighY else { return [] }
        return [boardTooHighTip]
    }

    private func boardPlacementTips(_ center: (x: Double, y: Double)) -> [GuidanceTip] {
        boardVerticalPlacementTips(center) + boardHorizontalPlacementTips(center)
    }

    private func boardVerticalPlacementTips(_ center: (x: Double, y: Double)) -> [GuidanceTip] {
        if center.y < config.boardTooHighY { return [boardTooHighTip] }
        guard center.y > config.boardTooLowY else { return [] }
        return [GuidanceTip((
            id: "board-too-low",
            category: .blackboard,
            severity: .info,
            message: "Tafel liegt relativ tief im Rahmen.",
            actionHint: "Prüfen: genug Raum über der Tafel ohne Decken-Übermaß; ggf. leicht nach oben schwenken."
        ))]
    }

    private var boardTooHighTip: GuidanceTip {
        GuidanceTip((
            id: "board-too-high",
            category: .blackboard,
            severity: .warning,
            message: "Tafel sitzt zu weit oben - darunter fehlt der Interaktionsraum mit SuS.",
            actionHint: "Ausschnitt nach unten schwenken oder Stativ leicht anheben und nach unten neigen, bis unter der Tafel noch SuS/Lehrperson sichtbar sind."
        ))
    }

    private func boardHorizontalPlacementTips(_ center: (x: Double, y: Double)) -> [GuidanceTip] {
        if center.x < 0.28 {
            return [GuidanceTip((
                id: "board-left",
                category: .blackboard,
                severity: .info,
                message: "Tafel stark nach links gerutscht.",
                actionHint: "Stativ horizontal nach rechts schwenken oder Standort einen Schritt nach links, bis die Tafel zentrierter wirkt (außer bewusste Seitenperspektive)."
            ))]
        }
        guard center.x > 0.72 else { return [] }
        return [GuidanceTip((
            id: "board-right",
            category: .blackboard,
            severity: .info,
            message: "Tafel stark nach rechts gerutscht.",
            actionHint: "Horizontal nach links schwenken oder Standort nach rechts versetzen."
        ))]
    }

    func peopleCVTips(_ cv: CVFeatures) -> [GuidanceTip] {
        guard cv.analysisSucceeded else { return [] }
        guard cv.source == .vision || cv.source == .fixture else { return [] }
        var tips = personPresenceTips(cv)
        if personContextEligible(cv) {
            tips += personContextTips(cv)
        }
        tips += observationStabilityTips(cv)
        return tips
    }

    private func personPresenceTips(_ cv: CVFeatures) -> [GuidanceTip] {
        if !cv.hasPeople && cv.personCoverage < config.minPersonCoverage {
            return [GuidanceTip((
                id: "people-missing",
                category: .people,
                severity: .warning,
                message: "Keine Personen/Gesichter erkannt - Unterrichtsvideographie braucht Lehr-Lern-Akteure im Bild.",
                actionHint: "Kamera auf Lehrperson und Lerngruppe richten (nicht leere Tafelwand allein); Abstand/Zoom so, dass Personen lesbar sind."
            ))]
        }
        guard cv.personCoverage > 0.55 else { return [] }
        return [GuidanceTip((
            id: "people-too-close",
            category: .people,
            severity: .info,
            message: "Personen füllen sehr viel Bildfläche - Kontext (Tafel, Raum) kann fehlen.",
            actionHint: "Etwas zurückgehen oder Weitwinkel, damit Tafel und Interaktionskontext sichtbar bleiben."
        ))]
    }

    private func personContextEligible(_ cv: CVFeatures) -> Bool {
        guard cv.personCoverage <= 0.55 else { return false }
        return cv.hasPeople || cv.personCoverage >= config.minPersonCoverage
    }

    private func personContextTips(_ cv: CVFeatures) -> [GuidanceTip] {
        return peopleZoneTips(cv) + coPresenceTips(cv)
    }

    private func peopleZoneTips(_ cv: CVFeatures) -> [GuidanceTip] {
        let spatial = cv.peopleSpatialUsefulness
        guard spatial < config.minPeopleSpatialUsefulness || cv.personMidBandOccupancy < config.minPersonMidBandOccupancy else { return [] }
        return [GuidanceTip((
            id: "people-off-zone",
            category: .people,
            severity: .warning,
            message: "Personen außerhalb der Lehr-Lern-Zone (räumliche Nutzbarkeit \(percentText(spatial)), Mittelband \(percentText(cv.personMidBandOccupancy))).",
            actionHint: "Ausschnitt so wählen, dass Lehrperson und Lerngruppe im mittleren Bildband unter der Tafel lesbar sind - nicht nur am Bildrand/Boden."
        ))]
    }

    private func coPresenceTips(_ cv: CVFeatures) -> [GuidanceTip] {
        let boardCue = cv.multiCueBoardQuality >= config.minMultiCueBoardQuality || cv.boardConfidence >= config.boardMinScore
        guard boardCue else { return [] }
        let co = CVFeatureFusion.coPresenceScore(from: cv)
        guard co < config.minPersonBoardCoPresence else { return [] }
        return [GuidanceTip((
            id: "copresence-weak",
            category: .interaction,
            severity: .warning,
            message: "Tafel und Personen kaum gemeinsam im Analyseausschnitt (Co-Präsenz \(percentText(co))).",
            actionHint: "Seitlich-frontal so positionieren, dass Schreibfläche und Akteure gleichzeitig sichtbar sind."
        ))]
    }

    private func observationStabilityTips(_ cv: CVFeatures) -> [GuidanceTip] {
        guard cv.observationStability < config.minObservationStability else { return [] }
        return [GuidanceTip((
            id: "cv-unstable",
            category: .motion,
            severity: .info,
            message: "CV-Beobachtung unruhig (Stabilität \(percentText(cv.observationStability))) - Hinweise können flackern.",
            actionHint: "Stativ ruhig halten; kurzen Moment warten, bis Tafel/Personen stabil erkannt werden (kontinuierliche Aufnahme nicht ständig reframen)."
        ))]
    }
}
