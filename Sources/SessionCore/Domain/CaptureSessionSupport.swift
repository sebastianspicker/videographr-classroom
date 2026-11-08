import Foundation

/// Capture purpose recorded for the local session workflow.
public enum CapturePurpose: String, Codable, CaseIterable, Sendable, Identifiable {
    case ownTeaching
    case otherTeaching
    case mixed

    public var id: String { rawValue }

    public var titleDE: String {
        switch self {
        case .ownTeaching: return "Eigener Unterricht"
        case .otherTeaching: return "Fremder Unterricht"
        case .mixed: return "Eigene + fremde Sequenzen"
        }
    }

    public var researchNoteDE: String {
        switch self {
        case .ownTeaching:
            return "Höhere Authentizität/Motivation; kritische Distanz oft schwieriger (Seidel et al. 2011; Krammer 2014)."
        case .otherTeaching:
            return "Mehr kritische Distanz und Theoriebezug - gut zum Einstieg (Krammer 2014)."
        case .mixed:
            return "Empfohlene Kombination: zuerst fremde Clips für Diskursnormen, dann eigene Videos."
        }
    }
}

/// Seminar / research analysis focus selected in Setup (maps to coding soft priors).
/// The session's `analysisIntent` and a coding snapshot's `analysisFocus` share one enum,
/// so both persisted formats use the same raw values.
public typealias AnalysisIntent = CodingAnalysisFocus

/// Lesson / classroom context carried into reflection (Krammer/Reusser, portals).
public struct SessionContext: Codable, Equatable, Sendable {
    public struct Values: Sendable {
        public var subject = ""
        public var gradeLevel = ""
        public var lessonGoal = ""
        public var schoolOrSite = ""
        public var notes = ""

        public init() {}
    }

    public var subject: String
    public var gradeLevel: String
    public var lessonGoal: String
    public var schoolOrSite: String
    public var notes: String

    public init(_ values: Values = Values()) {
        subject = values.subject
        gradeLevel = values.gradeLevel
        lessonGoal = values.lessonGoal
        schoolOrSite = values.schoolOrSite
        notes = values.notes
    }

    public var isMinimallyComplete: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !lessonGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Explicit consent / secondary-use acknowledgment (Derry ethics; not full DSGVO product).
/// In-app ethics acknowledgments (not a full institutional DSGVO workflow).
public struct ConsentRecord: Codable, Equatable, Sendable {
    public var informedParticipantsAcknowledged: Bool
    public var secondaryUseAcknowledged: Bool
    public var storageResponsibilityAcknowledged: Bool
    public var acknowledgedAt: Date?

    public init(
        informedParticipantsAcknowledged: Bool = false,
        secondaryUseAcknowledged: Bool = false,
        storageResponsibilityAcknowledged: Bool = false,
        acknowledgedAt: Date? = nil
    ) {
        self.informedParticipantsAcknowledged = informedParticipantsAcknowledged
        self.secondaryUseAcknowledged = secondaryUseAcknowledged
        self.storageResponsibilityAcknowledged = storageResponsibilityAcknowledged
        self.acknowledgedAt = acknowledgedAt
    }
}
