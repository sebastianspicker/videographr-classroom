import SessionCore
import SwiftUI
import UIKit

extension ReflectView {
    var metadataReview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                metadataReviewHeader
                VStack(alignment: .leading, spacing: 0) {
                    ProtocolSection("1", "Inhalt") {
                        exportContents
                    }
                    ProtocolSection("2", "Erforderliche Freigaben") {
                        exportScopes
                    }
                    ProtocolSection("3", "Weitergabe") {
                        export
                        if let error = appStore.lastStoreError {
                            StatusMark(error, kind: .fault, prominent: true)
                                .accessibilityIdentifier("reflect.exportError")
                        }
                        exportOutcome
                    }
                    metadataGrantGuidance
                }
            }
            .padding(.horizontal, pageGutter)
            .padding(.top, Space.xl)
            .padding(.bottom, Space.xxl)
            .frame(maxWidth: Space.pageMaximum, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .paperSurface()
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("reflect.metadataReviewScreen")
    }

    private var metadataReviewHeader: some View {
        DocumentHeader(
            eyebrow: "Metadaten weitergeben",
            title: "Paket prüfen",
            summary: "Umfang und Freigaben vor der Systemauswahl prüfen."
        ) {
            if appStore.session.canExportExternally {
                StatusMark("Bereit", kind: .secured)
            } else {
                StatusMark("Freigaben prüfen", kind: .attention)
            }
        }
    }

    @ViewBuilder
    var export: some View {
        if appStore.session.canExportExternally {
            VStack(alignment: .leading, spacing: Space.s) {
                Button {
                    isPreparingExport = true
                    Task {
                        defer { isPreparingExport = false }
                        guard let prepared = await appStore.prepareExportForSharing() else { return }
                        pendingExportOutcome = prepared
                        exportOutcomeCoordinator = ExportOutcomeCoordinator(exportID: prepared.id)
                        preparedExport = prepared
                    }
                } label: {
                    Label(
                        isPreparingExport ? "Paket wird vorbereitet…" : "Paket erstellen und weitergeben",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .buttonStyle(InkButtonStyle(kind: .primary))
                .disabled(isPreparingExport)
                .accessibilityLabel("Metadatenpaket exportieren")

                Text("Öffnet nach erfolgreicher Vorbereitung die Systemauswahl. Abschluss durch das System ist kein Zustell- oder Lesebeleg.")
                    .font(Typeface.captionSmall)
                    .foregroundStyle(Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("Die erforderlichen Freigaben sind nicht aktiv. Sekundärnutzung und externe Weitergabe werden nicht aus der Erhebungsfreigabe abgeleitet.")
                .font(Typeface.proseSmall)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: Space.measure, alignment: .leading)
        }
    }

    private var metadataGrantGuidance: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Rule()
            Text("Freigaben bleiben sitzungsbezogen")
                .font(Typeface.heading)
                .foregroundStyle(Ink.primary)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Space.l)
            Text("Erhebungsfreigabe erweitert sich nicht automatisch auf Sekundärnutzung oder externe Weitergabe.")
                .font(Typeface.proseSmall)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: Space.measure, alignment: .leading)
            Button("Freigaben in der Sitzung bearbeiten") {
                onEditSession()
            }
            .buttonStyle(InkButtonStyle(kind: .secondary))
            .accessibilityIdentifier("reflect.editSessionGrants")
            .padding(.top, Space.xs)
        }
    }

    private static let packageFiles: [(name: String, description: String)] = [
        ("session.json", "Sitzungskontext und Freigabemetadaten"),
        ("annotations.jsonl", "Menschliche Notizen und Zeitbereiche"),
        ("observations.jsonl", "Technische Beobachtungen"),
        ("coding-snapshots.jsonl", "Kodierungsschnappschüsse und Herkunft"),
        ("manifest.json", "Prüfsummen und Herkunft")
    ]

    private var exportContents: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.packageFiles, id: \.name) { file in
                packageLine(file.name, file.description)
            }
            Label {
                Text("Nicht enthalten: Videodatei")
                    .font(Typeface.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "video.slash")
            }
            .foregroundStyle(Ink.primary)
            .padding(.vertical, Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rule(strong: true) }
            Text("Metadaten sind nicht anonym und können Personenbezug haben. Das Paket enthält keine lokale oder importierte Videodatei.")
                .font(Typeface.proseSmall)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: Space.measure, alignment: .leading)
                .padding(.top, Space.m)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exportScopes: some View {
        let required = StudyExportProjection.requiredScopes(for: appStore.session)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(ConsentScope.allCases, id: \.self) { scope in
                if required.contains(scope) {
                    exportScopeRow(scope)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func exportScopeRow(_ scope: ConsentScope) -> some View {
        let documented = appStore.session.authorizes(scope)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                Text(exportScopeTitle(scope))
                    .font(Typeface.body)
                    .foregroundStyle(Ink.primary)
                Spacer(minLength: Space.m)
                exportScopeMark(documented)
            }
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(exportScopeTitle(scope))
                    .font(Typeface.body)
                    .foregroundStyle(Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                exportScopeMark(documented)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Space.s + 2)
        .overlay(alignment: .bottom) { Rule() }
        .accessibilityElement(children: .combine)
    }

    private func exportScopeMark(_ documented: Bool) -> some View {
        documented
            ? StatusMark("dokumentiert", kind: .secured)
            : StatusMark("fehlt", kind: .attention)
    }

    @ViewBuilder
    var exportOutcome: some View {
        if let event = appStore.session.exportEvents.max(by: { $0.exportedAt < $1.exportedAt }) {
            let presentation = exportOutcomePresentation(for: event)
            VStack(alignment: .leading, spacing: Space.s) {
                StatusMark(presentation.title, kind: presentation.kind, prominent: true)
                Text(presentation.detail)
                    .font(Typeface.proseSmall)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: Space.measure, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    FactRow(key: "Paket", value: "Metadaten ohne Video")
                    FactRow(key: "Exportvorgang", value: event.status.rawValue, mono: true)
                    FactRow(
                        key: "Protokolliert",
                        value: event.exportedAt.formatted(date: .abbreviated, time: .shortened),
                        mono: true
                    )
                }
                if let failure = event.failureDescription, !failure.isEmpty {
                    Text(failure)
                        .font(Typeface.captionSmall)
                        .foregroundStyle(Ink.fault)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if event.status == .completed {
                    Text("Externe Kopien können durch die App nicht zurückgerufen werden.")
                        .font(Typeface.captionSmall)
                        .foregroundStyle(Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("reflect.exportOutcome")
        }
    }

    private func exportScopeTitle(_ scope: ConsentScope) -> String {
        switch scope {
        case .collection: return "Erhebung"
        case .localReflection: return "Lokale Reflexion"
        case .researchProcessing: return "Forschungsverarbeitung"
        case .secondaryUse: return "Sekundärnutzung"
        case .externalSharing: return "Externe Weitergabe"
        }
    }

    private func exportOutcomePresentation(for event: ExportEvent) -> (title: String, detail: String, kind: StatusMark.Kind) {
        switch event.status {
        case .completed:
            return (
                "Weitergabe vom System bestätigt",
                "Das System meldet den Vorgang als abgeschlossen. Dies ist kein Nachweis, dass die Datei zugestellt oder gelesen wurde.",
                .secured
            )
        case .attempted:
            return (
                "Weitergabe wird noch eingeordnet",
                "Der vorbereitete Vorgang ist lokal protokolliert. Ein bestätigter Abschluss liegt noch nicht vor.",
                .attention
            )
        case .cancelled:
            return ("Weitergabe abgebrochen", "Die Systemauswahl wurde ohne bestätigten Abschluss beendet.", .neutral)
        case .failed:
            return ("Weitergabe fehlgeschlagen", "Der Fehler ist im lokalen Exportvorgang vermerkt.", .fault)
        case .outcomeUnknown:
            return ("Ausgang der Weitergabe unbekannt", "Der Vorgang bleibt lokal als ungeklärt protokolliert.", .attention)
        }
    }

    private func packageLine(_ name: String, _ description: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                Text(name)
                    .font(Typeface.value)
                    .foregroundStyle(Ink.instrument)
                    .frame(width: 220, alignment: .leading)
                Text(description)
                    .font(Typeface.callout)
                    .foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(name)
                    .font(Typeface.value)
                    .foregroundStyle(Ink.instrument)
                Text(description)
                    .font(Typeface.callout)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Space.s + 2)
        .overlay(alignment: .bottom) { Rule() }
        .accessibilityElement(children: .combine)
    }

    func recordCancelledExportIfNeeded() {
        guard let pending = pendingExportOutcome,
              let coordinator = exportOutcomeCoordinator,
              coordinator.exportID == pending.id
        else { return }
        coordinator.recordDismissal()
        Task { @MainActor in
            await Task.yield()
            guard let outcome = coordinator.dismissalFallbackIfNeeded() else { return }
            submitExportOutcome(outcome, for: pending, coordinator: coordinator)
        }
    }

    func recordActivityExportOutcome(
        _ prepared: AppStore.PreparedExport,
        completed: Bool,
        shareActivityIdentifier: String?,
        failureDescription: String?
    ) {
        guard let coordinator = exportOutcomeCoordinator,
              coordinator.exportID == prepared.id,
              let outcome = coordinator.recordActivityCompletion(
                  completed: completed,
                  shareActivityIdentifier: shareActivityIdentifier,
                  failureDescription: failureDescription
              )
        else { return }
        submitExportOutcome(outcome, for: prepared, coordinator: coordinator)
        preparedExport = nil
    }

    func submitExportOutcome(
        _ outcome: ExportOutcomeCoordinator.Outcome,
        for prepared: AppStore.PreparedExport,
        coordinator: ExportOutcomeCoordinator
    ) {
        Task { @MainActor in
            await appStore.recordExportOutcome(
                prepared,
                completed: outcome.completed,
                shareActivityIdentifier: outcome.shareActivityIdentifier,
                failureDescription: outcome.failureDescription
            )
            guard exportOutcomeCoordinator === coordinator else { return }
            pendingExportOutcome = nil
            exportOutcomeCoordinator = nil
        }
    }
}

struct SystemShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let completion: @MainActor (Bool, String?, String?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { activityType, completed, _, error in
            Task { @MainActor in
                completion(completed, activityType?.rawValue, error?.localizedDescription)
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
