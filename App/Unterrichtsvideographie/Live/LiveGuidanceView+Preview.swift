import SwiftUI

extension LiveGuidanceView {
    var previewIsUnavailable: Bool {
        liveStore.usingSimulatorFallback || liveStore.privacyCoverIsVisible
    }

    var accessiblePreviewUnavailableState: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Image(systemName: "video.slash")
                .font(.title2)
                .foregroundStyle(Room.secondary)
                .accessibilityHidden(true)
            Text(previewUnavailableTitle)
                .font(Typeface.heading)
                .foregroundStyle(Room.primary)
            Text(previewUnavailableDetail)
                .font(Typeface.caption)
                .foregroundStyle(Room.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black)
        .overlay { Rectangle().strokeBorder(Room.rule, lineWidth: 1) }
        .accessibilityIdentifier("live.previewUnavailable")
    }
    var previewPane: some View {
        ZStack(alignment: .topLeading) {
            previewImage
            privacyCover
            previewSourceStatus
        }
        .background(Color.black)
    }

    @ViewBuilder private var previewImage: some View {
        if liveStore.usingSimulatorFallback {
            Color.black
            .overlay { simulatorPreviewUnavailableState }
        } else {
            CameraPreviewView(session: liveStore.session)
        }
    }

    /// Simulator values may exercise the direct-signal UI, but never stand in
    /// for a real camera image or recorded take.
    private var simulatorPreviewUnavailableState: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "video.slash")
                .font(.largeTitle)
                .foregroundStyle(Room.secondary)
                .accessibilityHidden(true)
            Text("Keine Kameravorschau im Simulator")
                .font(Typeface.heading)
                .foregroundStyle(Room.primary)
                .accessibilityIdentifier("live.preview")
            Text("Simulator")
                .font(Typeface.labelSmall)
                .foregroundStyle(Room.tertiary)
                .accessibilityIdentifier("live.captureMode")
                .accessibilityValue("simulator")
            Text(liveStore.lastError ?? "Direkte Bildsignale können hier nur als Testwerte vorliegen.")
                .font(Typeface.caption)
                .foregroundStyle(Room.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.xl)
        }
    }

    @ViewBuilder private var privacyCover: some View {
        if liveStore.privacyCoverIsVisible {
            Color.black
                .overlay {
                    VStack(spacing: Space.s) {
                        Image(systemName: "eye.slash.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Room.secondary)
                            .accessibilityHidden(true)
                        Text(previewUnavailableTitle)
                            .font(Typeface.heading)
                            .foregroundStyle(Room.primary)
                            .multilineTextAlignment(.center)
                        Text(previewUnavailableDetail)
                            .font(Typeface.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Room.secondary)
                    }
                    .padding(.horizontal, Space.xxl)
                }
                .accessibilityLabel("Vorschau pausiert, bis ein neues Kamerabild vorliegt")
                .accessibilityIdentifier("live.privacyCover")
        }
    }

    @ViewBuilder private var previewSourceStatus: some View {
        if !previewIsUnavailable && !dynamicTypeSize.isAccessibilitySize {
            HStack(alignment: .top) {
                if liveStore.isRecording {
                    HStack(spacing: Space.s) {
                        Circle()
                            .fill(Room.primary)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text("Aufnahme läuft")
                            .font(Typeface.labelSmall)
                            .foregroundStyle(Room.primary)
                    }
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xs + 2)
                    .background(Room.signalDeep)
                } else {
                    Text("Vorschau · noch keine Aufnahme")
                        .font(Typeface.labelSmall)
                        .foregroundStyle(Room.primary)
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, Space.xs + 2)
                        .background(Color.black.opacity(0.72))
                }
                Spacer(minLength: Space.m)
                Text(liveFormatLabel)
                    .font(Typeface.valueSmall)
                    .monospacedDigit()
                    .foregroundStyle(Room.instrument)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xs + 2)
                    .background(Color.black.opacity(0.72))
            }
            .padding(Space.m)
        }
    }

    private var previewUnavailableTitle: String {
        #if targetEnvironment(simulator)
        return "Keine Kameravorschau im Simulator"
        #else
        if liveStore.authorizationStatus == .denied || liveStore.authorizationStatus == .restricted {
            return "Kamerazugriff nicht verfügbar"
        }
        if liveStore.microphoneAuthorizationStatus == .denied || liveStore.microphoneAuthorizationStatus == .restricted {
            return "Mikrofonzugriff nicht verfügbar"
        }
        return "Warte auf ein aktuelles Kamerabild"
        #endif
    }

    private var previewUnavailableDetail: String {
        #if targetEnvironment(simulator)
        return "Eine Aufnahme benötigt ein aktuelles Kamerabild auf einem unterstützten Gerät."
        #else
        if let lastError = liveStore.lastError, !lastError.isEmpty { return lastError }
        if liveStore.authorizationStatus == .denied || liveStore.authorizationStatus == .restricted {
            return "Erlaube den Kamerazugriff in den Einstellungen und versuche die Kamera anschließend erneut."
        }
        if liveStore.microphoneAuthorizationStatus == .denied || liveStore.microphoneAuthorizationStatus == .restricted {
            return "Erlaube den Mikrofonzugriff in den Einstellungen und versuche die Kamera anschließend erneut."
        }
        return "Aufnahme bleibt blockiert, bis ein aktuelles direktes Bildsignal vorliegt."
        #endif
    }

    var audioStatusText: String {
        if liveStore.privacyCoverIsVisible || liveStore.usingSimulatorFallback { return "nicht verfügbar" }
        return switch filming.audio.status {
        case .silent: "stumm"
        case .low: "niedrig"
        case .good: "gut"
        case .hot: "hoch"
        case .clipping: "übersteuert"
        case .dropout: "Aussetzer"
        }
    }

    var recordingStateAccessibilityValue: String {
        if liveStore.isFinalizingRecording { return "finalizing" }
        if liveStore.isStartingRecording { return "starting" }
        return liveStore.isRecording ? "recording" : "idle"
    }
}
