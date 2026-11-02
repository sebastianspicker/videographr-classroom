import Foundation
import GuidanceEngine
import SessionCore

// MARK: - Preset families

private let teachingSituationFamilies: [String: String] = [
    TeachingSituationID.frontalBoardInstruction.rawValue: "Ganzklasse / Tafel",
    TeachingSituationID.teacherDemonstration.rawValue: "Ganzklasse / Tafel",
    TeachingSituationID.studentBoardPresentation.rawValue: "Ganzklasse / Tafel",
    TeachingSituationID.teacherLedDialogue.rawValue: "Dialog / Feedback",
    TeachingSituationID.formativeAssessmentDialogue.rawValue: "Dialog / Feedback",
    TeachingSituationID.collaborativeGroupWork.rawValue: "Arbeitsformen",
    TeachingSituationID.partnerWork.rawValue: "Arbeitsformen",
    TeachingSituationID.individualSeatwork.rawValue: "Arbeitsformen",
    TeachingSituationID.handsOnExperiment.rawValue: "Experiment",
    TeachingSituationID.classroomManagementOverview.rawValue: "Organisation / Führung",
    TeachingSituationID.transitionOrganization.rawValue: "Organisation / Führung",
    TeachingSituationID.circleOrPlenumDiscussion.rawValue: "Plenum / Diskurs"
]

public extension TeachingSituationCatalogue {
    /// Family grouping for UI (TIMSS-script families).
    static func family(for id: TeachingSituationID) -> String {
        teachingSituationFamilies[id.rawValue] ?? "Unbekannt"
    }
}
