import Foundation
import GuidanceEngine
import SessionCore
// MARK: - Code sets (documented, stable)
/// IPN-style process-quality dimension codes (Seidel / Prenzel lineage; software coding layer).
///
/// Complete, exerciseable coding transform from structure/scene features to dimension codes with
/// honest confidence. Not a claim of multi-rater psychometric validation against official codebooks.
public enum IPNDimensionCode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Klassenführung / Strukturierung des Unterrichtsablaufs.
    case classroomOrganization
    /// Zielorientierung / Transparenz der Lernziele (often board-visible goals).
    case goalOrientation
    /// Lernunterstützung / scaffolding in der Interaktion.
    case learningSupport
    /// Kognitive Aktivierung (Aufgaben/Denken sichtbar machen).
    case cognitiveActivation
    /// Sozialklima / partizipative Interaktionsstruktur.
    case socialClimate
    /// Fehlerkultur / Umgang mit Schülerantworten (proxy via dialogue structure).
    case errorCulture
    /// Experimentierphasen / hands-on structure (IPN Videostudie Physics experimentation facet).
    case experimentation
    public var id: String { rawValue }
    public var titleDE: String {
        switch self {
        case .classroomOrganization: return "Klassenführung / Organisation"
        case .goalOrientation: return "Zielorientierung / Klarheit"
        case .learningSupport: return "Lernunterstützung"
        case .cognitiveActivation: return "Kognitive Aktivierung"
        case .socialClimate: return "Sozialklima"
        case .errorCulture: return "Fehlerkultur (Proxy)"
        case .experimentation: return "Experimentieren / Hands-on"
        }
    }
    public var researchNoteDE: String {
        switch self {
        case .classroomOrganization:
            return "IPN: Organisation des Unterrichts; Struktur und Übersichtlichkeit des Lehr-Lern-Geschehens."
        case .goalOrientation:
            return "IPN: Zielklarheit/Transparenz - positiv mit kognitiven Lernaspekten assoziiert (Seidel et al. 2006)."
        case .learningSupport:
            return "IPN: Lernunterstützung - stärker mit Einstellungen/Interesse verknüpft."
        case .cognitiveActivation:
            return "Prozessqualität: kognitiv anregende Aufgaben und Denkprozesse sichtbar machen."
        case .socialClimate:
            return "Soziale Einbindung und Interaktionsdichte (TALIS/IPN-nah)."
        case .errorCulture:
            return "Proxy aus Dialog-/Unterstützungsstruktur - nicht validierte Fehlerkodierung."
        case .experimentation:
            return "IPN Videostudie: Experimentierphasen / hands-on structure as process-quality facet (Seidel et al. 2006)."
        }
    }
}
/// TIMSS-style instructional / activity structure (lesson-script) codes.
public enum TIMSSActivityCode: String, Codable, CaseIterable, Sendable, Identifiable {
    case wholeClassInstruction
    case publicBoardWork
    case studentPresentation
    case recitationDialogue
    case groupWork
    case partnerWork
    case seatworkCollaborative
    case seatworkIndividual
    case experimentLab
    case discussionPlenum
    case transitionOrganization
    case unclearOrNonInstructional
    public var id: String { rawValue }
    public var titleDE: String {
        switch self {
        case .wholeClassInstruction: return "Ganzklassenunterricht"
        case .publicBoardWork: return "Öffentliche Tafelarbeit"
        case .studentPresentation: return "SuS-Präsentation"
        case .recitationDialogue: return "Rezitation / Dialog"
        case .groupWork: return "Gruppenarbeit"
        case .partnerWork: return "Partnerarbeit"
        case .seatworkCollaborative: return "Kooperative Still-/Tischarbeit"
        case .seatworkIndividual: return "Individuelle Stillarbeit"
        case .experimentLab: return "Experiment / Praktikum"
        case .discussionPlenum: return "Diskussion / Plenum"
        case .transitionOrganization: return "Übergang / Organisation"
        case .unclearOrNonInstructional: return "Unklar / nicht-instruktional"
        }
    }
}
/// Single coded dimension with ordinal level and confidence.
public struct PedagogicalCodeAssignment: Equatable, Sendable, Identifiable {
    public var id: String
    public var family: PedagogicalCodeFamily
    public var code: String
    public var labelDE: String
    /// Ordinal intensity / presence 0...1 (structure proxy, not human rater score).
    public var level: Double
    public var confidence: Double
    public var rationaleDE: String
    public struct Identity: Equatable, Sendable {
        public var id: String
        public var family: PedagogicalCodeFamily
        public init(id: String, family: PedagogicalCodeFamily) {
            self.id = id
            self.family = family
        }
    }
    public struct Descriptor: Equatable, Sendable {
        public var code: String
        public var labelDE: String
        public init(code: String, labelDE: String) {
            self.code = code
            self.labelDE = labelDE
        }
    }
    public struct Measurement: Equatable, Sendable {
        public var level: Double
        public var confidence: Double
        public init(level: Double, confidence: Double) {
            self.level = level
            self.confidence = confidence
        }
    }
    public struct Values: Equatable, Sendable {
        public var identity: Identity
        public var descriptor: Descriptor
        public var measurement: Measurement
        public var rationaleDE: String
        public init(
            identity: Identity,
            descriptor: Descriptor,
            measurement: Measurement,
            rationaleDE: String
        ) {
            self.identity = identity
            self.descriptor = descriptor
            self.measurement = measurement
            self.rationaleDE = rationaleDE
        }
    }
    public init(_ values: Values) {
        id = values.identity.id
        family = values.identity.family
        code = values.descriptor.code
        labelDE = values.descriptor.labelDE
        level = min(1, max(0, values.measurement.level))
        confidence = min(1, max(0, values.measurement.confidence))
        rationaleDE = values.rationaleDE
    }
}
public enum PedagogicalCodeFamily: String, Codable, Sendable {
    case ipnProcessQuality
    case timssActivityScript
    case gtiQuality
}
/// Full pedagogical coding output for a frame / short window.
public struct PedagogicalCodingResult: Equatable, Sendable {
    public var ipnDimensions: [PedagogicalCodeAssignment]
    public var timssActivities: [PedagogicalCodeAssignment]
    /// OECD GTI / TALIS Video–aligned quality facets (software proxies).
    public var gtiDimensions: [PedagogicalCodeAssignment]
    /// Primary TIMSS activity (highest level among activity codes).
    public var primaryTIMSS: TIMSSActivityCode
    /// Primary GTI facet (highest level among GTI codes).
    public var primaryGTI: GTIQualityCode
    public var overallConfidence: Double
    public var summaryDE: String
    public var sceneType: TeachingSceneType
    public var teachingSituation: TeachingSituationID
    /// Layout pattern used as coding prior (structure CV).
    public var layoutPattern: ClassroomLayoutPattern
    /// Optional analysis focus that reweighted coding priors.
    public var analysisFocus: CodingAnalysisFocus?
    public struct Assignments: Equatable, Sendable {
        public var ipnDimensions: [PedagogicalCodeAssignment]
        public var timssActivities: [PedagogicalCodeAssignment]
        public var gtiDimensions: [PedagogicalCodeAssignment]
        public init(
            ipnDimensions: [PedagogicalCodeAssignment],
            timssActivities: [PedagogicalCodeAssignment],
            gtiDimensions: [PedagogicalCodeAssignment] = []
        ) {
            self.ipnDimensions = ipnDimensions
            self.timssActivities = timssActivities
            self.gtiDimensions = gtiDimensions
        }
    }
    public struct PrimaryCodes: Equatable, Sendable {
        public var timss: TIMSSActivityCode
        public var gti: GTIQualityCode
        public init(timss: TIMSSActivityCode, gti: GTIQualityCode = .instructionalQuality) {
            self.timss = timss
            self.gti = gti
        }
    }
    public struct Context: Equatable, Sendable {
        public var sceneType: TeachingSceneType
        public var teachingSituation: TeachingSituationID
        public var layoutPattern: ClassroomLayoutPattern
        public var analysisFocus: CodingAnalysisFocus?
        public init(
            sceneType: TeachingSceneType,
            teachingSituation: TeachingSituationID,
            layoutPattern: ClassroomLayoutPattern = .unknown,
            analysisFocus: CodingAnalysisFocus? = nil
        ) {
            self.sceneType = sceneType
            self.teachingSituation = teachingSituation
            self.layoutPattern = layoutPattern
            self.analysisFocus = analysisFocus
        }
    }
    public struct Content: Equatable, Sendable {
        public var assignments: Assignments
        public var primaryCodes: PrimaryCodes
        public var overallConfidence: Double
        public var summaryDE: String
        public init(
            assignments: Assignments,
            primaryCodes: PrimaryCodes,
            overallConfidence: Double,
            summaryDE: String
        ) {
            self.assignments = assignments
            self.primaryCodes = primaryCodes
            self.overallConfidence = overallConfidence
            self.summaryDE = summaryDE
        }
    }
    public struct Values: Equatable, Sendable {
        public var content: Content
        public var context: Context
        public init(content: Content, context: Context) {
            self.content = content
            self.context = context
        }
    }
    public init(_ values: Values) {
        ipnDimensions = values.content.assignments.ipnDimensions
        timssActivities = values.content.assignments.timssActivities
        gtiDimensions = values.content.assignments.gtiDimensions
        primaryTIMSS = values.content.primaryCodes.timss
        primaryGTI = values.content.primaryCodes.gti
        overallConfidence = min(1, max(0, values.content.overallConfidence))
        summaryDE = values.content.summaryDE
        sceneType = values.context.sceneType
        teachingSituation = values.context.teachingSituation
        layoutPattern = values.context.layoutPattern
        analysisFocus = values.context.analysisFocus
    }
    public static func empty(
        situation: TeachingSituationID = .frontalBoardInstruction,
        scene: TeachingSceneType = .emptyOrUnusable
    ) -> PedagogicalCodingResult {
        PedagogicalCodingResult(
            .init(
                content: .init(
                    assignments: .init(ipnDimensions: [], timssActivities: []),
                    primaryCodes: .init(timss: .unclearOrNonInstructional, gti: .classroomManagement),
                    overallConfidence: 0,
                    summaryDE: "Keine pädagogische Kodierung - unzureichende Szenen-/CV-Signale."
                ),
                context: .init(sceneType: scene, teachingSituation: situation, layoutPattern: .empty)
            )
        )
    }
}
