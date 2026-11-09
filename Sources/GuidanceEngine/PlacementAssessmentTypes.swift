import Foundation

/// Direct technical placement status. It does not establish research usability.
public enum PlacementQualityLevel: String, Equatable, Sendable, CaseIterable {
    case directSignalsPass
    case needsAdjustment
    case defective

    public var titleDE: String {
        switch self {
        case .directSignalsPass: return "Direkte Signale ohne Blocker"
        case .needsAdjustment: return "Platzierung anpassen"
        case .defective: return "Technische Signale unzureichend"
        }
    }
}

public struct PlacementDimension: Equatable, Identifiable, Sendable {
    public var id: String
    public var labelDE: String
    public var ok: Bool
    public var detailDE: String

    public init(id: String, labelDE: String, ok: Bool, detailDE: String) {
        self.id = id
        self.labelDE = labelDE
        self.ok = ok
        self.detailDE = detailDE
    }
}
