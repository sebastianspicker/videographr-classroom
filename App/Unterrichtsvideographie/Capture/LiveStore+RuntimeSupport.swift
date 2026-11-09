import AVFoundation
import Foundation
import SessionCore
import UIKit

extension LiveStore {
    internal func handleRuntimeError(_ error: Error?) {
        // AVCaptureSession runtime-error notifications are not generation-tagged. Once a
        // simulator fallback owns this Live generation, a late hardware-session error must not
        // replace the usable synthetic preview or suspend its UI.
        guard liveIsActive, !usingSimulatorFallback else { return }
        let nsError = error as NSError?
        lastError = error?.localizedDescription ?? "Unbekannter Capture-Fehler"
        persistOperationalObservation(
            kind: .error,
            note: "Capture-Laufzeitfehler: \(lastError ?? "unbekannt")"
        )
        privacyCoverIsVisible = true
        if nsError?.code == AVError.mediaServicesWereReset.rawValue,
           viewWantsLive, appIsActive, !captureIsInterrupted,
           runtimeRecoveryAttempts < maximumRuntimeRecoveryAttempts {
            runtimeRecoveryAttempts += 1
            recordStatusMessage = "Kameradienst wurde zurückgesetzt - Wiederherstellung läuft."
            suspend()
            DispatchQueue.main.async { [weak self] in self?.resumeIfDesired() }
        } else {
            canRetryCapture = true
            recordStatusMessage = "Capture-Fehler - erneut versuchen oder Berechtigungen prüfen."
            suspend()
        }
    }

    internal func refreshRuntimeStatus() {
        refreshBatteryStatus()
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: runtimeStatus.thermalState = "normal"
        case .fair: runtimeStatus.thermalState = "erhöht"
        case .serious: runtimeStatus.thermalState = "ernst"
        case .critical: runtimeStatus.thermalState = "kritisch"
        @unknown default: runtimeStatus.thermalState = "unbekannt"
        }
        runtimeStatus.audioRoute = CaptureCapacity.normalizedAudioRoute(
            portTypeRawValues: AVAudioSession.sharedInstance().currentRoute.inputs.map { $0.portType.rawValue }
        )
    }

    private func refreshBatteryStatus() {
        let battery = UIDevice.current.batteryLevel
        runtimeStatus.batteryPercent = battery >= 0 ? Int((battery * 100).rounded()) : nil
    }

    internal func disableIdleTimerForRecording() {
        guard previousIdleTimerDisabled == nil else { return }
        previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
    }

    internal func restoreIdleTimer() {
        guard let previousIdleTimerDisabled else { return }
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        self.previousIdleTimerDisabled = nil
    }

    /// Face-up/down/unknown keep the last valid angle (a tilted tripod phone reports face-up).
    private static var lastValidRotationAngle: CGFloat = 90

    internal static func rotationAngle() -> CGFloat {
        switch UIDevice.current.orientation {
        case .portrait: lastValidRotationAngle = 90
        case .portraitUpsideDown: lastValidRotationAngle = 270
        case .landscapeLeft: lastValidRotationAngle = 180
        case .landscapeRight: lastValidRotationAngle = 0
        default: break
        }
        return lastValidRotationAngle
    }
}
