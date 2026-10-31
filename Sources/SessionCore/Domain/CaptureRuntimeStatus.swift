import Foundation

/// Device/capture facts shown to the operator and copied into the durable take manifest.
public struct CaptureRuntimeStatus: Equatable, Sendable {
    /// Battery level at or below which capture raises a resource warning and a recording blocker.
    public static let lowBatteryPercent = 15

    public var videoConfiguration: String
    public var audioRoute: String
    public var batteryPercent: Int?
    /// Persisted verbatim: "normal", "erhöht", "ernst", "kritisch" or "unbekannt".
    public var thermalState: String
    public var spokenAudioCheckCompleted: Bool
    /// `nil` means the platform did not provide an important-usage capacity value.
    public var availableCapacityBytes: Int64?

    public init(
        videoConfiguration: String = "Noch nicht ausgehandelt",
        audioRoute: String = "Keine Audioroute",
        batteryPercent: Int? = nil,
        thermalState: String = "unbekannt",
        spokenAudioCheckCompleted: Bool = false,
        availableCapacityBytes: Int64? = nil
    ) {
        self.videoConfiguration = videoConfiguration
        self.audioRoute = audioRoute
        self.batteryPercent = batteryPercent
        self.thermalState = thermalState
        self.spokenAudioCheckCompleted = spokenAudioCheckCompleted
        self.availableCapacityBytes = availableCapacityBytes
    }

    public var hasResourceWarning: Bool {
        (batteryPercent.map { $0 <= Self.lowBatteryPercent } ?? false)
            || thermalState == "ernst"
            || thermalState == "kritisch"
            || (availableCapacityBytes.map { $0 < CaptureCapacity.minimumFreeCapacityBytes } ?? false)
    }
}

/// Capture estimates for the preflight storage check and the in-flight free-capacity reserve.
/// The planned duration is bounded by `CaptureSession` (1...240 minutes) and never caps a take.
public enum CaptureCapacity {
    public static let estimatedBytesPerSecond: Int64 = 1_500_000
    public static let minimumFreeCapacityBytes: Int64 = 500_000_000

    /// Clamps a planned duration to the 1...240 minute range `CaptureSession` admits.
    public static func boundedDurationMinutes(_ plannedDurationMinutes: Int) -> Int {
        min(240, max(1, plannedDurationMinutes))
    }

    /// Estimated file size for a planned duration. A planning value, never a recording cap.
    public static func maximumFileSize(forPlannedDurationMinutes plannedDurationMinutes: Int) -> Int64 {
        Int64(boundedDurationMinutes(plannedDurationMinutes)) * 60 * estimatedBytesPerSecond
    }

    /// Never retain a device-provided route name: port types are stable capability categories.
    public static func normalizedAudioRoute(portTypeRawValues: [String]) -> String {
        let types = Array(Set(portTypeRawValues)).sorted()
        guard !types.isEmpty else { return "Keine Audioroute" }
        let externalTypes: Set<String> = ["HeadsetMic", "USBAudio", "BluetoothHFP", "BluetoothLE"]
        let hasExternalInput = !externalTypes.isDisjoint(with: Set(types))
        return "Eingangstypen: \(types.joined(separator: ", ")) · extern: \(hasExternalInput ? "ja" : "nein")"
    }
}
