import SwiftUI

// Grayscale palette lifted in spirit from ai.md.
// Light and dark variants resolve via @Environment(\.colorScheme).

/// Palette mapped onto Tailwind CSS's `zinc-*` scale — near-neutral with only
/// a faint cool cast, chosen over `gray-*` so dark mode doesn't read as blue.
/// Hex values pulled directly from Tailwind v3 defaults. Success uses `emerald-*`.
///
/// Reference: https://tailwindcss.com/docs/customizing-colors
enum Palette {
    // MARK: Tailwind zinc-* hex values

    private enum Gray {
        static let _50:  UInt32 = 0xFAFAFA
        static let _100: UInt32 = 0xF4F4F5
        static let _200: UInt32 = 0xE4E4E7
        static let _300: UInt32 = 0xD4D4D8
        static let _400: UInt32 = 0xA1A1AA
        static let _500: UInt32 = 0x71717A
        static let _600: UInt32 = 0x52525B
        static let _700: UInt32 = 0x3F3F46
        static let _800: UInt32 = 0x27272A
        static let _900: UInt32 = 0x18181B
        static let _950: UInt32 = 0x09090B
    }

    private enum Emerald {
        static let _400: UInt32 = 0x34D399
        static let _600: UInt32 = 0x059669
    }

    // MARK: Semantic tokens (light / dark)

    /// Window background. light: gray-50 · dark: gray-900
    static func bg(_ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? Gray._900 : Gray._50)
    }
    /// Primary foreground. light: gray-800 · dark: gray-300
    static func fg(_ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? Gray._300 : Gray._800)
    }
    /// Muted/secondary foreground. light + dark: gray-500
    static func fgMuted(_ scheme: ColorScheme) -> Color {
        Color(hex: Gray._500)
    }
    /// Subtle borders / dividers. light: gray-200 · dark: gray-800
    static func border(_ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? Gray._800 : Gray._200)
    }
    /// Stronger borders (e.g. active button outlines). light: gray-400 · dark: gray-700
    static func borderStrong(_ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? Gray._700 : Gray._400)
    }
    /// Selected-segment fill. Subtle tint of fg.
    static func selection(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
    /// Savings indicator. light: emerald-600 · dark: emerald-400
    static func success(_ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? Emerald._400 : Emerald._600)
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
