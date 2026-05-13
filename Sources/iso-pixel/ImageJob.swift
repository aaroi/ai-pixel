import Foundation
import AppKit
import SwiftUI

@MainActor
final class ImageJob: ObservableObject, Identifiable {
    let id = UUID()
    let sourceURL: URL
    let sourceName: String
    let sourceStem: String
    let sourceBytes: Int
    let sourceWidth: Int
    let sourceHeight: Int
    let sourceThumbnail: NSImage?
    /// True when the source is a video — routes processing through ffmpeg and
    /// forces GIF output.
    let isVideo: Bool

    /// Editable filename stem (without extension). Initialized from the global
    /// suffix at import time; the user can rewrite it per-row before saving.
    /// Once the user has typed in the field, `isCustomStem` flips to true and
    /// global suffix changes will no longer overwrite this value.
    @Published var outputStem: String
    @Published var isCustomStem: Bool = false

    /// The suffix currently embedded at the end of `outputStem`. Tracked so
    /// that when the user changes the global suffix, we can strip the old one
    /// before appending the new one (instead of stacking them).
    var lastAppliedSuffix: String

    enum State {
        case processing
        case ready(processed: ProcessedImage)
        case saved(at: URL, processed: ProcessedImage)
        case failed(message: String)
    }

    @Published var state: State = .processing
    /// 0..1 progress for long video encodes. Nil for image jobs.
    @Published var processingProgress: Double? = nil

    init?(sourceURL: URL) {
        let attrs = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)) ?? [:]
        let bytes = (attrs[.size] as? NSNumber)?.intValue ?? 0
        let isVideo = VideoProcessor.isVideo(url: sourceURL)
        let width: Int
        let height: Int
        let thumb: NSImage?
        if isVideo {
            guard let meta = VideoProcessor.sourceMetadata(url: sourceURL) else { return nil }
            width = meta.width
            height = meta.height
            thumb = VideoProcessor.sourceThumbnail(url: sourceURL)
        } else {
            guard let dims = ImageProcessor.sourceDimensions(url: sourceURL) else { return nil }
            width = dims.0
            height = dims.1
            thumb = ImageProcessor.sourceThumbnail(url: sourceURL)
        }
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let suffix = UserDefaults.standard.outputSuffix
        self.sourceURL = sourceURL
        self.sourceName = sourceURL.lastPathComponent
        self.sourceStem = stem
        self.sourceBytes = bytes
        self.sourceWidth = width
        self.sourceHeight = height
        self.sourceThumbnail = thumb
        self.isVideo = isVideo
        // If the source filename already ends with the current global suffix
        // (re-import of a previously saved output), treat the suffix as already
        // applied so we don't stack it.
        if !suffix.isEmpty && stem.hasSuffix(suffix) {
            self.outputStem = stem
        } else {
            self.outputStem = "\(stem)\(suffix)"
        }
        self.lastAppliedSuffix = suffix
    }

    func run() async {
        let url = sourceURL
        let quality = UserDefaults.standard.outputQuality
        let maxEdge = UserDefaults.standard.outputMaxEdge
        let isVideo = self.isVideo
        // Video inputs always produce GIF regardless of the global format picker.
        let format: OutputFormat = isVideo ? .gif : UserDefaults.standard.outputFormat
        let fps = UserDefaults.standard.outputGifFPS
        // First run shows a spinner. Re-runs (triggered by quality / format
        // changes) keep the current ready/saved data visible so the row
        // doesn't flash a spinner on every slider tick.
        let isFirstRun: Bool = {
            switch state {
            case .ready, .saved: return false
            default: return true
            }
        }()
        if isFirstRun { self.state = .processing }
        self.processingProgress = isVideo ? 0 : nil
        do {
            let processed: ProcessedImage
            if isVideo {
                processed = try await Task.detached(priority: .userInitiated) {
                    try VideoProcessor.process(
                        url: url,
                        quality: quality,
                        maxEdge: maxEdge,
                        fps: fps,
                        progress: { value in
                            Task { @MainActor [weak self] in
                                self?.processingProgress = value
                            }
                        }
                    )
                }.value
            } else {
                processed = try await Task.detached(priority: .userInitiated) {
                    try ImageProcessor.process(url: url, format: format, quality: quality, maxEdge: maxEdge)
                }.value
            }
            self.state = .ready(processed: processed)
            self.processingProgress = nil
        } catch {
            self.state = .failed(message: error.localizedDescription)
            self.processingProgress = nil
        }
    }

    func save() {
        guard case .ready(let processed) = state else { return }
        let dir = sourceURL.deletingLastPathComponent()
        // If the user cleared the filename field, fall back to the source stem
        // (no suffix) — empty input means "save as-is".
        let rawStem = outputStem.isEmpty ? sourceStem : outputStem
        // Strip path separators and parent-directory tokens so the output stays
        // alongside the source file even if the user types something unusual.
        let stem = rawStem
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "..", with: "_")
        let dest = dir.appendingPathComponent("\(stem).\(processed.format.fileExtension)")
        do {
            try processed.data.write(to: dest, options: .atomic)
            self.state = .saved(at: dest, processed: processed)
        } catch {
            self.state = .failed(message: "save failed: \(error.localizedDescription)")
        }
    }

    /// Write the processed bytes to the general pasteboard. Always writes a
    /// TIFF fallback alongside the native-format bytes — most editors / chat
    /// apps only sniff for `public.tiff` or `public.png` on paste, and WebP in
    /// particular gets ignored without it.
    @discardableResult
    func copyToPasteboard() -> Bool {
        let processed: ProcessedImage
        switch state {
        case .ready(let p), .saved(_, let p): processed = p
        default: return false
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        let nativeType = NSPasteboard.PasteboardType(processed.format.typeIdentifier as String)
        item.setData(processed.data, forType: nativeType)
        if let tiff = processed.thumbnail.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        return pb.writeObjects([item])
    }

    var outputBytes: Int? {
        switch state {
        case .ready(let p), .saved(_, let p): return p.data.count
        default: return nil
        }
    }

    /// Encoded bytes of the processed image (whatever format it was rendered
    /// in). Used to construct an NSImage for the comparison overlay.
    var outputData: Data? {
        switch state {
        case .ready(let p), .saved(_, let p): return p.data
        default: return nil
        }
    }

    /// Bytes saved vs source. Nil while processing.
    var bytesSaved: Int? {
        guard let out = outputBytes, sourceBytes > 0 else { return nil }
        return max(0, sourceBytes - out)
    }

    /// Percent reduction (0–100). Nil while processing.
    var percentSaved: Int? {
        guard let saved = bytesSaved, sourceBytes > 0 else { return nil }
        return Int(round(Double(saved) / Double(sourceBytes) * 100))
    }

    var outputDimensions: (Int, Int)? {
        switch state {
        case .ready(let p), .saved(_, let p): return (p.width, p.height)
        default: return nil
        }
    }

    var outputThumbnail: NSImage? {
        switch state {
        case .ready(let p), .saved(_, let p): return p.thumbnail
        default: return nil
        }
    }
}

enum ByteFormat {
    static func short(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useKB]
        f.countStyle = .file
        f.zeroPadsFractionDigits = false
        return f.string(fromByteCount: Int64(bytes))
    }
}
