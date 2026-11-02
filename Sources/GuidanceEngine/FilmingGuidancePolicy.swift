import Foundation

/// Capture phase for continuous classroom recording (Derry: continuous take).
public enum FilmingPhase: String, Equatable, Sendable {
    case preRoll
    case recording
}

/// How a tip should be presented on the live filming surface.
public enum TipPresentation: String, Equatable, Sendable {
    /// Act on now (pre-roll or critical mid-take).
    case active
    /// Still shown mid-take but framed as non-interruptive / post-take.
    case postTakeNote
    /// Hidden from primary list (e.g. pure OK noise while recording).
    case suppressed
}

/// A guidance tip with live-phase presentation and sort rank for the Live list.
public struct PrioritizedTip: Equatable, Identifiable, Sendable {
    public var id: String
    public var tip: GuidanceTip
    public var presentation: TipPresentation
    /// Lower = more important.
    public var rank: Int
    /// Optional mid-take banner prepended in UI.
    public var phaseNoteDE: String?

    public init(
        tip: GuidanceTip,
        presentation: TipPresentation,
        rank: Int,
        phaseNoteDE: String? = nil
    ) {
        self.id = tip.id + ":" + presentation.rawValue
        self.tip = tip
        self.presentation = presentation
        self.rank = rank
        self.phaseNoteDE = phaseNoteDE
    }
}

/// Snapshot for Live UI while guiding the user before and during filming.
public struct FilmingGuidanceSnapshot: Equatable, Sendable {
    public struct Values: Sendable {
        public var phase: FilmingPhase = .preRoll
        public var rankedTips: [PrioritizedTip] = []
        public var headlineDE = ""
        public var audio = AudioGuidance(status: .silent, message: "", actionHint: "", isReady: false)
        public var liveUpdatesActive = true

        public init() {}
    }

    public var phase: FilmingPhase
    public var rankedTips: [PrioritizedTip]
    public var headlineDE: String
    public var audio: AudioGuidance
    /// Always true when sensors are live - guidance is not frozen at pre-roll.
    public var liveUpdatesActive: Bool

    public init(_ values: Values = Values()) {
        phase = values.phase
        rankedTips = values.rankedTips
        headlineDE = values.headlineDE
        audio = values.audio
        liveUpdatesActive = values.liveUpdatesActive
    }

    public var visibleTips: [PrioritizedTip] {
        rankedTips.filter { $0.presentation != .suppressed }
    }

    public var criticalCount: Int {
        visibleTips.filter { $0.tip.severity == .critical && $0.presentation == .active }.count
    }
}

/// Pure mid-take / pre-roll prioritization for continuous Unterrichtsvideographie.
/// - Pre-roll: all tips active, ranked by severity (critical first).
/// - Recording: critical visual + bad audio stay active; composition/board reframe
///   become postTakeNote (do not interrupt continuous take); pure OK tips suppressed.
public struct FilmingGuidancePolicy: Sendable {
    public var audioEvaluator: AudioReadinessEvaluator

    public init(audioEvaluator: AudioReadinessEvaluator = .default) {
        self.audioEvaluator = audioEvaluator
    }

    /// Rank and classify visual + audio tips for the current filming phase.
    public func evaluate(
        visual: GuidanceResult,
        audioSample: AudioLevelSample,
        isRecording: Bool
    ) -> FilmingGuidanceSnapshot {
        let audio = audioEvaluator.evaluate(audioSample)
        let phase: FilmingPhase = isRecording ? .recording : .preRoll
        let ranked = rankedTips(visual: visual, audio: audio, isRecording: isRecording)
        var values = FilmingGuidanceSnapshot.Values()
        values.phase = phase
        values.rankedTips = ranked
        values.headlineDE = headline(visual: visual, audio: audio, ranked: ranked, isRecording: isRecording)
        values.audio = audio
        return FilmingGuidanceSnapshot(values)
    }

    private func rankedTips(
        visual: GuidanceResult,
        audio: AudioGuidance,
        isRecording: Bool
    ) -> [PrioritizedTip] {
        let audioTips = audioTip(audio, isRecording: isRecording).map { [$0] } ?? []
        let visualTips = visual.tips.map { classify(tip: $0, isRecording: isRecording) }
        return (audioTips + visualTips).sorted(by: priorityOrder)
    }

    private func audioTip(_ audio: AudioGuidance, isRecording: Bool) -> PrioritizedTip? {
        guard !audio.isReady || audio.status == .hot else { return nil }
        let severity = audioSeverity(for: audio)
        let tip = GuidanceTip((
            id: "audio-\(audio.status.rawValue)", category: .general, severity: severity,
            message: audio.message, actionHint: isRecording ? midTakeAudioAction(audio) : audio.actionHint
        ))
        return PrioritizedTip(
            tip: tip, presentation: .active, rank: severityRank(severity),
            phaseNoteDE: isRecording ? "Während der Aufnahme · Audio" : nil
        )
    }

    private func audioSeverity(for audio: AudioGuidance) -> GuidanceSeverity {
        switch audio.status {
        case .clipping, .silent, .dropout: return .critical
        case .low: return .warning
        case .hot: return audio.isReady ? .info : .warning
        case .good: return .info
        }
    }

    private func priorityOrder(_ left: PrioritizedTip, _ right: PrioritizedTip) -> Bool {
        if left.rank != right.rank { return left.rank < right.rank }
        if left.tip.severity != right.tip.severity { return left.tip.severity > right.tip.severity }
        return left.tip.id < right.tip.id
    }

    private func headline(
        visual: GuidanceResult,
        audio: AudioGuidance,
        ranked: [PrioritizedTip],
        isRecording: Bool
    ) -> String {
        isRecording ? recordingHeadline(ranked) : preRollHeadline(visual: visual, audio: audio)
    }

    private func recordingHeadline(_ ranked: [PrioritizedTip]) -> String {
        let criticalCount = ranked.filter { $0.presentation == .active && $0.tip.severity == .critical }.count
        return criticalCount > 0
            ? "Aufnahme läuft - \(criticalCount) kritische Hinweise (Take möglichst fortsetzen)."
            : "Aufnahme läuft - Live-Überwachung aktiv (kontinuierlicher Take)."
    }

    private func preRollHeadline(visual: GuidanceResult, audio: AudioGuidance) -> String {
        let criticalCount = visual.tips.filter { $0.severity == .critical }.count
        if criticalCount > 0 { return "Vor der Aufnahme: \(criticalCount) kritische Punkte beheben." }
        return audio.isReady
            ? "Pre-Roll: Bild, Lage und Audio prüfen - dann kontinuierliche Aufnahme starten."
            : "Vor der Aufnahme: Audiopegel prüfen."
    }

    // MARK: - Classification

    private func classify(tip: GuidanceTip, isRecording: Bool) -> PrioritizedTip {
        if !isRecording {
            return PrioritizedTip(
                tip: tip,
                presentation: .active,
                rank: severityRank(tip.severity)
            )
        }
        return recordingClassification(for: tip)
    }

    private func recordingClassification(for tip: GuidanceTip) -> PrioritizedTip {
        // Mid-take: continuous classroom capture prefers not reframing for mild issues.
        if tip.severity == .ok {
            return PrioritizedTip(tip: tip, presentation: .suppressed, rank: 90)
        }

        if isCriticalMidTake(tip) {
            var adjusted = tip
            if !adjusted.actionHint.contains("Take") {
                adjusted = GuidanceTip((
                    id: tip.id,
                    category: tip.category,
                    severity: tip.severity,
                    message: tip.message,
                    actionHint: midTakeAction(for: tip)
                ))
            }
            return PrioritizedTip(
                tip: adjusted,
                presentation: .active,
                rank: severityRank(tip.severity),
                phaseNoteDE: "Während der Aufnahme"
            )
        }

        // Non-critical reframe / composition → post-take note
        let post = GuidanceTip((
            id: tip.id,
            category: tip.category,
            severity: tip.severity,
            message: tip.message,
            actionHint: "Nach dem Take prüfen: " + tip.actionHint
        ))
        return PrioritizedTip(
            tip: post,
            presentation: .postTakeNote,
            rank: 40 + severityRank(tip.severity),
            phaseNoteDE: "Nach dem Take (kontinuierliche Aufnahme nicht unterbrechen)"
        )
    }

    /// Issues that still matter during a continuous take (image unusable / audio path).
    private func isCriticalMidTake(_ tip: GuidanceTip) -> Bool {
        if tip.severity == .critical { return true }
        if tip.category == .people { return tip.severity == .warning }
        let warningCriticalCategories: Set<GuidanceCategory> = [.backlight, .orientation, .motion]
        return warningCriticalCategories.contains(tip.category) && tip.severity >= .warning
    }

    private func midTakeAction(for tip: GuidanceTip) -> String {
        let actions: [GuidanceCategory: String] = [
            .orientation: "Nur bei starker Schräglage vorsichtig korrigieren - Take möglichst fortsetzen.",
            .backlight: "Belichtung nicht wild ändern; Take fortsetzen, Standort beim nächsten Take wechseln.",
            .ceiling: "Neigung minimal korrigieren, wenn SuS/Tafel verloren gehen.",
            .interaction: "Take fortsetzen; nächsten Take näher/seitlich-frontal platzieren.",
            .motion: "Stativ ruhig halten - Wackeln erschwert das Erkennen von Bilddetails.",
            .people: "Take fortsetzen wenn möglich; beim nächsten Take Akteure ins Bild holen."
        ]
        return actions[tip.category]
            ?? "Hinweis notieren; kontinuierlichen Take nicht für Feinkorrekturen stoppen."
    }

    private func midTakeAudioAction(_ audio: AudioGuidance) -> String {
        switch audio.status {
        case .silent, .clipping, .dropout:
            return "Sofort Pegel/Mikrofon prüfen - ohne Audio fehlt das Audiosignal der Sequenz."
        case .low:
            return "Gain leicht erhöhen, wenn möglich ohne den Take zu stoppen."
        case .hot:
            return "Gain leicht senken bei Spitzen."
        case .good:
            return audio.actionHint
        }
    }

    private func severityRank(_ s: GuidanceSeverity) -> Int {
        switch s {
        case .critical: return 0
        case .warning: return 10
        case .info: return 20
        case .ok: return 50
        }
    }
}
