import Foundation
import AVFoundation
import AppKit
import UniformTypeIdentifiers

/// Video → high-quality GIF conversion via ffmpeg's palettegen + paletteuse.
/// Mirrors the cwebp-style external-tool pattern in `ImageProcessor`.
enum VideoProcessor {

    /// True when the URL points at a movie/audiovisual file.
    static func isVideo(url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            // Fallback to extension sniffing for paths the file system can't classify.
            let ext = url.pathExtension.lowercased()
            return ["mp4", "mov", "m4v", "webm", "mkv", "avi", "gif"].contains(ext)
        }
        return type.conforms(to: .movie) || type.conforms(to: .audiovisualContent)
    }

    /// Locate `ffmpeg` (from `brew install ffmpeg`) on known Homebrew prefixes.
    /// Cached after the first lookup.
    static let ffmpegPath: String? = {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",   // Apple Silicon Homebrew
            "/usr/local/bin/ffmpeg",      // Intel Homebrew / system
            "/usr/bin/ffmpeg",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        return nil
    }()

    struct VideoMetadata {
        let width: Int
        let height: Int
        let durationSec: Double
        let nominalFPS: Double
    }

    static func sourceMetadata(url: URL) -> VideoMetadata? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }
        // Apply the track's preferred transform so portrait video reports portrait dims.
        let size = track.naturalSize.applying(track.preferredTransform)
        let w = abs(size.width)
        let h = abs(size.height)
        let durationSec = CMTimeGetSeconds(asset.duration)
        let fps = Double(track.nominalFrameRate)
        return VideoMetadata(
            width: Int(w.rounded()),
            height: Int(h.rounded()),
            durationSec: durationSec.isFinite ? durationSec : 0,
            nominalFPS: fps.isFinite ? fps : 0
        )
    }

    /// Grab a frame ~0.5s in (or 10% through, whichever is sooner) for the list thumbnail.
    /// Avoids the all-black intro frame that some captures start with.
    static func sourceThumbnail(url: URL, maxPx: Int = 96) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxPx * 2, height: maxPx * 2)
        let durationSec = CMTimeGetSeconds(asset.duration)
        let targetSec = durationSec.isFinite && durationSec > 0
            ? min(0.5, durationSec * 0.1)
            : 0.0
        let time = CMTime(seconds: targetSec, preferredTimescale: 600)
        do {
            let cg = try gen.copyCGImage(at: time, actualTime: nil)
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        } catch {
            return nil
        }
    }

    /// Convert a video to a GIF. `progress` receives values in [0, 1] from a
    /// background thread — caller is responsible for hopping to MainActor.
    static func process(
        url: URL,
        quality: Double,
        maxEdge: Int,
        fps: Int,
        progress: ((Double) -> Void)? = nil
    ) throws -> ProcessedImage {
        guard let ffmpeg = ffmpegPath else { throw ProcessingError.ffmpegToolMissing }
        guard let meta = sourceMetadata(url: url) else { throw ProcessingError.decodeFailed }

        // Never upscale: clamp fps and long-edge to source values.
        let sourceFPS = meta.nominalFPS > 0 ? meta.nominalFPS : 30
        let effectiveFPS = max(1, min(fps, Int(sourceFPS.rounded())))
        let sourceLongEdge = max(meta.width, meta.height)
        let effectiveLongEdge = (maxEdge <= 0) ? sourceLongEdge : min(maxEdge, sourceLongEdge)
        let isPortrait = meta.height > meta.width

        // `-2` rounds the computed dimension to the nearest even number, which
        // palette filters require. For portrait video, target the height axis
        // so `maxEdge` keeps its "long edge" meaning.
        let scaleClause: String
        if maxEdge <= 0 || effectiveLongEdge == sourceLongEdge {
            scaleClause = ""
        } else if isPortrait {
            scaleClause = ",scale=-2:\(effectiveLongEdge):flags=lanczos"
        } else {
            scaleClause = ",scale=\(effectiveLongEdge):-2:flags=lanczos"
        }

        // Quality slider → dither + palette size. Larger palette + better dither
        // = bigger file but smoother gradients. The low end drops dither
        // entirely and shrinks the palette aggressively to chase tiny outputs.
        let dither: String
        let maxColors: Int
        switch quality {
        case 0.85...:
            dither = "sierra2_4a"
            maxColors = 256
        case 0.65..<0.85:
            dither = "bayer:bayer_scale=3"
            maxColors = 192
        case 0.45..<0.65:
            dither = "bayer:bayer_scale=5"
            maxColors = 128
        case 0.25..<0.45:
            dither = "bayer:bayer_scale=5"
            maxColors = 64
        default:
            dither = "none"
            maxColors = 32
        }

        // Single-pass palette graph: split, generate palette on one branch,
        // apply it on the other. `stats_mode=diff` weights by frame-to-frame
        // changes — better for video than `full`.
        let filter = "fps=\(effectiveFPS)\(scaleClause),split [a][b];"
            + "[a] palettegen=max_colors=\(maxColors):stats_mode=diff [p];"
            + "[b][p] paletteuse=dither=\(dither)"

        let tmpDir = FileManager.default.temporaryDirectory
        let outURL = tmpDir.appendingPathComponent("isopixel-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: outURL) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: ffmpeg)
        task.arguments = [
            "-nostdin",
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-i", url.path,
            "-vf", filter,
            "-loop", "0",
            "-progress", "pipe:1",
            outURL.path
        ]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        // Parse ffmpeg's `out_time_us=<microseconds>` lines into a 0..1 ratio.
        if let progress = progress, meta.durationSec > 0 {
            let totalUs = meta.durationSec * 1_000_000
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                for line in text.split(separator: "\n") {
                    if line.hasPrefix("out_time_us="),
                       let us = Double(line.dropFirst("out_time_us=".count)) {
                        progress(min(1.0, max(0, us / totalUs)))
                    } else if line == "progress=end" {
                        progress(1.0)
                    }
                }
            }
        } else {
            // Drain so the pipe buffer doesn't fill and stall ffmpeg.
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                _ = handle.availableData
            }
        }

        var stderrData = Data()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let d = handle.availableData
            if !d.isEmpty { stderrData.append(d) }
        }

        do {
            try task.run()
        } catch {
            throw ProcessingError.ffmpegFailed(message: error.localizedDescription)
        }
        task.waitUntilExit()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        guard task.terminationStatus == 0 else {
            let raw = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let msg = raw.isEmpty ? "exit \(task.terminationStatus)" : raw
            throw ProcessingError.ffmpegFailed(message: msg)
        }

        let data = try Data(contentsOf: outURL)
        // NSImage decodes GIFs natively; the first frame is fine as a thumbnail.
        let thumb = NSImage(data: data) ?? sourceThumbnail(url: url) ?? NSImage()

        // Compute output dimensions for the row's "WxH" label.
        let outW: Int
        let outH: Int
        if scaleClause.isEmpty {
            outW = meta.width
            outH = meta.height
        } else if isPortrait {
            let scale = Double(effectiveLongEdge) / Double(meta.height)
            outW = max(2, Int((Double(meta.width) * scale).rounded() / 2) * 2)
            outH = effectiveLongEdge
        } else {
            let scale = Double(effectiveLongEdge) / Double(meta.width)
            outW = effectiveLongEdge
            outH = max(2, Int((Double(meta.height) * scale).rounded() / 2) * 2)
        }

        return ProcessedImage(
            width: outW,
            height: outH,
            format: .gif,
            data: data,
            thumbnail: thumb
        )
    }
}
