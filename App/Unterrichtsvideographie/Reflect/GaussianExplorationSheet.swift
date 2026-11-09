import ExperimentalResearch
import SessionCore
import SwiftUI
import UIKit
import simd

/// Observes publication/lifetime without exposing images or changing authorization.
enum GaussianPresentationState: Equatable {
    case generated, unavailable, discarded
}

/// The frozen request is ephemeral. The sheet owns generation, controls and result lifetime.
@MainActor
struct GaussianExplorationSheet: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let request: GaussianFrameRequest
    let isCurrent: @MainActor () -> Bool
    var onPresentationState: @MainActor (GaussianPresentationState) -> Void = { _ in }

    @State private var result: GaussianFrameResult?
    @State private var message: String?
    @State private var canRetry = false
    @State private var stage = GaussianGenerationStage.waiting
    @State private var camera = GaussianCamera()
    @State private var showsSource = false
    @State private var allowsDragging = false
    @State private var marksUncertainty = false
    @State private var generation = UUID()
    @State private var isClosing = false

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
              ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StatusMark("Experiment · nicht validiert", kind: .hypothesis, prominent: true)
                    Text("Relative Tiefe aus einem Standbild. Verdeckte Bereiche bleiben unbekannt.")
                        .font(Typeface.callout)
                        .foregroundStyle(Ink.secondary)

                    if let message {
                        unavailable(message)
                    } else if let result {
                        exploration(result, viewport: viewport.size)
                    } else {
                        VStack(spacing: 12) {
                            ProgressView(stage.title)
                            Text("Die erste Berechnung kann länger dauern. Sie können jederzeit zur Aufnahme zurückkehren.")
                                .font(Typeface.caption).foregroundStyle(Ink.tertiary)
                        }
                            .frame(maxWidth: .infinity, minHeight: 180)
                            .accessibilityIdentifier("reflect.gaussian.loading")
                    }
                    if result != nil { DisclosureGroup("Impulse für die Besprechung") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(Self.discussionPrompts.enumerated()), id: \.offset) { index, prompt in
                                Text("\(index + 1). \(prompt)")
                            }
                            Text("Impulse, keine Auswertung. Antworten werden hier nicht gespeichert; Notizen gehören in Ihre eigene Reflexion zur Originalaufnahme.")
                                .font(Typeface.caption).foregroundStyle(Ink.tertiary)
                        }
                        .font(Typeface.callout).foregroundStyle(Ink.secondary).padding(.top, 8)
                    }
                    .accessibilityIdentifier("reflect.gaussian.prompts") }
                    DisclosureGroup("Was diese Ansicht zeigen kann") {
                        Text("Die KI schätzt relative Tiefe. Daraus entsteht eine unvollständige 2,5D-Oberfläche mit kleinen Perspektivänderungen. Schraffierte Flächen haben keine Bildinformation: Die Kamera hat dort nichts aufgenommen, oder an einer Tiefenkante öffnet sich eine Lücke. Auch unmarkierte Flächen beruhen auf geschätzter Tiefe. Geometrie und Größen sind nicht vermessen; die Ansicht zeigt keine zusätzlich aufgenommenen Ereignisse. Eine geometrische Ansicht von einem anderen Ort zeigt nicht, was eine Person dort gesehen oder erlebt hat.")
                            .font(Typeface.callout).foregroundStyle(Ink.secondary).padding(.top, 8)
                    }
                    .accessibilityIdentifier("reflect.gaussian.limitations")
                    Text("Nur lokal und vorübergehend. Diese Ansicht wird weder als Medienbeleg gespeichert noch exportiert.")
                        .font(Typeface.caption)
                        .foregroundStyle(Ink.tertiary)
                }
                .padding(20)
              }
            }
            .paperSurface()
            .navigationTitle("Perspektive erkunden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zur Aufnahme") { close() }
                        .accessibilityIdentifier("reflect.gaussian.close")
                }
            }
            .task(id: generation) { await generate() }
            .task {
                // Expiry can occur without any observable session mutation.
                while !Task.isCancelled {
                    if !isAuthorized { close(); return }
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
            .onChange(of: appStore.session) { _, _ in
                if !isAuthorized { close() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { GaussianFrameGenerator.discardCachedModel() }
                if phase != .active { close() }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                GaussianFrameGenerator.discardCachedModel()
                close()
            }
            .onDisappear { discard() }
        }
    }

    private static let discussionPrompts = [
        "Was ist im Original direkt sichtbar? Beschreiben Sie, ohne Absichten zuzuschreiben.",
        "Welcher Bereich fehlt oder ist verdeckt? Wo zeigt die Perspektive Schraffur?",
        "Was hat sich durch den Blickwechsel nur in der Darstellung verändert? Die aufgenommenen Ereignisse bleiben dieselben.",
        "Was bleibt unsicher? Welche zusätzliche Quelle (Kameraposition, Beobachtung, Gespräch) bräuchten Sie?",
        "Welche Position oder Beobachtungsroutine könnte in einer künftigen Stunde helfen?"
    ]

    private var isAuthorized: Bool {
        !isClosing && scenePhase == .active
            && request.sessionID == appStore.session.id
            && appStore.session.mediaAssets.contains(where: { $0.id == request.assetID })
            && request.authorization?.matches(appStore.session) == true
            && GaussianExplorationPolicy.permits(appStore.session)
            && isCurrent()
    }

    private func generate() async {
        let token = generation
        guard isAuthorized else { close(); return }
        do {
            let generated = try await GaussianFrameGenerator.generate(
                request, modelURL: GaussianFrameGenerator.bundledModelURL,
                isAuthorized: { generation == token && isAuthorized },
                onProgress: { nextStage in
                    await MainActor.run {
                        guard generation == token, isAuthorized else { return }
                        stage = nextStage
                    }
                }
            )
            guard !Task.isCancelled, generation == token, isAuthorized else { return }
            result = generated
            onPresentationState(.generated)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, generation == token, isAuthorized else { return }
            message = (error as? GaussianFrameError)?.errorDescription
                ?? "Dieses Standbild konnte nicht verarbeitet werden. Bitte zur Aufnahme zurückkehren und eine andere Position wählen."
            if let frameError = error as? GaussianFrameError {
                switch frameError {
                case .invalidFrame, .invalidDepth: canRetry = true
                case .modelUnavailable, .unsupportedModel, .persistenceUnavailable, .staleRequest, .playbackNotReady:
                    canRetry = false
                }
            } else { canRetry = true }
            onPresentationState(.unavailable)
        }
    }

    private func retry() {
        guard isAuthorized else { close(); return }
        result = nil
        message = nil
        canRetry = false
        stage = .waiting
        generation = UUID()
    }

    private func discard() {
        guard !isClosing else { return }
        isClosing = true
        generation = UUID()
        result = nil
        message = nil
        onPresentationState(.discarded)
    }

    private func close() {
        guard !isClosing else { return }
        discard()
        dismiss()
    }

    private func unavailable(_ message: String) -> some View {
        VStack(spacing: 12) {
            ContentUnavailableView("Perspektivansicht nicht verfügbar", systemImage: "viewfinder", description: Text(message))
            if canRetry {
                Button("Erneut versuchen", action: retry)
                    .buttonStyle(InkButtonStyle(kind: .secondary))
                    .accessibilityIdentifier("reflect.gaussian.retry")
            }
        }
        .accessibilityIdentifier("reflect.gaussian.unavailable")
    }

    private func exploration(_ result: GaussianFrameResult, viewport: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            comparison
            if viewport.width >= 760 && !dynamicTypeSize.isAccessibilitySize && !showsSource {
                HStack(alignment: .top, spacing: 20) {
                    canvas(result, width: (viewport.width - 60) * 0.62, heightLimit: viewport.height * 0.64)
                        .frame(maxWidth: .infinity)
                    cameraControls.frame(width: (viewport.width - 60) * 0.38)
                }
            } else {
                canvas(result, width: viewport.width - 40, heightLimit: max(180, viewport.height * 0.54))
                if !showsSource { cameraControls }
            }
            Text("Originalposition: \(reflectionTimecode(Int64(result.actualTime.seconds * 1_000)))")
                .font(Typeface.valueSmall)
                .foregroundStyle(Ink.tertiary)
        }
    }

    @ViewBuilder private var comparison: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Toggle("Originalstandbild anzeigen", isOn: $showsSource)
                .accessibilityIdentifier("reflect.gaussian.comparison")
        } else {
            Picker("Ansicht", selection: $showsSource) {
                Text("Perspektive").tag(false)
                Text("Original").tag(true)
            }
            .pickerStyle(.segmented).accessibilityIdentifier("reflect.gaussian.comparison")
        }
    }

    private func canvas(_ result: GaussianFrameResult, width: CGFloat, heightLimit: CGFloat) -> some View {
        let token = generation
        return VStack(alignment: .leading, spacing: 8) {
            canvasContent(result, width: width, heightLimit: heightLimit, token: token)
            if !showsSource { legend }
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                GaussianHatchSwatch().accessibilityHidden(true)
                Text("Schraffiert: keine Bildinformation – nicht aufgenommen oder Lücke an einer Tiefenkante.")
            }
            if marksUncertainty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // Must match the uncertainty tint in GaussianMetalView (1, 0.62, 0).
                    RoundedRectangle(cornerRadius: 2).fill(Color(red: 1, green: 0.62, blue: 0))
                        .frame(width: 16, height: 10).accessibilityHidden(true)
                    Text("Bernstein: Fläche gegenüber der Aufnahme gedehnt oder an einer Tiefenkante – hier ergänzt die Darstellung zwischen Bildpunkten.")
                }
            }
            Text(marksUncertainty ? "Ohne Markierung: ebenfalls geschätzte Tiefe, kein Genauigkeitsnachweis." : "Alle Flächen beruhen auf geschätzter Tiefe.")
        }
        .font(Typeface.caption)
        .foregroundStyle(Ink.tertiary)
    }

    private func canvasContent(_ result: GaussianFrameResult, width: CGFloat, heightLimit: CGFloat, token: UUID) -> some View {
        Group {
            if showsSource {
                Image(result.sourceImage, scale: 1, label: Text("Originalstandbild aus der Aufnahme"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .accessibilityIdentifier("reflect.gaussian.source")
            } else {
                GaussianExplorationCanvas(surface: result.surface, sourceImage: result.sourceImage, camera: $camera, allowsDragging: allowsDragging,
                                          marksUncertainty: marksUncertainty) { error in
                    guard generation == token, !isClosing else { return }
                    guard isAuthorized else { close(); return }
                    message = error
                    canRetry = true
                    self.result = nil
                    onPresentationState(.unavailable)
                }
                .aspectRatio(CGFloat(result.surface.aspectRatio), contentMode: .fit)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Experimentelle Perspektivansicht aus geschätzter Tiefe")
                .accessibilityHint("Die Perspektive lässt sich mit den folgenden Reglern ändern. Verdeckte Bereiche bleiben unbekannt.")
                .accessibilityAddTraits(.isImage)
                .accessibilityIdentifier("reflect.gaussian.canvas")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: min(max(1, width) / CGFloat(result.surface.aspectRatio), heightLimit))
        .clipShape(RoundedRectangle(cornerRadius: Radius.control))
    }

    private var surfaceAspectRatio: Float { result?.surface.aspectRatio ?? 16 / 9 }

    private var cameraControls: some View {
        VStack(alignment: .leading, spacing: 8) {
                GaussianPositionMap(camera: camera, surfaceAspectRatio: surfaceAspectRatio)
                Toggle("Dehnung und Tiefenkanten markieren", isOn: $marksUncertainty)
                    .font(Typeface.callout).accessibilityIdentifier("reflect.gaussian.uncertainty")
                cameraSlider("Seitlich", id: "horizontal", value: camera.horizontal, limit: GaussianCamera.lateralLimit,
                             negative: "links", positive: "rechts") {
                    camera = GaussianCamera(horizontal: $0, vertical: camera.vertical, dolly: camera.dolly,
                                            yawDegrees: camera.yawDegrees, pitchDegrees: camera.pitchDegrees)
                }
                cameraSlider("Höhe", id: "vertical", value: camera.vertical, limit: GaussianCamera.lateralLimit,
                             negative: "tiefer", positive: "höher") {
                    camera = GaussianCamera(horizontal: camera.horizontal, vertical: $0, dolly: camera.dolly,
                                            yawDegrees: camera.yawDegrees, pitchDegrees: camera.pitchDegrees)
                }
                cameraSlider("Abstand", id: "dolly", value: camera.dolly, limit: GaussianCamera.dollyLimit,
                             negative: "weiter", positive: "näher") {
                    camera = GaussianCamera(horizontal: camera.horizontal, vertical: camera.vertical, dolly: $0,
                                            yawDegrees: camera.yawDegrees, pitchDegrees: camera.pitchDegrees)
                }
                DisclosureGroup("Blickwinkel ändern") {
                    cameraSlider("Seitlicher Winkel", id: "yaw", value: camera.yawDegrees, limit: GaussianCamera.yawLimitDegrees,
                                 negative: "links", positive: "rechts", isAngle: true) {
                        camera = GaussianCamera(horizontal: camera.horizontal, vertical: camera.vertical, dolly: camera.dolly,
                                                yawDegrees: $0, pitchDegrees: camera.pitchDegrees)
                    }
                    cameraSlider("Vertikaler Winkel", id: "pitch", value: camera.pitchDegrees, limit: GaussianCamera.pitchLimitDegrees,
                                 negative: "tiefer", positive: "höher", isAngle: true) {
                        camera = GaussianCamera(horizontal: camera.horizontal, vertical: camera.vertical, dolly: camera.dolly,
                                                yawDegrees: camera.yawDegrees, pitchDegrees: $0)
                    }
                }
                .accessibilityIdentifier("reflect.gaussian.angles")
                Toggle("Perspektive durch Ziehen ändern", isOn: $allowsDragging)
                    .font(Typeface.callout).accessibilityIdentifier("reflect.gaussian.dragEnabled")
                Button("Perspektive zurücksetzen") { camera = GaussianCamera() }
                    .buttonStyle(InkButtonStyle(kind: .secondary))
                    .disabled(camera == GaussianCamera())
                    .accessibilityIdentifier("reflect.gaussian.reset")
                Text(allowsDragging ? "Im Bild ziehen. Zum Scrollen außerhalb des Bildes wischen." : "Die Regler ändern die Ansicht. Ziehen im Bild ist ausgeschaltet, damit Sie durch die Seite scrollen können.")
                    .font(Typeface.caption)
                    .foregroundStyle(Ink.tertiary)
        }
    }

    private func cameraSlider(_ title: String, id: String, value: Float, limit: Float,
                              negative: String, positive: String, isAngle: Bool = false,
                              set: @escaping (Float) -> Void) -> some View {
        let magnitude = isAngle ? String(format: "%.1f Grad", abs(value)) : "\(Int(abs(value) / limit * 100)) Prozent"
        let position = abs(value) < 0.0001 ? "Originalposition" : "\(value < 0 ? negative : positive) · \(magnitude)"
        return VStack(alignment: .leading, spacing: 0) {
            Text(title).font(Typeface.callout.weight(.semibold))
            Text(position).font(Typeface.caption).foregroundStyle(Ink.tertiary)
            Slider(value: Binding(get: { Double(value) }, set: { set(Float($0)) }), in: -Double(limit)...Double(limit))
                .frame(minHeight: 44)
                .tint(Ink.human)
                .accessibilityLabel(title)
                .accessibilityValue(position)
                .accessibilityIdentifier("reflect.gaussian.\(id)")
        }
    }
}

private struct GaussianExplorationCanvas: View {
    let surface: GaussianDepthSurface
    let sourceImage: CGImage
    @Binding var camera: GaussianCamera
    let allowsDragging: Bool
    let marksUncertainty: Bool
    let onFailure: (String) -> Void
    @State private var dragStart: GaussianCamera?

    var body: some View {
        GeometryReader { proxy in
            GaussianMetalView(surface: surface, sourceImage: sourceImage, camera: camera, marksUncertainty: marksUncertainty, onFailure: onFailure)
                .gesture(DragGesture().onChanged { value in
                    if dragStart == nil { dragStart = camera }
                    guard let start = dragStart else { return }
                    camera = GaussianCamera(
                        horizontal: start.horizontal - Float(value.translation.width / max(1, proxy.size.width)) * 0.2,
                        vertical: start.vertical + Float(value.translation.height / max(1, proxy.size.height)) * 0.2,
                        dolly: start.dolly, yawDegrees: start.yawDegrees, pitchDegrees: start.pitchDegrees
                    )
                }.onEnded { _ in dragStart = nil }, including: allowsDragging ? .all : .none)
                .onChange(of: allowsDragging) { _, _ in dragStart = nil }
        }
    }
}

/// Diagonal hatch swatch matching the renderer's "not recorded" background.
private struct GaussianHatchSwatch: View {
    // Same colours as gaussianBackgroundFragment.
    static let base = Color(red: 0.055, green: 0.065, blue: 0.08)
    static let stripe = Color(red: 0.36, green: 0.38, blue: 0.42)

    var body: some View {
        Canvas { context, size in
            var lines = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                lines.move(to: CGPoint(x: x, y: size.height))
                lines.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 4
            }
            context.clip(to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 2))
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.base))
            context.stroke(lines, with: .color(Self.stripe), lineWidth: 1.5)
        }
        .frame(width: 16, height: 10)
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Ink.tertiary, lineWidth: 0.5))
    }
}

/// Top-down view (x right, z away) of the virtual camera relative to the recording camera, at unexaggerated scale of the assumed display units.
private struct GaussianPositionMap: View {
    let camera: GaussianCamera
    let surfaceAspectRatio: Float

    private var frame: GaussianViewFrame { GaussianViewFrame(camera: camera) }
    private static let zRange: ClosedRange<Float> = -0.15...1.6

    private var heightWord: String {
        let y = frame.position.y
        if abs(y) < 0.0001 { return "gleich" }
        return y > 0 ? "höher" : "tiefer"
    }

    private var accessibilityDescription: String {
        guard camera != GaussianCamera() else { return "Ansicht an der Aufnahmeposition" }
        func part(_ value: Float, _ limit: Float, _ negative: String, _ positive: String) -> String? {
            guard abs(value) >= 0.0001 else { return nil }
            return "\(Int(abs(value) / limit * 100)) Prozent \(value < 0 ? negative : positive)"
        }
        func angle(_ value: Float, _ negative: String, _ positive: String) -> String? {
            guard abs(value) >= 0.0001 else { return nil }
            return "Winkel \(String(format: "%.1f", abs(value)).replacingOccurrences(of: ".", with: ",")) Grad \(value < 0 ? negative : positive)"
        }
        let parts = [
            part(camera.horizontal, GaussianCamera.lateralLimit, "links", "rechts"),
            part(camera.vertical, GaussianCamera.lateralLimit, "tiefer", "höher"),
            part(camera.dolly, GaussianCamera.dollyLimit, "weiter", "näher"),
            angle(camera.yawDegrees, "links", "rechts"),
            angle(camera.pitchDegrees, "tiefer", "höher")
        ].compactMap { $0 }
        return "Ansicht " + parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Position gegenüber der Aufnahme").font(Typeface.heading)
            Canvas { context, size in draw(&context, size: size) }
                .frame(height: 120)
                .frame(maxWidth: .infinity)
            Text("Höhe: \(heightWord). Maßstab geschätzt, nicht vermessen.")
                .font(Typeface.caption).foregroundStyle(Ink.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Position gegenüber der Aufnahme")
        .accessibilityValue("\(accessibilityDescription). Höhe: \(heightWord). Maßstab geschätzt, nicht vermessen.")
        .accessibilityIdentifier("reflect.gaussian.positionMap")
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let tanH = tan(GaussianDepthSurface.verticalFieldOfViewDegrees * .pi / 360) * surfaceAspectRatio
        let near = GaussianDepthSurface.nearestDepth, far = GaussianDepthSurface.farthestDepth
        let halfWidth = max(far * tanH, 0.25) * 1.05
        let scale = CGFloat(min(Float(size.height) / (Self.zRange.upperBound - Self.zRange.lowerBound),
                                Float(size.width) / (2 * halfWidth)))
        func point(_ x: Float, _ z: Float) -> CGPoint {
            CGPoint(x: size.width / 2 + CGFloat(x) * scale,
                    y: size.height - CGFloat(z - Self.zRange.lowerBound) * scale)
        }
        var area = Path()
        area.move(to: point(-near * tanH, near))
        area.addLine(to: point(near * tanH, near))
        area.addLine(to: point(far * tanH, far))
        area.addLine(to: point(-far * tanH, far))
        area.closeSubpath()
        context.fill(area, with: .color(Ink.human.opacity(0.18)))
        context.stroke(area, with: .color(Ink.human.opacity(0.5)), lineWidth: 1)

        let origin = point(0, 0)
        context.fill(Path(ellipseIn: CGRect(x: origin.x - 4, y: origin.y - 4, width: 8, height: 8)),
                     with: .color(Ink.human))
        context.draw(Text("Aufnahme").font(.caption2).foregroundStyle(Ink.secondary),
                     at: CGPoint(x: origin.x - 10, y: origin.y), anchor: .trailing)

        let view = frame
        let center = point(view.position.x, view.position.z)
        var tick = Path()
        tick.move(to: center)
        let length = SIMD2<Float>(view.forward.x, view.forward.z)
        let unit = length / max(simd_length(length), 0.0001)
        tick.addLine(to: CGPoint(x: center.x + CGFloat(unit.x) * 14, y: center.y - CGFloat(unit.y) * 14))
        context.stroke(tick, with: .color(Ink.primary), lineWidth: 2)
        context.stroke(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)),
                       with: .color(Ink.primary), lineWidth: 2)
        context.draw(Text("Ansicht").font(.caption2).foregroundStyle(Ink.secondary),
                     at: CGPoint(x: max(center.x, origin.x) + 10, y: center.y), anchor: .leading)
    }
}
