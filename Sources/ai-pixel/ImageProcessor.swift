import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import AppKit

struct ProcessedImage {
    let width: Int
    let height: Int
    let format: OutputFormat
    let data: Data
    let thumbnail: NSImage
}

enum ProcessingError: Error, LocalizedError {
    case unreadable
    case decodeFailed
    case encodeFailed(format: OutputFormat)
    case webpToolMissing

    var errorDescription: String? {
        switch self {
        case .unreadable: return "couldn't open"
        case .decodeFailed: return "couldn't decode"
        case .encodeFailed(let fmt): return "couldn't encode \(fmt.label)"
        case .webpToolMissing: return "webp requires `brew install webp`"
        }
    }
}

enum ImageProcessor {

    /// Long-edge target for LinkedIn — large enough to look good on retina,
    /// small enough that LinkedIn won't aggressively recompress.
    static let longEdge: CGFloat = 1920

    static func process(url: URL, format: OutputFormat, quality: Double) throws -> ProcessedImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ProcessingError.unreadable
        }
        guard let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw ProcessingError.decodeFailed
        }

        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let scale = min(longEdge / max(w, h), 1.0)
        let outW = Int((w * scale).rounded())
        let outH = Int((h * scale).rounded())

        // Render into a fresh sRGB context with high-quality interpolation.
        // PNG / WebP keep alpha; JPEG flattens.
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: UInt32 = format == .jpeg
            ? CGImageAlphaInfo.noneSkipLast.rawValue
            : CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw ProcessingError.encodeFailed(format: format)
        }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        guard let resized = ctx.makeImage() else { throw ProcessingError.encodeFailed(format: format) }

        // Encode in the chosen format. ImageIO covers JPEG/PNG natively;
        // WebP requires the `cwebp` external tool because macOS doesn't ship
        // a WebP encoder.
        let data: Data
        if format == .webp {
            data = try encodeWebP(cg: resized, quality: quality)
        } else {
            let mut = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(mut, format.typeIdentifier, 1, nil) else {
                throw ProcessingError.encodeFailed(format: format)
            }
            var opts: [CFString: Any] = [:]
            if format.isLossy {
                opts[kCGImageDestinationLossyCompressionQuality] = quality
            }
            CGImageDestinationAddImage(dest, resized, opts as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw ProcessingError.encodeFailed(format: format) }
            data = mut as Data
        }

        let thumb = NSImage(cgImage: resized, size: NSSize(width: outW, height: outH))

        return ProcessedImage(
            width: outW,
            height: outH,
            format: format,
            data: data,
            thumbnail: thumb
        )
    }

    /// Locate `cwebp` (from `brew install webp`) on PATH or known Homebrew prefixes.
    /// Cached after the first lookup.
    static let cwebpPath: String? = {
        let candidates = [
            "/opt/homebrew/bin/cwebp",   // Apple Silicon Homebrew
            "/usr/local/bin/cwebp",      // Intel Homebrew / system
            "/usr/bin/cwebp",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        return nil
    }()

    /// Encode a CGImage as WebP by writing a temp PNG and shelling out to
    /// `cwebp`. Returns the encoded bytes; throws `webpToolMissing` if the
    /// user hasn't installed it.
    private static func encodeWebP(cg: CGImage, quality: Double) throws -> Data {
        guard let cwebp = cwebpPath else { throw ProcessingError.webpToolMissing }

        let tmpDir = FileManager.default.temporaryDirectory
        let pngURL  = tmpDir.appendingPathComponent("aipixel-\(UUID().uuidString).png")
        let webpURL = tmpDir.appendingPathComponent("aipixel-\(UUID().uuidString).webp")
        defer {
            try? FileManager.default.removeItem(at: pngURL)
            try? FileManager.default.removeItem(at: webpURL)
        }

        // Write a lossless PNG first, then re-encode as WebP at the requested quality.
        let pngData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(pngData, UTType.png.identifier as CFString, 1, nil) else {
            throw ProcessingError.encodeFailed(format: .webp)
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { throw ProcessingError.encodeFailed(format: .webp) }
        try (pngData as Data).write(to: pngURL, options: .atomic)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: cwebp)
        task.arguments = [
            "-q", String(Int((quality * 100).rounded())),
            "-quiet",
            pngURL.path,
            "-o", webpURL.path
        ]
        let errPipe = Pipe()
        task.standardError = errPipe
        do {
            try task.run()
        } catch {
            throw ProcessingError.encodeFailed(format: .webp)
        }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw ProcessingError.encodeFailed(format: .webp)
        }
        return try Data(contentsOf: webpURL)
    }

    static func sourceDimensions(url: URL) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (w, h)
    }

    static func sourceThumbnail(url: URL, maxPx: Int = 96) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPx,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// Output URL: same directory as source, basename + configurable suffix +
    /// the current format's extension.
    static func outputURL(for source: URL, format: OutputFormat) -> URL {
        let suffix = UserDefaults.standard.outputSuffix
        let dir = source.deletingLastPathComponent()
        let stem = source.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent("\(stem)\(suffix).\(format.fileExtension)")
    }
}
