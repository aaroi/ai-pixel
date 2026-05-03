import SwiftUI

// Grayscale palette lifted in spirit from ai.md.
// Light and dark variants resolve via @Environment(\.colorScheme).

// Pure grayscale, no harsh contrasts. fg is intentionally not pure white in dark
// mode — it's softened to ~80% so buttons and outlines don't glare.
enum Palette {
    static func bg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x121212) : Color(hex: 0xFAFAFA)
    }
    static func fg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xCBCBCB) : Color(hex: 0x2D2D2D)
    }
    static func fgMuted(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x8B8B8B) : Color(hex: 0x7A7A7A)
    }
    static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x2A2A2A) : Color(hex: 0xE5E5E5)
    }
    static func borderStrong(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x4A4A4A) : Color(hex: 0xB5B5B5)
    }
    static func selection(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }
    static func success(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x6BB87E) : Color(hex: 0x3F8C57)
    }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

/// Mono is reserved for filenames, dimensions, bytes — the technical bits.
/// System font carries everything else: prose, buttons, labels.
enum Typography {
    static let mono       = Font.system(.body,  design: .monospaced)
    static let monoSmall  = Font.system(size: 11, design: .monospaced)
    static let monoTiny   = Font.system(size: 10, design: .monospaced)
    static let monoLarge  = Font.system(size: 14, design: .monospaced)

    static let system       = Font.system(.body)
    static let systemSmall  = Font.system(size: 12)
    static let systemTiny   = Font.system(size: 11)
    static let systemLarge  = Font.system(size: 15, weight: .medium)
}
