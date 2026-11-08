import SwiftUI
import ExperimentalResearch
import GuidanceEngine
import SessionCore

extension LiveGuidanceView {
    func liveGuidanceEvidencePane(
        maximumDimensions: Int? = nil,
        prioritizedDimensionID: String? = nil
    ) -> some View {
        var orderedDimensions = liveStore.guidance.observability.dimensions
        if let prioritizedDimensionID,
           let index = orderedDimensions.firstIndex(where: { $0.id == prioritizedDimensionID })
        {
            orderedDimensions.insert(orderedDimensions.remove(at: index), at: 0)
        }
        let dimensions = maximumDimensions.map {
            Array(orderedDimensions.prefix($0))
        } ?? orderedDimensions
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
            if appStore.session.operatingMode == .experimentalResearch,
               appStore.session.hasUsableExperimentalProtocol
            {
                HypothesisBlock(title: "Experimenteller Forschungsmodus · nicht validiert") {
                    Text("Regelhypothesen sind von Aufnahmesignalen getrennt und beeinflussen weder Bereitschaft noch Reflexionsfragen.")
                        .font(Typeface.caption)
                        .foregroundStyle(Room.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, Space.l)
            }

            instrumentSection(
                liveStore.isRecording ? "Direkte Signale während der Aufnahme" : "Direkte Signale vor der Aufnahme",
                detail: "Direkte Signale"
            ) {
                Text(liveStore.isRecording ? "Aufnahme läuft" : (readiness.canRecord ? "Bereit zur Aufnahme" : "Aufnahme prüfen"))
                    .font(Typeface.body.weight(.semibold))
                    .foregroundStyle(Room.primary)
                    .accessibilityIdentifier("live.recordingState")
                    .accessibilityValue(recordingStateAccessibilityValue)
                ForEach(dimensions) { dimension in
                    Rule()
                    HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                        Image(systemName: observabilityIcon(dimension.status))
                            .font(.footnote.weight(.semibold))
                            .imageScale(.small)
                            .foregroundStyle(observabilityColor(dimension.status))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(dimension.labelDE)
                                    .font(Typeface.callout)
                                    .foregroundStyle(Room.primary)
                                Spacer(minLength: Space.s)
                                Text(observabilityStatusLabel(dimension.status))
                                    .font(Typeface.labelSmall)
                                    .foregroundStyle(observabilityColor(dimension.status))
                            }
                                .accessibilityIdentifier("live.observability.\(dimension.id)")
                            Text(dimension.detailDE)
                                .font(Typeface.captionSmall)
                                .foregroundStyle(Room.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(observabilityValue(dimension))
                            .font(Typeface.valueSmall)
                            .monospacedDigit()
                            .foregroundStyle(Room.instrument)
                    }
                }
                Text("Diese Werte beschreiben Aufnahmebedingungen, nicht Unterrichtsqualität.")
                    .font(Typeface.captionSmall)
                    .foregroundStyle(Room.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            recordingControls
            liveTips
            audioControls
            deviceAndFormat
            experimentalHypotheses
            }
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.l)
        }
        .scrollDismissesKeyboard(.immediately)
        .accessibilityIdentifier("live.guidanceList")
    }

    func instrumentSection<Content: View>(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rule()
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    FormLabel(title)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    if let detail {
                        Text(detail)
                            .font(Typeface.labelSmall)
                            .foregroundStyle(Room.tertiary)
                    }
                }
                content()
            }
            .padding(.top, Space.l)
            .padding(.bottom, Space.xl)
        }
    }

    func observabilityStatusLabel(_ status: CaptureObservabilityDimension.Status) -> String {
        switch status {
        case .pass: "Stabil"
        case .warn: "Prüfen"
        case .fail: "Nicht bereit"
        case .unavailable: "Nicht verfügbar"
        }
    }

    private var recordingControls: some View {
        instrumentSection("Kontinuierliche Aufnahme") {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(appStore.session.title)
                    .font(Typeface.heading)
                    .foregroundStyle(Room.primary)
                    .accessibilityIdentifier("live.recordingControls")
                Text("geplant \(appStore.session.plannedDurationMinutes) Min.")
                    .font(Typeface.valueSmall)
                    .foregroundStyle(Room.secondary)
            }
            readinessWarnings
            overrideControls
            auditPseudonym
            recordButtons
            captureRecoveryControls
        }
    }

    @ViewBuilder
    private var readinessWarnings: some View {
        if !readiness.blockers.isEmpty && !liveStore.isRecording {
            ForEach(readiness.blockers) { blocker in
                StatusMark(blocker.messageDE, kind: .fault)
            }
        }
        if liveStore.runtimeStatus.hasResourceWarning && !liveStore.isRecording {
            StatusMark(
                "Geräteressource warnt: Akku \(liveStore.runtimeStatus.batteryPercent.map { "\($0)%" } ?? "-"), Temperatur \(liveStore.runtimeStatus.thermalState)",
                kind: .attention
            )
        }
        if !liveStore.runtimeStatus.spokenAudioCheckCompleted && !liveStore.isRecording {
            StatusMark("Sprechprobe wurde noch nicht vollständig abgehört.", kind: .attention)
        }
    }

    @ViewBuilder
    private var overrideControls: some View {
        if !liveStore.isRecording && readiness.canOverrideQualityWarnings && requiresOverride {
            Toggle("Trotz technischer Warnungen aufnehmen", isOn: $forceRecord)
                .toggleStyle(InkCheckboxStyle())
                .accessibilityIdentifier("live.forceOverride")
            if forceRecord {
                LedgerField("Begründung") {
                    TextField("Begründung für Override", text: $overrideReason, axis: .vertical)
                        .lineLimit(2...4)
                        .writingLine()
                        .accessibilityIdentifier("live.overrideReason")
                }
            }
        }
    }

    private var auditPseudonym: some View {
        Group {
            LedgerField("Audit-Pseudonym") {
                TextField("Audit-Pseudonym", text: $operatorPseudonym)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .writingLine(mono: true)
                    .accessibilityIdentifier("live.operatorPseudonym")
            }
            Text("Das Pseudonym bezeichnet den Auditkontext; die Geräteauthentifizierung schützt den Zugriff und bestätigt keine reale Identität.")
                .font(Typeface.captionSmall)
                .foregroundStyle(Room.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let message = liveStore.recordStatusMessage {
                Text(message)
                    .font(Typeface.caption)
                    .foregroundStyle(Room.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("live.recordStatus")
            }
        }
    }

    private var recordButtons: some View {
        HStack(spacing: Space.m) {
            Button { beginRecording() } label: {
                Text(liveStore.isStartingRecording ? "Startet…" : (liveStore.isRecording ? "Läuft…" : "Start"))
            }
            .buttonStyle(RecordButtonStyle(isRecording: false, compact: true))
            .accessibilityIdentifier("live.start")
            .disabled(
                liveStore.isStartingRecording || liveStore.isPreparingRecording || liveStore.isRecording
                    || liveStore.isFinalizingRecording
                    || audioCheck.blocksCapture
                    || !readiness.canOverrideQualityWarnings || !overrideIsValid
            )

            Button { liveStore.stopRecording() } label: {
                Label("Stop", systemImage: "stop.circle")
            }
            .buttonStyle(InkButtonStyle(kind: .secondary))
            .accessibilityIdentifier("live.stop")
            .disabled((!liveStore.isStartingRecording && !liveStore.isRecording) || liveStore.isFinalizingRecording)
        }
    }

    @ViewBuilder
    private var captureRecoveryControls: some View {
        if let diagnostic = liveStore.artifactRecoveryDiagnostic {
            StatusMark(diagnostic, kind: .attention)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(diagnostic)
                .accessibilityIdentifier("live.artifactRecoveryDiagnostic")
        }
        if liveStore.canRetryCapture {
            Button("Kamera erneut versuchen") { liveStore.retryCapture() }
                .buttonStyle(InkButtonStyle(kind: .secondary))
                .accessibilityIdentifier("live.retry")
        }
        if liveStore.authorizationStatus == .denied || liveStore.authorizationStatus == .restricted
            || liveStore.microphoneAuthorizationStatus == .denied
            || liveStore.microphoneAuthorizationStatus == .restricted
        {
            Button("Berechtigungen in Einstellungen öffnen") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(InkButtonStyle(kind: .quiet))
        }
    }

    private var liveTips: some View {
        instrumentSection("Live-Hinweise") {
            let tips = filming.visibleTips
            if tips.isEmpty {
                Text(liveStore.isRecording ? "Keine kritischen technischen Hinweise." : "Analysiere Bild, Lage und Audio…")
                    .font(Typeface.callout)
                    .foregroundStyle(Room.secondary)
            } else {
                ForEach(tips) { PrioritizedTipRow(item: $0, isRecording: liveStore.isRecording) }
            }
        }
    }

    private var audioControls: some View {
        instrumentSection("Audio") {
            Text(filming.audio.message)
                .font(Typeface.body)
                .foregroundStyle(Room.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(filming.audio.actionHint)
                .font(Typeface.callout.weight(.semibold))
                .foregroundStyle(Room.human)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Space.s) {
                metricRow("Peak", liveStore.audioSample.peakLevel)
                metricRow("Mittel", liveStore.audioSample.averageLevel)
                if let value = liveStore.audioSample.clippingFraction { metricRow("PCM-Vollaussteuerung", value) }
                instrumentRow("Kanäle", liveStore.audioSample.channelCount.map(String.init) ?? "nicht verfügbar")
                instrumentRow("Samplerate", liveStore.audioSample.sampleRate.map { String(format: "%.0f Hz", $0) } ?? "nicht verfügbar")
                if let value = liveStore.audioSample.baselineLevelEstimate { metricRow("Niedrigstes Fenstermittel", value) }
                instrumentRow("Zeitstempel-Lücke", liveStore.audioSample.dropoutDetected ? "erkannt" : "nicht erkannt")
                instrumentRow("Route", liveStore.runtimeStatus.audioRoute)
            }
            Text("Der Pegeltest misst Amplitude, PCM-Vollaussteuerung und Zeitstempelkontinuität. Er misst weder True Peak nach ITU-R BS.1770 noch Sprachverständlichkeit. Vor Ort eine Hörprobe durchführen.")
                .font(Typeface.captionSmall)
                .foregroundStyle(Room.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            spokenAudioControls
        }
    }

    @ViewBuilder
    private var spokenAudioControls: some View {
        if !liveStore.isRecording && !liveStore.isStartingRecording && !liveStore.isFinalizingRecording {
            Button {
                guard let authorization = SpokenAudioCheckAuthorization.make(
                    for: appStore.session,
                    covering: SpokenAudioCheckModel.authorizationWindow
                ) else { return }
                audioCheck.start(
                    authorization: authorization,
                    currentSession: { appStore.session },
                    pauseCapture: { liveStore.stop() },
                    resumeCapture: { liveStore.start() },
                    playbackCompleted: { liveStore.markSpokenAudioCheckCompleted() }
                )
            } label: {
                Label("4-Sekunden-Sprechprobe aufnehmen", systemImage: "mic.badge.plus")
            }
            .buttonStyle(InkButtonStyle(kind: .secondary))
            .disabled(
                audioCheck.blocksCapture
                    || SpokenAudioCheckAuthorization.make(
                        for: appStore.session,
                        covering: SpokenAudioCheckModel.authorizationWindow
                    ) == nil
            )
            .accessibilityIdentifier("live.audioCheck.record")
            if audioCheck.canPlay {
                Button { audioCheck.play() } label: {
                    Label("Sprechprobe abhören", systemImage: "play.circle")
                }
                .buttonStyle(InkButtonStyle(kind: .secondary))
                .accessibilityIdentifier("live.audioCheck.play")
            }
            if audioCheck.canCancel {
                Button("Sprechprobe abbrechen", role: .cancel) { audioCheck.cancel(resumeCapture: true) }
                    .buttonStyle(InkButtonStyle(kind: .quiet))
            }
            Label(audioCheck.statusText, systemImage: audioCheck.statusIcon)
                .font(Typeface.caption.weight(.medium))
                .foregroundStyle(audioCheck.playbackCompleted ? Room.secured : Room.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("live.audioCheck.status")
        }
    }

    private var deviceAndFormat: some View {
        instrumentSection("Gerät & Format") {
            VStack(alignment: .leading, spacing: Space.s) {
                instrumentRow("Video", liveStore.runtimeStatus.videoConfiguration)
                instrumentRow("Akku", liveStore.runtimeStatus.batteryPercent.map { "\($0)%" } ?? "nicht verfügbar")
                instrumentRow("Temperatur", liveStore.runtimeStatus.thermalState)
                instrumentRow("Freier Speicher", liveStore.runtimeStatus.availableCapacityBytes.map(formatCapacity) ?? "nicht verfügbar")
            }
            Text("Die geplante Dauer beendet die Aufnahme nicht. Automatisch finalisiert wird sie, wenn der freie Speicher unter die Sicherheitsreserve fällt, die Freigabe abläuft oder widerrufen wird, die Aufnahme unterbrochen wird oder die Hintergrundzeit endet.")
                .font(Typeface.captionSmall)
                .foregroundStyle(Room.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var experimentalHypotheses: some View {
        if appStore.session.operatingMode == .experimentalResearch,
           appStore.session.hasUsableExperimentalProtocol
        {
            instrumentSection("Experimentelle Regelhypothesen") {
                HypothesisBlock {
                    Text(liveStore.experimentalResult?.hypotheses.limitationDE ?? "Experimentelle Regeln werden erst nach einem aktuellen Aufnahmesignal ausgewertet.")
                        .font(Typeface.caption)
                        .foregroundStyle(Room.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(liveStore.experimentalResult?.hypotheses.hypotheses.prefix(12) ?? []) { hypothesis in
                        LabeledContent {
                            Text(String(format: "Regelaktivierung %.0f %%", hypothesis.ruleSupport * 100))
                                .font(Typeface.valueSmall)
                                .monospacedDigit()
                                .foregroundStyle(Room.hypothesis)
                        } label: {
                            Text(hypothesis.labelDE)
                                .font(Typeface.callout)
                                .foregroundStyle(Room.primary)
                        }
                    }
                }
            }
            .accessibilityIdentifier("live.experimentalHypotheses")
        }
    }
}
