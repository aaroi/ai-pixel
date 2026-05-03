import SwiftUI
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

enum SettingsKeys {
    static let outputSuffix  = "outputSuffix"
    static let outputFormat  = "outputFormat"
    static let outputQuality = "outputQuality"

    static let defaultSuffix:  String = "-compressed"
    static let defaultFormat:  String = OutputFormat.jpeg.rawValue
    static let defaultQuality: Double = 0.95
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case jpeg
    case png
    case webp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png:  return "PNG"
        case .webp: return "WebP"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png:  return "png"
        case .webp: return "webp"
        }
    }

    var typeIdentifier: CFString {
        switch self {
        case .jpeg: return UTType.jpeg.identifier as CFString
        case .png:  return UTType.png.identifier as CFString
        case .webp: return "org.webmproject.webp" as CFString
        }
    }

    var isLossy: Bool { self != .png }

    /// Whether ImageIO can encode this format on the current system.
    var nativelyEncodable: Bool {
        let supported = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        return supported.contains(typeIdentifier as String)
    }

    /// All formats are exposed in the picker. Encoding may still fail at the
    /// system level (e.g. WebP without `cwebp` installed) — that's surfaced
    /// per-image with a clear error.
    static var available: [OutputFormat] { allCases }
}

extension UserDefaults {
    /// Returns the user's chosen suffix verbatim, including empty string if
    /// they've cleared the field. Falls back to the first-launch default only
    /// when the key has never been set.
    var outputSuffix: String {
        string(forKey: SettingsKeys.outputSuffix) ?? SettingsKeys.defaultSuffix
    }

    var outputFormat: OutputFormat {
        let raw = string(forKey: SettingsKeys.outputFormat) ?? SettingsKeys.defaultFormat
        return OutputFormat(rawValue: raw) ?? .jpeg
    }

    var outputQuality: Double {
        let v = double(forKey: SettingsKeys.outputQuality)
        // double(forKey:) returns 0 if unset — fall back to default in that case.
        return v == 0 ? SettingsKeys.defaultQuality : v
    }
}
