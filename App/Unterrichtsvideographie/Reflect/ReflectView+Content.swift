import AVKit
import ExperimentalResearch
import Foundation
import SessionCore
import SwiftUI

extension ReflectView {
    // MARK: - Studio columns

    var playerColumn: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            interruptedTakeNotice
            mediaEvidenceStudio
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func lafColumn(index: ReflectionAnnotationIndex) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Vier Fragen strukturieren die eigene Analyse. Sie erzeugen keine automatische Bewertung.")
                .font(Typeface.caption)
                .foregroundStyle(Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                Rule()
                ForEach(Array(ReflectionPromptID.allCases.enumerated()), id: \.element.id) { number, prompt in
                    Button {
                        focusedPrompt = prompt
                    } label: {
                        lafRow(prompt, number: number + 1, index: index)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(focusedPrompt == prompt ? .isSelected : [])
                    Rule()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func notesColumn(index: ReflectionAnnotationIndex) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Eigene Beobachtung")
                    .font(Typeface.section)
                    .foregroundStyle(Ink.primary)
                    .accessibilityAddTraits(.isHeader)
                FormLabel("menschlich verfasst", small: true)
            }

            LedgerField("Reflexionsfokus") {
                LedgerMenuPicker(
                    title: "Reflexionsfokus",
                    selection: $focusedPrompt,
                    options: ReflectionPromptID.allCases.map { ($0, $0.titleDE) },
                    accessibilityID: "reflect.promptPicker"
                )
                Text(focusedPrompt.promptDE)
                    .font(Typeface.quote)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.s)
            }

            LedgerField("Autor-Pseudonym") {
                TextField("Autor-Pseudonym", text: $annotationAuthor)
                    .textInputAutocapitalization(.characters)
                    .submitLabel(.next)
                    .onSubmit { annotationFocus = .note }
                    .writingLine(mono: true)
                    .focused($annotationFocus, equals: .author)
                    .accessibilityIdentifier("reflect.annotationAuthor")
            }

            LedgerField("Beobachtung") {
                TextField("Beobachtungsnotiz", text: binding(for: focusedPrompt), axis: .vertical)
                    .lineLimit(4...8)
                    .submitLabel(.done)
                    .onSubmit { annotationFocus = nil }
                    .writingLine()
                    .focused($annotationFocus, equals: .note)
                    .accessibilityIdentifier("reflect.\(focusedPrompt.rawValue)")
            }

            VStack(alignment: .leading, spacing: Space.s) {
                if let annotationEditorMessage {
                    StatusMark(
                        annotationEditorMessage,
                        kind: annotationEditorMessage.hasPrefix("Notiz lokal gesichert") ? .secured : .fault
                    )
                    .accessibilityIdentifier("reflect.annotationSaveState")
                }

                if case .failed(let failure) = appStore.saveState {
                    StatusMark("Lokale Speicherung fehlgeschlagen: \(failure)", kind: .fault)
                } else {
                    SaveStateMark(state: appStore.saveState)
                        .accessibilityIdentifier("reflect.persistenceState")
                }
            }

            noteActions

            VStack(alignment: .leading, spacing: Space.xs) {
                FormLabel("Medienbelege zu dieser Frage")
                reflectEvidenceSummary(for: focusedPrompt, index: index)
            }

            DisclosureGroup("Schnelle Verknüpfung") {
                reflectPromptEvidenceControls(for: focusedPrompt)
            }
            .disclosureGroupStyle(InkDisclosureStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var annotationIntervalFields: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            FormLabel("Ausgewählter Zeitbereich")
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Space.xl) {
                    annotationTimeField("Von", text: $annotationStartTimecode, focus: .start, identifier: "reflect.annotationStart")
                    annotationTimeField("Bis", text: $annotationEndTimecode, focus: .end, identifier: "reflect.annotationEnd")
                }
                VStack(alignment: .leading, spacing: Space.l) {
                    annotationTimeField("Von", text: $annotationStartTimecode, focus: .start, identifier: "reflect.annotationStart")
                    annotationTimeField("Bis", text: $annotationEndTimecode, focus: .end, identifier: "reflect.annotationEnd")
                }
            }
            Text("MM:SS · Die Notiz wird mit diesem Bereich verknüpft.")
                .font(Typeface.captionSmall)
                .foregroundStyle(Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if ReflectionAnnotationTimecode.parse(annotationStartTimecode) == .success(0),
               ReflectionAnnotationTimecode.parse(annotationEndTimecode) == .success(0) {
                Text("00:00 bis 00:00 bezeichnet das gesamte Video.")
                    .font(Typeface.captionSmall)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noteActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.m) {
                saveAnnotationButton
                metadataReviewLink
            }
            VStack(alignment: .leading, spacing: Space.s) {
                saveAnnotationButton
                metadataReviewLink
            }
        }
    }

    private var metadataReviewLink: some View {
        NavigationLink {
            metadataReview
        } label: {
            Label("Metadaten prüfen", systemImage: "doc.text.magnifyingglass")
        }
        .buttonStyle(InkButtonStyle(kind: .secondary))
        .accessibilityIdentifier("reflect.metadataReview")
    }

    private var annotationIntervalActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.m) {
                currentPositionButton
                wholeVideoButton
            }
            VStack(alignment: .leading, spacing: Space.s) {
                currentPositionButton
                wholeVideoButton
            }
        }
    }

    private var saveAnnotationButton: some View {
        Button(isSavingAnnotation ? "Notiz wird gesichert…" : "Notiz sichern") {
            saveHumanAnnotation()
        }
        .buttonStyle(InkButtonStyle(kind: .primary))
        .disabled(isSavingAnnotation || !hasPlayableSelectedMedia)
        .accessibilityIdentifier("reflect.annotationSave")
    }

    private var currentPositionButton: some View {
        Button("Aktuelle Position") {
            usePlaybackPositionForAnnotationInterval()
        }
        .buttonStyle(InkButtonStyle(kind: .secondary))
        .accessibilityLabel("Aktuelle Wiedergabeposition für den Zeitbereich übernehmen")
    }

    private var wholeVideoButton: some View {
        Button("Ganzes Video") {
            useWholeVideoForAnnotationInterval()
        }
        .buttonStyle(InkButtonStyle(kind: .secondary))
        .accessibilityLabel("Gesamtes Video für den Zeitbereich übernehmen")
    }

    private func annotationTimeField(
        _ label: String,
        text: Binding<String>,
        focus: ReflectionAnnotationField,
        identifier: String
    ) -> some View {
        LedgerField(label) {
            TextField("00:00", text: text)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .submitLabel(focus == .start ? .next : .done)
                .onSubmit { annotationFocus = focus == .start ? .end : nil }
                .focused($annotationFocus, equals: focus)
                .accessibilityLabel("\(label), Minuten und Sekunden")
                .accessibilityIdentifier(identifier)
                .writingLine(mono: true)
        }
    }

    private func lafRow(_ prompt: ReflectionPromptID, number: Int, index: ReflectionAnnotationIndex) -> some View {
        let filled = !appStore.session.reflection[prompt].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let linked = !index.annotations(for: prompt).isEmpty
        let active = focusedPrompt == prompt

        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            MarginMark(text: String(format: "%02d", number), emphasized: active)
                .frame(width: Space.marginCompact, alignment: .leading)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(prompt.titleDE)
                    .font(Typeface.heading)
                    .foregroundStyle(Ink.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(prompt.visionFacetDE)
                    .font(Typeface.captionSmall)
                    .foregroundStyle(Ink.tertiary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.m) {
                    StatusMark("Notiz", kind: filled ? .secured : .open)
                    StatusMark("Beleg", kind: linked ? .secured : .open)
                }
                .padding(.top, Space.xxs)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.m)
        .padding(.leading, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? Ink.humanWash : Color.clear)
        .overlay(alignment: .leading) {
            if active {
                Rectangle().fill(Ink.human).frame(width: 2)
            }
        }
        .contentShape(Rectangle())
    }

    var mediaEvidenceStudio: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if appStore.session.mediaAssets.isEmpty {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text("Noch keine Aufnahme verknüpft")
                        .font(Typeface.section)
                        .foregroundStyle(Ink.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Nehmen Sie im Bereich 02 Aufnahme auf oder importieren Sie eine lokale MP4-Datei. Zu jeder der vier Fragen gehört mindestens ein Medienbeleg.")
                        .font(Typeface.prose)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: Space.measure, alignment: .leading)
                    mediaImportControl
                }
                .padding(.vertical, Space.l)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: Space.l) {
                        mediaPicker
                        mediaImportControl
                    }
                    VStack(alignment: .leading, spacing: Space.s) {
                        mediaPicker
                        mediaImportControl
                    }
                }

                if let selectedAsset {
                    if hasPlayableSelectedMedia, let player = playback.player {
                        videoPlayer(player, asset: selectedAsset)
                        ReflectionPlaybackControls(
                            playback: playback,
                            durationMilliseconds: selectedAsset.durationMilliseconds,
                            rangeStartMilliseconds: $rangeStartMilliseconds
                        )
                        gaussianExplorationControl
                        Rule()
                        annotationIntervalFields
                        annotationIntervalActions
                    } else if isCheckingMedia {
                        ProgressView {
                            Text("Videodatei wird geprüft…")
                                .font(Typeface.caption)
                                .foregroundStyle(Ink.tertiary)
                        }
                    } else {
                        StatusMark("Die verknüpfte Videodatei fehlt oder kann nicht geöffnet werden.", kind: .attention, prominent: true)
                            .accessibilityLabel("Videodatei fehlt oder ist beschädigt")
                    }
                }
            }
        }
    }

    private var mediaPicker: some View {
        LedgerField("Medium") {
            LedgerMenuPicker(
                title: "Medium",
                selection: Binding(
                    get: { selectedAsset?.id },
                    set: { selectedAssetID = $0 }
                ),
                options: appStore.session.mediaAssets.map { (Optional($0.id), assetLabel($0)) },
                accessibilityID: "reflect.mediaPicker",
                mono: true
            )
        }
    }

    @ViewBuilder
    private var gaussianExplorationControl: some View {
        if appStore.session.operatingMode == .experimentalResearch {
            if GaussianExplorationPolicy.permits(appStore.session) {
                Button {
                    gaussianLaunchMessage = nil
                    playback.player?.pause()
                    gaussianLaunchID = UUID()
                } label: {
                    Label(gaussianLaunchID == nil ? "Standbild-Perspektive erkunden · Experiment" : "Freigaben werden gesichert…", systemImage: "viewfinder")
                }
                .buttonStyle(InkButtonStyle(kind: .secondary))
                .disabled(gaussianLaunchID != nil || playback.isSeeking)
                .accessibilityIdentifier("reflect.gaussian.open")
                if let gaussianLaunchMessage {
                    StatusMark(gaussianLaunchMessage, kind: .attention)
                }
            } else {
                Text("Perspektivexperimente benötigen ein aktuelles Forschungsprotokoll sowie Freigaben für Forschung und lokale Reflexion.")
                    .font(Typeface.caption)
                    .foregroundStyle(Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @MainActor
    func beginGaussianExploration(token: UUID) async {
        guard let asset = selectedAsset, let url = selectedMediaURL else {
            gaussianLaunchID = nil
            return
        }
        let selection = GaussianLaunchPreparation.Selection(session: appStore.session, assetID: asset.id, mediaURL: url)
        let player = playback.player
        let initialTime = player?.currentTime()
        let seekRevision = playback.seekRevision
        defer { if gaussianLaunchID == token { gaussianLaunchID = nil } }
        do {
            let request = try await GaussianLaunchPreparation.prepare(
                selection: selection,
                persist: { await appStore.flushPendingChanges() },
                currentSelection: {
                    guard gaussianLaunchID == token, scenePhase == .active, isReflectionSelected(),
                          playback.player === player, playback.seekRevision == seekRevision,
                          let initialTime, playback.matchesPausedFrame(url: url, time: initialTime),
                          let currentAsset = selectedAsset, let currentURL = selectedMediaURL else { return nil }
                    return .init(session: appStore.session, assetID: currentAsset.id, mediaURL: currentURL)
                },
                freeze: { playback.pauseForGaussianExploration() }
            )
            guard !Task.isCancelled, gaussianLaunchID == token else { return }
            gaussianRequest = request
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, gaussianLaunchID == token else { return }
            gaussianLaunchMessage = (error as? GaussianFrameError)?.errorDescription
                ?? "Die Perspektivansicht konnte nicht vorbereitet werden."
        }
    }

    @ViewBuilder
    private var mediaImportControl: some View {
        if appStore.session.authorizes(.localReflection) {
            Button { isImportingMedia = true } label: {
                Label(isProcessingMediaImport ? "Video wird importiert…" : "Video importieren",
                      systemImage: isProcessingMediaImport ? "hourglass" : "square.and.arrow.down")
            }
            .buttonStyle(InkButtonStyle(kind: .quiet))
            .disabled(isProcessingMediaImport)
            .accessibilityIdentifier("reflect.importMedia")
        } else {
            StatusMark("Videoimport erfordert eine aktive Freigabe für lokale Reflexion.", kind: .open)
        }
    }

    private func videoPlayer(_ player: AVPlayer, asset: SessionMediaAsset) -> some View {
        GeometryReader { proxy in
            VideoPlayer(player: player)
                .frame(width: proxy.size.width, height: proxy.size.width * 9 / 16)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(Rectangle())
        .overlay {
            Rectangle().strokeBorder(Ink.rule, lineWidth: 1)
        }
        .accessibilityLabel("Videowiedergabe für \(assetLabel(asset))")
    }

    @ViewBuilder
    var experimentalHypotheses: some View {
        if appStore.session.operatingMode == .experimentalResearch,
           appStore.session.hasUsableExperimentalProtocol,
           let snapshot = appStore.session.latestCodingSnapshot
        {
            HypothesisBlock(title: "Experimentelle Hypothese · nicht validiert") {
                Text(snapshot.summaryDE)
                    .font(Typeface.caption)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let report = appStore.session.researchCaptureReport(
                    generatorProvenance: BuildProvenanceFactory.export
                ) {
                    Text(report.summaryDE)
                        .font(Typeface.captionSmall)
                        .foregroundStyle(Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let scaffold = appStore.session.reflectionScaffoldNotes()[focusedPrompt.rawValue] {
                    Text(scaffold)
                        .font(Typeface.captionSmall)
                        .foregroundStyle(Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Keine pädagogische Bewertung, keine Konfidenzangabe und kein Ersatz für menschliche Kodierung.")
                    .font(Typeface.captionSmall)
                    .foregroundStyle(Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityLabel("Experimentelle, nicht validierte Hypothese")
        }
    }

    @ViewBuilder
    func reflectPromptEvidenceControls(for prompt: ReflectionPromptID) -> some View {
        if selectedAsset == nil {
            Text("Für diesen Schritt ist noch kein Medium verfügbar.")
                .font(Typeface.caption)
                .foregroundStyle(Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        } else if hasPlayableSelectedMedia {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.m) {
                    Button("Aktuelle Position verknüpfen") { addAnnotation(for: prompt, wholeAsset: false) }
                        .buttonStyle(InkButtonStyle(kind: .secondary))
                    Button("Ganzes Video verknüpfen") { addAnnotation(for: prompt, wholeAsset: true) }
                        .buttonStyle(InkButtonStyle(kind: .secondary))
                }
                VStack(alignment: .leading, spacing: Space.s) {
                    Button("Aktuelle Position verknüpfen") { addAnnotation(for: prompt, wholeAsset: false) }
                        .buttonStyle(InkButtonStyle(kind: .secondary))
                    Button("Ganzes Video verknüpfen") { addAnnotation(for: prompt, wholeAsset: true) }
                        .buttonStyle(InkButtonStyle(kind: .secondary))
                }
            }
            .disabled(isSavingAnnotation)
        }
    }

    /// Linked evidence reads like a transcript: the timecode sits in the margin.
    @ViewBuilder
    func reflectEvidenceSummary(for prompt: ReflectionPromptID, index: ReflectionAnnotationIndex) -> some View {
        let annotations = index.annotations(for: prompt)
        if annotations.isEmpty {
            StatusMark("Noch kein Medienbeleg", kind: .open)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Rule()
                ForEach(annotations, id: \.id) { annotation in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        MarginMark(text: annotationLabel(annotation))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 96, alignment: .leading)
                        Image(systemName: "link")
                            .font(.footnote)
                            .foregroundStyle(Ink.tertiary)
                            .accessibilityHidden(true)
                        Spacer(minLength: Space.s)
                        Button("Entfernen", role: .destructive) {
                            appStore.removeAnnotation(id: annotation.id)
                        }
                        .font(Typeface.callout.weight(.semibold))
                        .foregroundStyle(Ink.fault)
                        .frame(minHeight: Space.target)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Medienbeleg entfernen")
                    }
                    Rule()
                }
            }
        }
    }

    @ViewBuilder
    func reflectProgress(index: ReflectionAnnotationIndex) -> some View {
        let filled = appStore.session.reflection.filledCount
        let linked = index.linkedPromptCount
        let complete = reflectionIsComplete(index: index)
        VStack(alignment: .leading, spacing: Space.m) {
            Text("\(filled) / 4 Antworten · \(linked) / 4 belegt")
                .font(Typeface.value)
                .foregroundStyle(Ink.instrument)
                .monospacedDigit()
            HStack(spacing: Space.xs) {
                ForEach(ReflectionPromptID.allCases) { prompt in
                    let isFilled = !appStore.session.reflection[prompt]
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ZStack {
                        Rectangle().fill(isFilled ? Ink.human : Color.clear)
                        Rectangle().strokeBorder(isFilled ? Ink.human : Ink.ruleStrong, lineWidth: 1)
                    }
                    .frame(width: 12, height: 12)
                }
            }
            .accessibilityHidden(true)
            StatusMark(
                complete ? "Reflexion vollständig" : "Vollständig nach vier Antworten und je einem Medienbeleg",
                kind: complete ? .secured : .open
            )
            Button("Entwurf speichern") {
                appStore.save()
            }
            .buttonStyle(InkButtonStyle(kind: .secondary))
            .accessibilityIdentifier("reflect.save")
            .padding(.top, Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Interrupted takes

extension ReflectView {
    /// A take cut off by app termination is kept until the operator verifies or discards it.
    @ViewBuilder
    var interruptedTakeNotice: some View {
        if !interruptedTakeIDs.isEmpty || interruptedTakeMessage != nil {
            VStack(alignment: .leading, spacing: Space.s) {
                if !interruptedTakeIDs.isEmpty {
                    StatusMark("Unterbrochene Aufnahme aufbewahrt, noch nicht geprüft", kind: .attention)
                    Text("Die App wurde während einer Aufnahme beendet. Die Datei wurde nicht gelöscht. Prüfen und übernehmen Sie sie als Take, oder verwerfen Sie sie ausdrücklich. Bis dahin ist in dieser Sitzung keine neue Aufnahme möglich.")
                        .font(Typeface.caption)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(interruptedTakeIDs, id: \.self) { transactionID in
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: Space.m) { interruptedTakeActions(for: transactionID) }
                            VStack(alignment: .leading, spacing: Space.s) { interruptedTakeActions(for: transactionID) }
                        }
                        .disabled(isResolvingInterruptedTake)
                    }
                }
                if let interruptedTakeMessage {
                    Text(interruptedTakeMessage)
                        .font(Typeface.caption)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("reflect.interruptedTake.message")
                }
            }
            .confirmationDialog(
                "Unterbrochene Aufnahme endgültig verwerfen?",
                isPresented: Binding(
                    get: { interruptedTakePendingDiscard != nil },
                    set: { if !$0 { interruptedTakePendingDiscard = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Endgültig verwerfen", role: .destructive) {
                    if let transactionID = interruptedTakePendingDiscard {
                        resolveInterruptedTake(transactionID, discard: true)
                    }
                }
            } message: {
                Text("Die Datei wird gelöscht. Das lässt sich nicht rückgängig machen.")
            }
        }
    }

    @ViewBuilder
    private func interruptedTakeActions(for transactionID: UUID) -> some View {
        Button("Prüfen und übernehmen") { resolveInterruptedTake(transactionID, discard: false) }
            .buttonStyle(InkButtonStyle(kind: .primary))
            .accessibilityIdentifier("reflect.interruptedTake.recover")
        Button("Verwerfen…", role: .destructive) { interruptedTakePendingDiscard = transactionID }
            .buttonStyle(InkButtonStyle(kind: .destructive))
            .accessibilityIdentifier("reflect.interruptedTake.discard")
    }

    private func resolveInterruptedTake(_ transactionID: UUID, discard: Bool) {
        isResolvingInterruptedTake = true
        interruptedTakeMessage = nil
        Task { @MainActor in
            interruptedTakeMessage = discard
                ? await appStore.discardInterruptedTake(transactionID)
                : await appStore.recoverInterruptedTake(transactionID)
            interruptedTakeIDs = await appStore.pendingInterruptedTakeIDs()
            isResolvingInterruptedTake = false
        }
    }
}
