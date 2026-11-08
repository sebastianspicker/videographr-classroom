import SwiftUI
import UIKit

// "Protokoll in drei Tinten": documents are set on paper, the capture screen is
// a dark room, and colour states provenance. Königsblau marks what a person wrote
// or decided, graphite what the instrument measured, ochre what an unvalidated
// experiment proposes. Signal red exists only for a running take.

// MARK: - Colour roles

enum Ink {
    /// Page background of every document surface.
    static let paper = dynamic(light: 0xF5F3EE, dark: 0x16171A)
    /// A raised sheet inside a page: grouped records, sheets, menus.
    static let sheet = dynamic(light: 0xFBFAF7, dark: 0x1E2023)
    /// Printed text: titles, labels, body.
    static let primary = dynamic(light: 0x1A1C1E, dark: 0xECEAE4)
    static let secondary = dynamic(light: 0x4E5257, dark: 0xB9B6AE)
    /// Captions and quiet metadata. Still AA for text on paper and sheet.
    static let tertiary = dynamic(light: 0x686C72, dark: 0x9A978F)
    /// Ruled lines that structure a page (decorative, not a control boundary).
    static let rule = dynamic(light: 0xD9D5CC, dark: 0x34363A)
    /// Writing lines of inputs and control outlines; ≥ 3:1 against paper.
    static let ruleStrong = dynamic(light: 0x857F74, dark: 0x77797F)

    /// Königsblau: the operator's hand. Actions, entered values, human notes.
    static let human = dynamic(light: 0x1F3FAA, dark: 0x9DB0FF)
    /// Text set on a filled Königsblau control.
    static let onHuman = dynamic(light: 0xFFFFFF, dark: 0x101218)
    /// Graphite: what the instrument measured. Always paired with mono type.
    static let instrument = dynamic(light: 0x3A3F45, dark: 0xC9CDD2)
    /// Ochre: experimental, unvalidated hypotheses. Always paired with hatching.
    static let hypothesis = dynamic(light: 0x8A5A00, dark: 0xE2B04A)
    /// Documented, secured, saved. Used sparingly for confirmations only.
    static let secured = dynamic(light: 0x2F6B45, dark: 0x7CC79A)
    /// Needs a look: a check is incomplete or a technical warning is present.
    static let attention = dynamic(light: 0x9A4A00, dark: 0xFFB070)
    /// Errors and destructive actions on paper.
    static let fault = dynamic(light: 0xB3261E, dark: 0xFF8A80)

    /// Wash behind the human hand, e.g. the selected prompt.
    static let humanWash = dynamic(light: 0xE6EAF6, dark: 0x22283A)
    static let hypothesisWash = dynamic(light: 0xF3EBDA, dark: 0x2A241A)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

/// The capture screen is always dark: a lit screen at the back of a classroom
/// distracts, and the preview must dominate.
enum Room {
    static let canvas = Color(hex: 0x0E0F11)
    static let surface = Color(hex: 0x17191C)
    static let raised = Color(hex: 0x202327)
    static let primary = Color(hex: 0xECEAE4)
    static let secondary = Color(hex: 0xB9B6AE)
    static let tertiary = Color(hex: 0x9A978F)
    static let rule = Color(hex: 0x2C2F33)
    static let ruleStrong = Color(hex: 0x6E7177)
    static let human = Color(hex: 0x9DB0FF)
    static let instrument = Color(hex: 0xC9CDD2)
    static let hypothesis = Color(hex: 0xE2B04A)
    static let secured = Color(hex: 0x7CC79A)
    static let attention = Color(hex: 0xFFB070)
    static let fault = Color(hex: 0xFF8A80)
    static let signal = Color(hex: 0xE5243B)
    static let signalDeep = Color(hex: 0xA30F24)
}

// MARK: - Type

/// Serif is a person or a document, mono is the instrument, sans is the interface.
/// Every custom face scales with Dynamic Type through `relativeTo`.
enum Typeface {
    private static let display = "SourceSerif4Display-Semibold"
    private static let subhead = "SourceSerif4Subhead-Semibold"
    private static let text = "SourceSerif4SmText-Regular"
    private static let italic = "SourceSerif4SmText-It"

    /// Screen and document titles.
    static let title = Font.custom(display, size: 30, relativeTo: .title)
    static let titleCompact = Font.custom(display, size: 26, relativeTo: .title)
    /// Section headings inside a document.
    static let section = Font.custom(subhead, size: 20, relativeTo: .title3)
    /// Smaller headings: list rows, record titles.
    static let heading = Font.custom(subhead, size: 17, relativeTo: .headline)
    /// Human writing and long-form reading.
    static let prose = Font.custom(text, size: 17, relativeTo: .body)
    static let proseSmall = Font.custom(text, size: 15, relativeTo: .subheadline)
    static let quote = Font.custom(italic, size: 15, relativeTo: .subheadline)
    /// Wordmark: always lowercase.
    static let wordmark = Font.custom(display, size: 21, relativeTo: .title3)

    /// Printed form labels: small caps, never all-caps shouting.
    static let label = Font.footnote.weight(.semibold).lowercaseSmallCaps()
    static let labelSmall = Font.caption.weight(.semibold).lowercaseSmallCaps()
    /// Interface text.
    static let body = Font.body
    static let callout = Font.callout
    static let caption = Font.footnote
    static let captionSmall = Font.caption

    /// Instrument values.
    static let value = Font.system(.callout, design: .monospaced)
    static let valueSmall = Font.system(.caption, design: .monospaced)
    static let timecode = Font.system(.largeTitle, design: .monospaced).weight(.medium)
    static let timecodeInline = Font.system(.subheadline, design: .monospaced).weight(.medium)
}

// MARK: - Space, shape, motion

enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48

    /// Page gutters.
    static let gutterCompact: CGFloat = 20
    static let gutterRegular: CGFloat = 40
    /// Width of the protocol margin that carries section numbers and timecodes.
    static let marginRegular: CGFloat = 72
    static let marginCompact: CGFloat = 52
    /// Readable measure for prose and forms.
    static let measure: CGFloat = 680
    static let pageMaximum: CGFloat = 1_180
    /// Minimum interactive height.
    static let target: CGFloat = 44
}

enum Radius {
    /// Controls are near-square, like a stamp, not a pill.
    static let control: CGFloat = 3
}

// MARK: - Helpers

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
