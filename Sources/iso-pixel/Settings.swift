import SwiftUI
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

enum SettingsKeys {
    static let outputSuffix  = "outputSuffix"
    static let outputFormat  = "outputFormat"
    static let outputQuality = "outputQuality"
    static let outputMaxEdge     = "outputMaxEdge"
    static let outputMaxEdgeMode = "outputMaxEdgeMode"
    static let outputGifFPS  = "outputGifFPS"

    static let defaultSuffix:  String = "-compressed"
    static let defaultFormat:  String = OutputFormat.jpeg.rawValue
    static let defaultQuality: Double = 0.95
    /// Long-edge target in pixels. `0` means don't resize — just re-encode.
    static let defaultMaxEdge: Int    = 1920
    /// "preset" or "custom". Custom mode shows the numeric input.
    static let defaultMaxEdgeMode: String = "preset"
    /// Frames per second for video → GIF conversions.
    static let defaultGifFPS: Int = 12
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case jpeg
    case png
    case webp
    case gif

    var id: String { rawValue }

    var label: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png:  return "PNG"
        case .webp: return "WebP"
        case .gif:  return "GIF"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png:  return "png"
        case .webp: return "webp"
        case .gif:  return "gif"
        }
    }

    var typeIdentifier: CFString {
        switch self {
        case .jpeg: return UTType.jpeg.identifier as CFString
        case .png:  return UTType.png.identifier as CFString
        case .webp: return "org.webmproject.webp" as CFString
        case .gif:  return UTType.gif.identifier as CFString
        }
    }

    var isLossy: Bool { self != .png }

    /// Whether ImageIO can encode this format on the current system.
    var nativelyEncodable: Bool {
        let supported = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        return supported.contains(typeIdentifier as String)
    }

    /// GIF is video-output only. It's force-applied to video inputs and never
    /// offered for still images.
    var isVideoOutput: Bool { self == .gif }

    /// Formats exposed in the picker. GIF is excluded — it's only produced
    /// from video inputs, which set the format internally.
    static var available: [OutputFormat] { allCases.filter { !$0.isVideoOutput } }
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

    /// Long-edge target in pixels. `0` means don't resize.
    var outputMaxEdge: Int {
        if object(forKey: SettingsKeys.outputMaxEdge) == nil {
            return SettingsKeys.defaultMaxEdge
        }
        return integer(forKey: SettingsKeys.outputMaxEdge)
    }

    /// Frames per second for video → GIF conversions.
    var outputGifFPS: Int {
        if object(forKey: SettingsKeys.outputGifFPS) == nil {
            return SettingsKeys.defaultGifFPS
        }
        return integer(forKey: SettingsKeys.outputGifFPS)
    }
}
