import Foundation
import GuidanceEngine
import SessionCore

/// Expected / observed teaching-scene structure (not mere camera placement).
public enum TeachingSceneType: String, Codable, CaseIterable, Sendable, Identifiable {
    case emptyOrUnusable
    case boardCentricFrontal
    case multiPersonGroup
    case dialoguePair
    case studentAtBoard
    case experimentSpread
    case wholeRoomOverview
    case circleDiscussion
    case boardOnly
    case actorsWithoutBoard
    /// Scattered individual seatwork (TIMSS seatwork individual).
    case individualSeatwork
    /// Teacher modeling / demonstration at board or materials.
    case teacherDemonstration
    /// Transition / organization moment (whole-room, lower instructional clarity).
    case transitionMoment

    public var id: String { rawValue }

    public var titleDE: String {
        switch self {
        case .emptyOrUnusable: return "Leer / ohne zugeordnete Szene"
        case .boardCentricFrontal: return "Tafel-frontal"
        case .multiPersonGroup: return "Mehrpersonen-Gruppe"
        case .dialoguePair: return "Dialog-Paar"
        case .studentAtBoard: return "Präsentation an Tafel"
        case .experimentSpread: return "Experiment / verteilt"
        case .wholeRoomOverview: return "Raumübersicht"
        case .circleDiscussion: return "Kreis / Plenum"
        case .boardOnly: return "Nur Schreibfläche"
        case .actorsWithoutBoard: return "Akteure ohne Tafel"
        case .individualSeatwork: return "Stillarbeit / verstreut"
        case .teacherDemonstration: return "Lehr-Demonstration"
        case .transitionMoment: return "Übergang / Organisation"
        }
    }
}

/// Situation-specific capture / scene expectations consumed by guidance and coding.
public struct TeachingSituationPreset: Equatable, Sendable, Identifiable {
    public var id: TeachingSituationID
    public var titleDE: String
    public var summaryDE: String
    /// Primary scene types treated as matches by the unvalidated preset rule.
    public var expectedScenes: [TeachingSceneType]
    /// Secondary acceptable scenes (lower match score, not hard fail).
    public var acceptableScenes: [TeachingSceneType]
    /// Whether a usable writing surface is required for this situation.
    public var requiresBoard: Bool
    /// Minimum person count for a matching scene (0 = board-only situations allowed).
    public var minPeople: Int
    /// Prefer multi-person clusters (group / circle / management).
    public var prefersMultiPerson: Bool
    /// Relative weight for board cues in placement / readiness (0...1).
    public var boardEmphasis: Double
    /// Relative weight for people / interaction cues (0...1).
    public var peopleEmphasis: Double
    /// Relative weight for co-presence (board↔people) (0...1).
    public var coPresenceEmphasis: Double
    /// IPN dimension IDs emphasized for later coding (documentation + soft priors).
    public var ipnEmphasis: [String]
    /// TIMSS-style activity codes expected under good capture of this situation.
    public var expectedTIMSSActivities: [String]
    /// GTI/TALIS Video quality facets emphasized for coding priors.
    public var gtiEmphasis: [String]
    /// Preferred classroom layout patterns (structure CV).
    public var preferredLayouts: [ClassroomLayoutPattern]
    /// German action hint when observed scene mismatches the preset.
    public var mismatchHintDE: String
    /// Proactive capture guidance for this situation (setup / pre-roll).
    public var captureGuidanceDE: String

    public struct Values: Sendable {
        public var id: TeachingSituationID = .frontalBoardInstruction
        public var titleDE = ""
        public var summaryDE = ""
        public var expectedScenes: [TeachingSceneType] = []
        public var acceptableScenes: [TeachingSceneType] = []
        public var requiresBoard = false
        public var minPeople = 0
        public var prefersMultiPerson = false
        public var boardEmphasis = 0.0
        public var peopleEmphasis = 0.0
        public var coPresenceEmphasis = 0.0
        public var ipnEmphasis: [String] = []
        public var expectedTIMSSActivities: [String] = []
        public var gtiEmphasis: [String] = []
        public var preferredLayouts: [ClassroomLayoutPattern] = []
        public var mismatchHintDE = ""
        public var captureGuidanceDE = ""

        public init() {}
    }

    public init(_ values: Values) {
        id = values.id
        titleDE = values.titleDE
        summaryDE = values.summaryDE
        expectedScenes = values.expectedScenes
        acceptableScenes = values.acceptableScenes
        requiresBoard = values.requiresBoard
        minPeople = values.minPeople
        prefersMultiPerson = values.prefersMultiPerson
        boardEmphasis = min(1, max(0, values.boardEmphasis))
        peopleEmphasis = min(1, max(0, values.peopleEmphasis))
        coPresenceEmphasis = min(1, max(0, values.coPresenceEmphasis))
        ipnEmphasis = values.ipnEmphasis
        expectedTIMSSActivities = values.expectedTIMSSActivities
        gtiEmphasis = values.gtiEmphasis
        preferredLayouts = values.preferredLayouts
        mismatchHintDE = values.mismatchHintDE
        captureGuidanceDE = values.captureGuidanceDE
    }

    public static func make(_ configure: (inout Values) -> Void) -> TeachingSituationPreset {
        var values = Values()
        configure(&values)
        return TeachingSituationPreset(values)
    }

    // MARK: Configured experimental thresholds

    /// Minimum multi-cue board score used by the unvalidated preset rule.
    public var minResearchBoardScore: Double {
        requiresBoard ? min(0.85, 0.32 + 0.28 * boardEmphasis) : 0
    }

    /// Minimum interaction density used by the unvalidated multi-person or dialogue rule.
    public var minResearchInteractionDensity: Double {
        if prefersMultiPerson || minPeople >= 3 { return 0.26 + 0.08 * peopleEmphasis }
        if minPeople >= 2 { return 0.20 + 0.06 * peopleEmphasis }
        if minPeople >= 1 { return 0.10 + 0.04 * peopleEmphasis }
        return 0
    }

    /// Minimum layout-fit score against preferredLayouts.
    public var minResearchLayoutFit: Double {
        preferredLayouts.isEmpty ? 0.25 : 0.38 + 0.08 * peopleEmphasis
    }

    /// Minimum board text density when writing surface carries goal clarity (IPN/GTI).
    public var minResearchBoardTextDensity: Double {
        requiresBoard ? min(0.55, 0.12 + 0.22 * boardEmphasis) : 0
    }

    /// Minimum co-presence used by the unvalidated board-centric rule.
    public var minResearchCoPresence: Double {
        coPresenceEmphasis >= 0.55 ? min(0.75, 0.22 + 0.45 * coPresenceEmphasis) : 0.08
    }
}
