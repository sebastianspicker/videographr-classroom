import GuidanceEngine
import SwiftUI

/// In-app product identity, epistemic boundary, and technical footprint.
struct AboutView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    DocumentHeader(
                        eyebrow: "05 · Wissenschaftliche Alpha",
                        title: "Über Videographr",
                        summary: "Lokale Software für kontinuierliche Videoaufnahme und evidenzverknüpfte Reflexion in der Lehrkräftebildung."
                    ) {
                        StatusMark("Alpha", kind: .neutral)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        productSection
                        normalModeSection
                        experimentalSection
                        dataPathSection
                        evidenceSection
                        documentationSection
                        scopeSection
                        platformSection
                        Rule()
                    }
                }
                .padding(.horizontal, sizeClass == .regular ? Space.gutterRegular : Space.gutterCompact)
                .padding(.top, Space.xl)
                .padding(.bottom, Space.xxxl)
                .frame(maxWidth: Space.measure, alignment: .leading)
                .frame(maxWidth: Space.pageMaximum, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .paperSurface()
        }
    }

    // MARK: Sections

    private var productSection: some View {
        ProtocolSection("1", "Produkt") {
            VStack(alignment: .leading, spacing: Space.m) {
                VStack(spacing: 0) {
                    FactRow(key: "Produkt", value: "Videographr")
                    FactRow(key: "Version", value: BuildIdentity.current.displayVersion, mono: true)
                    FactRow(key: "Domäne", value: "Unterrichtsvideographie")
                }
                Text("Lokale Alpha-Software für kontinuierliche Videoaufnahme und evidenzverknüpfte Reflexion in der Lehrkräftebildung. Kein validiertes Kodierinstrument, kein Wirksamkeitsnachweis und kein Video-Portal.")
                    .font(Typeface.prose)
                    .foregroundStyle(Ink.primary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("info.content")
            }
        }
    }

    private var normalModeSection: some View {
        ProtocolSection("2", "Normalbetrieb: evidenzsicher") {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Direkte technische Beobachtbarkeit")
                    .font(Typeface.heading)
                    .foregroundStyle(Ink.primary)
                stepList([
                    "Setup mit zweckgebundener Einwilligung",
                    "technische Aufnahmehinweise zu Horizont, Kameraruhe, Belichtung, sichtbaren Bildstrukturen und Audiopegel",
                    "Reflexion mit selbst gesetzten Zeitmarken"
                ])
                caption("Bildstruktur-Signale beschreiben nur Beobachtbarkeit. Sie erkennen weder Unterrichtsqualität noch Lernen, Aufmerksamkeit, Feedback oder Beteiligung.")
            }
        }
    }

    private var experimentalSection: some View {
        ProtocolSection("3", "Experimenteller Modus") {
            HypothesisBlock(title: "Unvalidierte regelbasierte Hypothesen") {
                Text("Nur nach Eingabe einer gültigen Protokoll- und Aufsichtsreferenz. Regelaktivierungen werden dauerhaft getrennt vom Normalbetrieb gekennzeichnet und dürfen nicht als Wahrscheinlichkeit, menschlicher Code oder pädagogische Bewertung interpretiert werden.")
                    .font(Typeface.proseSmall)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var dataPathSection: some View {
        ProtocolSection("4", "Technischer Datenweg") {
            VStack(alignment: .leading, spacing: Space.m) {
                stepList([
                    "CoreMotion und AVCapture",
                    "lokale Signalextraktion",
                    "technische Aufnahmehinweise",
                    "lokaler SessionStore"
                ])
                Text("Video, Metadaten und Reflexion bleiben ohne ausdrückliche Freigabe im App-Speicher.")
                    .font(Typeface.prose)
                    .foregroundStyle(Ink.primary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                StatusMark("Der lokale Zugriff ist durch die iOS-Geräteeigentümer-Authentifizierung geschützt.", kind: .secured)
                caption("Ein Audit-Pseudonym ist keine bestätigte Identität.")
            }
        }
    }

    private var evidenceSection: some View {
        ProtocolSection("5", "Nachweisstand") {
            VStack(alignment: .leading, spacing: Space.m) {
                FactRow(key: "Claim-Register", value: "v\(EvidenceClaimRegistry.version)", mono: true)
                Text(EvidenceClaimRegistry.claims.first?.allowedWordingDE ?? "Die App meldet direkt beobachtbare Aufnahmebedingungen.")
                    .font(Typeface.prose)
                    .foregroundStyle(Ink.primary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                caption("Der aktuelle Stand belegt Implementierung und automatisierte Tests. Geräte-, Human-Rater- und Wirksamkeitsvalidierung sind getrennte, noch nicht erfüllte Stufen.")
            }
        }
    }

    private var documentationSection: some View {
        ProtocolSection("6", "Dokumentation") {
            VStack(spacing: 0) {
                ForEach([
                    "docs/SCIENTIFIC_ALPHA.md",
                    "docs/RESEARCH_GAP_INVENTORY.md",
                    "docs/EVALUATION.md",
                    "docs/references/unterrichtsvideographie.md"
                ], id: \.self) { path in
                    Text(path)
                        .font(Typeface.valueSmall)
                        .foregroundStyle(Ink.instrument)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, Space.s)
                        .overlay(alignment: .bottom) { Rule() }
                }
            }
        }
    }

    private var scopeSection: some View {
        ProtocolSection("7", "Umfang") {
            VStack(alignment: .leading, spacing: Space.l) {
                bulletList("Enthalten", [
                    "lokale Sitzungsverwaltung",
                    "Geräteeigentümer-Zugriffsschutz",
                    "zweckgebundene Einwilligung",
                    "kontinuierliche Aufnahme",
                    "technische Observierbarkeit",
                    "Medienwiedergabe",
                    "Zeitmarken",
                    "strukturierte Reflexion",
                    "vorab protokollierter Metadatenexport"
                ])
                bulletList("Nicht enthalten", [
                    "Multi-Cam-Synchronisation",
                    "Schnitt",
                    "Portal-Upload",
                    "institutionelle Datenschutzfreigabe",
                    "automatische pädagogische Bewertung",
                    "psychometrische Validierung",
                    "Wirksamkeitsnachweis"
                ])
            }
        }
    }

    private var platformSection: some View {
        ProtocolSection("8", "Plattform") {
            VStack(spacing: 0) {
                FactRow(key: "Zielgeräte", value: "iPhone & iPad (iOS 17+)", identifier: "info.platform")
                FactRow(key: "Sensoren", value: "Kamera, Mikrofon, Gyroskop/Lage")
                FactRow(key: "Speicherung", value: "lokal, sitzungsgebunden")
                FactRow(key: "Standardmodus", value: "evidenzsicher")
            }
        }
    }

    // MARK: Building blocks

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Typeface.caption)
            .foregroundStyle(Ink.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Ordered steps with a mono mark in the margin column.
    private func stepList(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    MarginMark(text: "\(index + 1)")
                        .frame(width: 20, alignment: .leading)
                    Text(step)
                        .font(Typeface.prose)
                        .foregroundStyle(Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func bulletList(_ label: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            FormLabel(label)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text("–")
                        .font(Typeface.valueSmall)
                        .foregroundStyle(Ink.tertiary)
                        .accessibilityHidden(true)
                    Text(item)
                        .font(Typeface.proseSmall)
                        .foregroundStyle(Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

#Preview {
    AboutView()
}

#Preview("Info · Große Schrift") {
    AboutView()
        .environment(\.dynamicTypeSize, .accessibility3)
}
