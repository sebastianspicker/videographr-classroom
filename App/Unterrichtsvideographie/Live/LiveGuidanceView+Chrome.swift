import GuidanceEngine
import SessionCore
import SwiftUI

extension LiveGuidanceView {
    func liveStage(previewHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Space.s) {
                    sessionHeading
                    LocalityMark()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, Space.m)
            }
            if dynamicTypeSize.isAccessibilitySize && previewIsUnavailable {
                accessiblePreviewUnavailableState
            } else {
                previewPane
                    .frame(height: previewHeight)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay { Rectangle().strokeBorder(Room.rule, lineWidth: 1) }
            }
            signalStrip.padding(.vertical, Space.l)
            captureDock
            Text("Direkte technische Beobachtungen · keine Unterrichtsbewertung")
                .font(Typeface.captionSmall)
                .foregroundStyle(Room.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Space.l)
        }
        .padding(Space.l)
    }

    var liveToolbar: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Space.xs) {
                    exitButton
                    detailsButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                standardToolbar
            }
        }
        .padding(.horizontal, Space.gutterCompact)
        .padding(.vertical, Space.xs)
        .background(Room.surface)
        .overlay(alignment: .bottom) { Rule() }
    }

    private var standardToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.gutterCompact) {
                exitButton
                Spacer(minLength: 0)
                sessionHeading
                Spacer(minLength: 0)
                detailsButton
            }
            VStack(alignment: .leading, spacing: Space.s) {
                HStack { exitButton; Spacer(); detailsButton }
                sessionHeading
            }
        }
    }

    private var exitButton: some View {
        Button(action: onExit) {
            Label("Sitzung", systemImage: "arrow.left")
        }
        .buttonStyle(InkButtonStyle(kind: .quiet))
        .accessibilityIdentifier("live.exit")
        .accessibilityLabel("Zur Sitzung")
    }

    private var sessionHeading: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize || horizontalSizeClass != .regular ? .leading : .center, spacing: Space.xxs) {
            Text(appStore.session.title.isEmpty ? "Neue Sitzung" : appStore.session.title)
                .font(Typeface.heading)
                .foregroundStyle(Room.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            Text([appStore.session.context.subject,
                  appStore.session.context.gradeLevel.isEmpty ? "" : "Klasse \(appStore.session.context.gradeLevel)"]
                .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(Typeface.valueSmall)
                .foregroundStyle(Room.secondary)
        }
    }

    private var detailsButton: some View {
        Button { inspectorIsVisible.toggle() } label: {
            Label("Messwerte & Freigaben", systemImage: "list.bullet.rectangle")
        }
        .buttonStyle(InkButtonStyle(kind: horizontalSizeClass == .regular ? .secondary : .quiet))
        .accessibilityIdentifier("live.inspector.toggle")
    }

    var inspectorPane: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                Text("Messwerte & Freigaben")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Room.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.s)
                Button("Fertig") { inspectorIsVisible = false }
                    .buttonStyle(InkButtonStyle(kind: .quiet))
            }
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.m)
            Rule()
            liveGuidanceEvidencePane(maximumDimensions: 4)
        }
        .roomSurface()
    }

    var captureDock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if dynamicTypeSize.isAccessibilitySize || horizontalSizeClass != .regular {
                    compactConsole
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        timingBlock
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.trailing, Space.xl)
                        consoleDivider
                        audioMeter
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Space.xl)
                        consoleDivider
                        recordBlock
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, Space.xl)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, Space.l)
            Rule()
        }
        .accessibilityElement(children: .contain)
    }

    private var compactConsole: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            recordBlock
            Rule()
            timingBlock
            Rule()
            audioMeter
        }
    }

    private var consoleDivider: some View {
        Rectangle()
            .fill(Room.rule)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    private var audioMeter: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            FormLabel("Ton")
            LiveAudioMeter(peak: previewIsUnavailable ? 0 : liveStore.audioSample.peakLevel,
                           average: previewIsUnavailable ? 0 : liveStore.audioSample.averageLevel)
                .frame(height: 20)
                .accessibilityLabel("Gemessener Audiopegel")
                .accessibilityValue(audioStatusText)
            Text(liveStore.usingSimulatorFallback || liveStore.privacyCoverIsVisible
                 ? "Audiosignal nicht verfügbar" : filming.audio.message)
                .font(Typeface.caption)
                .foregroundStyle(Room.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Sprachverständlichkeit wird nicht gemessen.")
                .font(Typeface.captionSmall)
                .foregroundStyle(Room.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var timingBlock: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Group {
                if liveStore.isRecording, let recordingStartedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(elapsedTimeLabel(from: recordingStartedAt, to: context.date))
                    }
                } else {
                    Text("00:00")
                }
            }
            .font(Typeface.timecode)
            .monospacedDigit()
            .foregroundStyle(Room.primary)
            Text("geplant \(appStore.session.plannedDurationMinutes) Min.")
                .font(Typeface.valueSmall)
                .foregroundStyle(Room.secondary)
            Group {
                if appStore.session.canStartNewCapture {
                    StatusMark("Erhebung und lokale Reflexion freigegeben", kind: .secured)
                } else {
                    StatusMark("Freigaben für Aufnahme fehlen", kind: .attention)
                }
            }
            .padding(.top, Space.xs)
        }
    }

    private var recordBlock: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Button {
                liveStore.isRecording ? liveStore.stopRecording() : beginRecording()
            } label: {
                Text(recordActionTitle)
            }
            .buttonStyle(RecordButtonStyle(isRecording: liveStore.isRecording))
            .disabled(liveStore.isStartingRecording || liveStore.isPreparingRecording || liveStore.isFinalizingRecording
                || (!liveStore.isRecording && (audioCheck.blocksCapture || !readiness.canOverrideQualityWarnings || !overrideIsValid)))
            .accessibilityIdentifier("live.captureDock")
            .accessibilityLabel(liveStore.isRecording ? "Aufnahme stoppen" : "Aufnahme starten")
            StatusMark(recordingStateLabel, kind: recordingStateKind)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(recordingStateLabel)
                .accessibilityIdentifier("live.recordingState")
                .accessibilityValue(recordingStateAccessibilityValue)
            if !liveStore.isRecording && !liveStore.runtimeStatus.spokenAudioCheckCompleted {
                Button("Sprechprobe und Startbedingungen prüfen") { inspectorIsVisible = true }
                    .buttonStyle(InkButtonStyle(kind: .quiet))
            } else {
                Text(liveStore.recordStatusMessage ?? "Freigaben werden beim Start erneut geprüft.")
                    .font(Typeface.caption)
                    .foregroundStyle(Room.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var signalStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rule()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    directReadout("Bild", id: "currentFrame")
                    consoleDivider
                    directReadout("Lage", id: "level")
                    consoleDivider
                    directReadout("Belichtung", id: "exposure")
                }
                .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 0) {
                    directReadout("Bild", id: "currentFrame")
                    Rule()
                    directReadout("Lage", id: "level")
                    Rule()
                    directReadout("Belichtung", id: "exposure")
                }
            }
            Rule()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("live.signalStrip")
    }

    private func directReadout(_ title: String, id: String) -> some View {
        let dimension = liveStore.guidance.observability.dimensions.first { $0.id == id }
        let noImage = liveStore.privacyCoverIsVisible || liveStore.usingSimulatorFallback
        let status: CaptureObservabilityDimension.Status = noImage ? .unavailable
            : (dimension?.status ?? (id == "currentFrame" ? .pass : .unavailable))
        let value = status == .unavailable ? "Nicht verfügbar"
            : status == .pass ? (id == "currentFrame" ? "Aktuell" : "Unauffällig")
            : status == .fail ? "Kritisch" : "Prüfen"
        return VStack(alignment: .leading, spacing: Space.xs) {
            FormLabel(title, small: true)
            Label {
                Text(value).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: observabilityIcon(status)).imageScale(.small)
            }
            .labelStyle(ReadoutLabelStyle())
            .font(Typeface.callout.weight(.medium))
            .foregroundStyle(observabilityColor(status))
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var recordingStateLabel: String {
        if liveStore.isFinalizingRecording { return "Datei wird geprüft und lokal gesichert." }
        if liveStore.isStartingRecording { return "Aufnahme startet…" }
        if liveStore.isRecording { return "Aufnahme läuft · kontinuierlicher Take" }
        return readiness.canRecord ? "Direkte Startbedingungen erfüllt" : "Aufnahmebedingungen prüfen"
    }

    private var recordingStateKind: StatusMark.Kind {
        if liveStore.isFinalizingRecording || liveStore.isStartingRecording { return .open }
        if liveStore.isRecording { return .neutral }
        return readiness.canRecord ? .secured : .attention
    }

    private var recordActionTitle: String {
        if liveStore.isFinalizingRecording { return "Aufnahme wird gesichert…" }
        if liveStore.isStartingRecording { return "Aufnahme startet…" }
        return liveStore.isRecording ? "Aufnahme beenden" : "Aufnahme starten"
    }

    private func elapsedTimeLabel(from start: Date, to end: Date) -> String {
        let duration = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%02d:%02d", duration / 60, duration % 60)
    }

    func metricRow(_ title: String, _ value: Double) -> some View {
        instrumentRow(title, String(format: "%.0f %%", value * 100))
    }

    /// A measured value: interface label, graphite mono reading.
    func instrumentRow(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(value)
                .font(Typeface.valueSmall)
                .monospacedDigit()
                .foregroundStyle(Room.instrument)
                .multilineTextAlignment(.trailing)
        } label: {
            Text(title)
                .font(Typeface.callout)
                .foregroundStyle(Room.primary)
        }
    }

    func observabilityIcon(_ status: CaptureObservabilityDimension.Status) -> String {
        switch status {
        case .pass: return "checkmark"
        case .warn: return "exclamationmark.triangle"
        case .fail: return "xmark.octagon"
        case .unavailable: return "minus"
        }
    }

    func observabilityColor(_ status: CaptureObservabilityDimension.Status) -> Color {
        switch status {
        case .pass: return Room.secondary
        case .warn: return Room.attention
        case .fail: return Room.fault
        case .unavailable: return Room.tertiary
        }
    }

    func observabilityValue(_ dimension: CaptureObservabilityDimension) -> String {
        dimension.value.map { String(format: "%.0f %%", $0 * 100) } ?? "-"
    }
}

private struct ReadoutLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon
            configuration.title
        }
    }
}

/// The one signal-red control: it starts and ends the take. Disabled, it
/// carries no red at all.
struct RecordButtonStyle: ButtonStyle {
    let isRecording: Bool
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: isRecording ? "stop.fill" : "circle.fill")
                .imageScale(.medium)
                .foregroundStyle(glyph)
                .accessibilityHidden(true)
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Typeface.body.weight(.semibold))
        .foregroundStyle(text)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 18)
        .padding(.vertical, Space.m)
        .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? Space.target : 56)
        .background(fill, in: RoundedRectangle(cornerRadius: Radius.control))
        .overlay {
            if !isRunning {
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(isEnabled ? Room.ruleStrong : Room.rule, lineWidth: 1)
            }
        }
        .opacity(configuration.isPressed ? 0.72 : 1)
        .contentShape(Rectangle())
    }

    private var isRunning: Bool { isRecording && isEnabled }

    private var fill: Color { isRunning ? Room.signalDeep : Room.raised }

    private var text: Color {
        guard isEnabled else { return Room.tertiary }
        return Room.primary
    }

    private var glyph: Color {
        guard isEnabled else { return Room.tertiary }
        return isRecording ? Room.primary : Room.signal
    }
}

/// A current amplitude sample, not a calibrated scientific quality scale.
private struct LiveAudioMeter: View {
    let peak: Double
    let average: Double
    private let segments = 24

    var body: some View {
        let level = min(1, max(0, max(peak, average)))
        HStack(spacing: Space.xxs) {
            ForEach(0..<segments, id: \.self) { index in
                let position = Double(index) / Double(segments)
                Rectangle()
                    .fill(position < level ? (position >= 0.85 ? Room.attention : Room.instrument) : Room.rule)
            }
        }
        .accessibilityElement(children: .ignore)
    }
}
