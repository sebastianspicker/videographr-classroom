import SwiftUI

// MARK: - Surfaces

/// Which material a subtree is set on. Components read it to pick their inks.
enum SurfaceMaterial {
    case paper
    case room
}

private struct SurfaceMaterialKey: EnvironmentKey {
    static let defaultValue = SurfaceMaterial.paper
}

extension EnvironmentValues {
    var surfaceMaterial: SurfaceMaterial {
        get { self[SurfaceMaterialKey.self] }
        set { self[SurfaceMaterialKey.self] = newValue }
    }
}

extension View {
    /// A document page: preparation, notes, export, reference, info.
    /// Follows the system appearance.
    func paperSurface() -> some View {
        self.environment(\.surfaceMaterial, .paper)
            .tint(Ink.human)
            .foregroundStyle(Ink.primary)
            .scrollContentBackground(.hidden)
            .background(Ink.paper.ignoresSafeArea())
            .toolbarBackground(Ink.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    /// The capture room: always dark so the preview dominates and the screen
    /// stays discreet in a classroom.
    func roomSurface() -> some View {
        self.environment(\.surfaceMaterial, .room)
            .tint(Room.human)
            .foregroundStyle(Room.primary)
            .scrollContentBackground(.hidden)
            .background(Room.canvas.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
    }

    /// The writing line of a form field: the person's entry in Königsblau serif
    /// on a ruled line, not in a box.
    func writingLine(mono: Bool = false) -> some View {
        modifier(WritingLine(mono: mono))
    }
}

private struct WritingLine: ViewModifier {
    let mono: Bool
    @Environment(\.surfaceMaterial) private var material

    func body(content: Content) -> some View {
        content
            .font(mono ? Typeface.value : Typeface.prose)
            .foregroundStyle(material == .room ? Room.human : Ink.human)
            .padding(.vertical, 10)
            .frame(minHeight: Space.target, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(material == .room ? Room.ruleStrong : Ink.ruleStrong)
                    .frame(height: 1)
            }
    }
}

// MARK: - Rules and marks

/// A full-width ruled line.
struct Rule: View {
    var strong = false
    @Environment(\.surfaceMaterial) private var material

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch (material, strong) {
        case (.paper, false): Ink.rule
        case (.paper, true): Ink.ruleStrong
        case (.room, false): Room.rule
        case (.room, true): Room.ruleStrong
        }
    }
}

/// Printed form label in small caps.
struct FormLabel: View {
    let text: String
    var small = false
    @Environment(\.surfaceMaterial) private var material

    init(_ text: String, small: Bool = false) {
        self.text = text
        self.small = small
    }

    var body: some View {
        Text(text)
            .font(small ? Typeface.labelSmall : Typeface.label)
            .tracking(0.3)
            .foregroundStyle(material == .room ? Room.secondary : Ink.secondary)
    }
}

/// The reference mark in the protocol margin: a section number or a timecode.
struct MarginMark: View {
    let text: String
    var emphasized = false
    @Environment(\.surfaceMaterial) private var material

    var body: some View {
        Text(text)
            .font(Typeface.valueSmall)
            .foregroundStyle(emphasized
                ? (material == .room ? Room.human : Ink.human)
                : (material == .room ? Room.tertiary : Ink.tertiary))
            .monospacedDigit()
    }
}

// MARK: - Document structure

/// Title block of a document page. The serif title carries the page.
struct DocumentHeader<Accessory: View>: View {
    let eyebrow: String
    let title: String
    var summary: String?
    @ViewBuilder var accessory: () -> Accessory
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(
        eyebrow: String,
        title: String,
        summary: String? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.summary = summary
        self.accessory = accessory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .lastTextBaseline, spacing: Space.l) {
                    titleBlock
                    Spacer(minLength: Space.l)
                    accessory()
                }
                VStack(alignment: .leading, spacing: Space.m) {
                    titleBlock
                    accessory()
                }
            }
            if let summary {
                Text(summary)
                    .font(Typeface.proseSmall)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: Space.measure, alignment: .leading)
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            FormLabel(eyebrow)
            Text(title)
                .font(sizeClass == .regular ? Typeface.title : Typeface.titleCompact)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// A numbered section of the protocol. On regular widths the number sits in
/// the margin column; on compact widths it precedes the heading.
struct ProtocolSection<Content: View>: View {
    let mark: String
    let title: String
    var note: String?
    @ViewBuilder var content: () -> Content
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ mark: String, _ title: String, note: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.mark = mark
        self.title = title
        self.note = note
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rule()
            if usesMargin {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    MarginMark(text: "§ \(mark)")
                        .frame(width: Space.marginRegular, alignment: .leading)
                    column
                }
            } else {
                column
            }
        }
    }

    private var usesMargin: Bool {
        sizeClass == .regular && !typeSize.isAccessibilitySize
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    if !usesMargin {
                        MarginMark(text: "§ \(mark)")
                    }
                    Text(title)
                        .font(Typeface.section)
                        .foregroundStyle(Ink.primary)
                        .accessibilityAddTraits(.isHeader)
                }
                if let note {
                    Text(note)
                        .font(Typeface.caption)
                        .foregroundStyle(Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .padding(.top, Space.l)
        .padding(.bottom, Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A labelled form field: small-caps label above a writing line.
struct LedgerField<Content: View>: View {
    let label: String
    var hint: String?
    @ViewBuilder var content: () -> Content

    init(_ label: String, hint: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.hint = hint
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            FormLabel(label)
            content()
            if let hint {
                Text(hint)
                    .font(Typeface.captionSmall)
                    .foregroundStyle(Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Two fields side by side when there is room, stacked otherwise.
struct LedgerPair<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if sizeClass == .regular && !typeSize.isAccessibilitySize {
            HStack(alignment: .top, spacing: Space.xl) {
                leading().frame(maxWidth: .infinity, alignment: .leading)
                trailing().frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: Space.l) {
                leading()
                trailing()
            }
        }
    }
}

/// A menu picker whose label reads like an entry on the writing line.
struct LedgerMenuPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    var accessibilityID: String?
    var mono = false

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(options.first { $0.value == selection }?.label ?? "–")
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Ink.tertiary)
                    .accessibilityHidden(true)
            }
            .writingLine(mono: mono)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityValue(options.first { $0.value == selection }?.label ?? "")
        .modifier(OptionalIdentifier(accessibilityID))
    }
}

/// Key–value line for facts and package contents.
struct FactRow: View {
    let key: String
    let value: String
    var mono = false
    var identifier: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                FormLabel(key).frame(width: 148, alignment: .leading)
                valueText
            }
            VStack(alignment: .leading, spacing: Space.xxs) {
                FormLabel(key)
                valueText
            }
        }
        .padding(.vertical, Space.s)
        .overlay(alignment: .bottom) { Rule() }
    }

    private var valueText: some View {
        Text(value)
            .font(mono ? Typeface.value : Typeface.callout)
            .foregroundStyle(mono ? Ink.instrument : Ink.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(OptionalIdentifier(identifier))
    }
}

// MARK: - Status

/// Status as glyph plus words; colour is never the only carrier.
struct StatusMark: View {
    enum Kind {
        case secured, open, attention, fault, hypothesis, neutral
    }

    let text: String
    var kind: Kind = .neutral
    var prominent = false
    @Environment(\.surfaceMaterial) private var material

    init(_ text: String, kind: Kind = .neutral, prominent: Bool = false) {
        self.text = text
        self.kind = kind
        self.prominent = prominent
    }

    var body: some View {
        Label {
            Text(text)
                .font(prominent ? Typeface.callout.weight(.semibold) : Typeface.caption.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .font(prominent ? .callout.weight(.semibold) : .footnote.weight(.semibold))
        }
        .labelStyle(StatusLabelStyle())
        .foregroundStyle(color)
    }

    private var symbol: String {
        switch kind {
        case .secured: "checkmark"
        case .open: "circle.dashed"
        case .attention: "exclamationmark.triangle"
        case .fault: "xmark.octagon"
        case .hypothesis: "questionmark.diamond"
        case .neutral: "circle"
        }
    }

    private var color: Color {
        switch (kind, material) {
        case (.secured, .paper): Ink.secured
        case (.secured, .room): Room.secured
        case (.open, .paper), (.neutral, .paper): Ink.secondary
        case (.open, .room), (.neutral, .room): Room.secondary
        case (.attention, .paper): Ink.attention
        case (.attention, .room): Room.attention
        case (.fault, .paper): Ink.fault
        case (.fault, .room): Room.fault
        case (.hypothesis, .paper): Ink.hypothesis
        case (.hypothesis, .room): Room.hypothesis
        }
    }
}

private struct StatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

// MARK: - Experimental content

/// Diagonal hatching: the visual signature of unvalidated, experimental output.
struct Hatching: SwiftUI.Shape {
    var spacing: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}

/// Wraps experimental content: a hatched ochre rule, a fixed label, a wash.
struct HypothesisBlock<Content: View>: View {
    var title = "Experimentell · nicht validiert"
    @ViewBuilder var content: () -> Content
    @Environment(\.surfaceMaterial) private var material

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Hatching()
                .stroke(ochre, lineWidth: 1.5)
                .frame(width: 8)
                .clipped()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s) {
                StatusMark(title, kind: .hypothesis)
                content()
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(material == .room ? Room.raised : Ink.hypothesisWash)
        .accessibilityElement(children: .contain)
    }

    private var ochre: Color { material == .room ? Room.hypothesis : Ink.hypothesis }
}

// MARK: - Buttons

struct InkButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet, destructive }

    var kind: Kind = .secondary
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.surfaceMaterial) private var material

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(kind == .quiet ? Typeface.callout.weight(.semibold) : Typeface.body.weight(.semibold))
            .multilineTextAlignment(kind == .quiet ? .leading : .center)
            .padding(.horizontal, kind == .quiet ? 0 : 18)
            .padding(.vertical, 11)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Space.target)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: Radius.control))
            .overlay {
                if kind == .secondary || kind == .destructive {
                    RoundedRectangle(cornerRadius: Radius.control)
                        .strokeBorder(border, lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .contentShape(Rectangle())
    }

    private var human: Color { material == .room ? Room.human : Ink.human }
    private var disabledInk: Color { material == .room ? Room.tertiary : Ink.tertiary }

    private var foreground: Color {
        guard isEnabled else { return disabledInk }
        switch kind {
        case .primary: return material == .room ? Room.canvas : Ink.onHuman
        case .secondary, .quiet: return human
        case .destructive: return material == .room ? Room.fault : Ink.fault
        }
    }

    private var background: Color {
        guard kind == .primary else { return .clear }
        if !isEnabled { return material == .room ? Room.raised : Ink.rule }
        return human
    }

    private var border: Color {
        guard isEnabled else { return material == .room ? Room.rule : Ink.rule }
        return kind == .destructive ? (material == .room ? Room.fault : Ink.fault) : human
    }
}

/// A square ballot box, ticked in Königsblau, like a consent form.
struct InkCheckboxStyle: ToggleStyle {
    @Environment(\.surfaceMaterial) private var material

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(configuration.isOn ? human : Color.clear)
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(configuration.isOn ? human : ruleStrong, lineWidth: 1.5)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(material == .room ? Room.canvas : Ink.onHuman)
                    }
                }
                .frame(width: 20, height: 20)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                configuration.label
                    .font(Typeface.body)
                    .foregroundStyle(material == .room ? Room.primary : Ink.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: Space.target, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "Ausgewählt" : "Nicht ausgewählt")
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }

    private var human: Color { material == .room ? Room.human : Ink.human }
    private var ruleStrong: Color { material == .room ? Room.ruleStrong : Ink.ruleStrong }
}

/// Disclosure that reads as a collapsible protocol section.
struct InkDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    configuration.label
                        .font(Typeface.callout.weight(.semibold))
                        .foregroundStyle(Ink.human)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: Space.s)
                    Image(systemName: configuration.isExpanded ? "minus" : "plus")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Ink.human)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: Space.target)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Geöffnet" : "Geschlossen")
            if configuration.isExpanded {
                configuration.content
                    .padding(.top, Space.s)
            }
        }
    }
}

// MARK: - Utilities

struct OptionalIdentifier: ViewModifier {
    let id: String?
    init(_ id: String?) { self.id = id }

    func body(content: Content) -> some View {
        if let id { content.accessibilityIdentifier(id) } else { content }
    }
}

/// Persistence state as a status mark, shared by every editing surface.
struct SaveStateMark: View {
    let state: AppStore.SaveState

    var body: some View {
        switch state {
        case .saved: StatusMark("Lokal gesichert", kind: .secured)
        case .unsaved: StatusMark("Ungesicherte Änderungen", kind: .open)
        case .saving: StatusMark("Wird gesichert …", kind: .open)
        case let .failed(message): StatusMark("Speicherfehler: \(message)", kind: .fault)
        }
    }
}
