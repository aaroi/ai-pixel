import Foundation

/// Command-line interface for iso.pixel — same processing engine as the GUI,
/// invoked headlessly. Designed to be called from agents (Claude Code, scripts,
/// automation) without launching a window.
///
/// Usage:
///   iso-pixel [options] <file>...
///
/// Options:
///   --format <jpeg|png|webp>   output format (default: jpeg)
///   --quality <0-100|0-1>      quality for lossy formats (default: 95)
///   --suffix <str>             filename suffix (default: -compressed)
///   --output-dir <path>        output directory (default: same as input)
///   --json                     emit results as JSON lines (one per file)
///   --help, -h                 show this help
///
/// Exit codes: 0 success, 1 partial failure, 2 invalid arguments.
enum CLI {

    static func run(args: [String]) -> Int {
        var format: OutputFormat = .jpeg
        var formatExplicit = false
        var quality: Double = 0.95
        var suffix: String = "-compressed"
        var maxEdge: Int = SettingsKeys.defaultMaxEdge
        var fps: Int = SettingsKeys.defaultGifFPS
        var outputDir: URL? = nil
        var emitJSON = false
        var inputs: [URL] = []

        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--help", "-h":
                printHelp()
                return 0
            case "--format":
                i += 1
                guard i < args.count, let f = OutputFormat(rawValue: args[i].lowercased()), !f.isVideoOutput else {
                    fputs("error: --format requires jpeg|png|webp (video inputs always produce gif)\n", stderr)
                    return 2
                }
                format = f
                formatExplicit = true
            case "--quality":
                i += 1
                guard i < args.count, let q = Double(args[i]) else {
                    fputs("error: --quality requires a number (0-100 or 0-1)\n", stderr)
                    return 2
                }
                quality = q > 1 ? q / 100 : q
                quality = max(0, min(1, quality))
            case "--suffix":
                i += 1
                guard i < args.count else {
                    fputs("error: --suffix requires a value\n", stderr)
                    return 2
                }
                suffix = args[i]
            case "--max-edge":
                i += 1
                guard i < args.count, let n = Int(args[i]), n >= 0 else {
                    fputs("error: --max-edge requires a non-negative integer (0 = no resize)\n", stderr)
                    return 2
                }
                maxEdge = n
            case "--fps":
                i += 1
                guard i < args.count, let n = Int(args[i]), n > 0 else {
                    fputs("error: --fps requires a positive integer\n", stderr)
                    return 2
                }
                fps = n
            case "--output-dir":
                i += 1
                guard i < args.count else {
                    fputs("error: --output-dir requires a path\n", stderr)
                    return 2
                }
                outputDir = URL(fileURLWithPath: args[i])
            case "--json":
                emitJSON = true
            default:
                if a.hasPrefix("-") {
                    fputs("error: unknown flag \(a)\n", stderr)
                    return 2
                }
                inputs.append(URL(fileURLWithPath: a))
            }
            i += 1
        }

        if inputs.isEmpty {
            fputs("error: no input files. use `iso-pixel --help` for usage.\n", stderr)
            return 2
        }

        var anyFailures = false

        for input in inputs {
            let summary = compressOne(
                input: input,
                format: format,
                formatExplicit: formatExplicit,
                quality: quality,
                maxEdge: maxEdge,
                fps: fps,
                suffix: suffix,
                outputDir: outputDir
            )
            if !summary.ok { anyFailures = true }
            emit(summary, asJSON: emitJSON, isError: !summary.ok)
        }

        return anyFailures ? 1 : 0
    }

    // MARK: - Single-image pipeline

    private static func compressOne(
        input: URL,
        format: OutputFormat,
        formatExplicit: Bool,
        quality: Double,
        maxEdge: Int,
        fps: Int,
        suffix: String,
        outputDir: URL?
    ) -> Summary {
        let sourceBytes = (try? FileManager.default.attributesOfItem(atPath: input.path)[.size] as? Int) ?? 0
        let dir = outputDir ?? input.deletingLastPathComponent()
        let stem = input.deletingPathExtension().lastPathComponent
        // Video inputs always produce GIF, overriding --format for that file.
        let isVideo = VideoProcessor.isVideo(url: input)
        let effectiveFormat: OutputFormat = isVideo ? .gif : format
        if isVideo && formatExplicit && format != .gif {
            fputs("warning: --format \(format.rawValue) ignored for video input \(input.lastPathComponent) (always gif)\n", stderr)
        }
        let dest = dir.appendingPathComponent("\(stem)\(suffix).\(effectiveFormat.fileExtension)")

        guard FileManager.default.fileExists(atPath: input.path) else {
            return Summary(input: input, output: dest, ok: false, error: "file not found", sourceBytes: sourceBytes, outputBytes: 0)
        }

        do {
            let data: Data
            if isVideo {
                let processed = try VideoProcessor.process(
                    url: input,
                    quality: quality,
                    maxEdge: maxEdge,
                    fps: fps,
                    progress: nil
                )
                data = processed.data
            } else {
                let processed = try ImageProcessor.process(url: input, format: format, quality: quality, maxEdge: maxEdge)
                data = processed.data
            }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dest, options: .atomic)
            return Summary(
                input: input,
                output: dest,
                ok: true,
                error: nil,
                sourceBytes: sourceBytes,
                outputBytes: data.count
            )
        } catch {
            return Summary(
                input: input,
                output: dest,
                ok: false,
                error: error.localizedDescription,
                sourceBytes: sourceBytes,
                outputBytes: 0
            )
        }
    }

    // MARK: - Output

    private struct Summary {
        let input: URL
        let output: URL
        let ok: Bool
        let error: String?
        let sourceBytes: Int
        let outputBytes: Int

        var savedPercent: Int {
            guard ok, sourceBytes > 0 else { return 0 }
            let saved = max(0, sourceBytes - outputBytes)
            return Int(round(Double(saved) / Double(sourceBytes) * 100))
        }
    }

    private static func emit(_ s: Summary, asJSON: Bool, isError: Bool = false) {
        if asJSON {
            var obj: [String: Any] = [
                "ok": s.ok,
                "input": s.input.path,
                "source_bytes": s.sourceBytes,
                "output_bytes": s.outputBytes,
                "saved_percent": s.savedPercent
            ]
            if s.ok { obj["output"] = s.output.path }
            if let err = s.error { obj["error"] = err }
            if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
               let line = String(data: data, encoding: .utf8) {
                if isError { fputs(line + "\n", stderr) } else { print(line) }
            }
        } else {
            if s.ok {
                print("\(s.input.path) → \(s.output.path)  \(formatBytes(s.outputBytes))  −\(s.savedPercent)%")
            } else {
                fputs("FAIL: \(s.input.path): \(s.error ?? "unknown")\n", stderr)
            }
        }
    }

    private static func formatBytes(_ b: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useKB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(b))
    }

    private static func printHelp() {
        print("""
        iso.pixel — minimalist image & video compression for macOS

        usage: iso-pixel [options] <file>...

        options:
          --format <jpeg|png|webp>   output format for images (default: jpeg)
          --quality <0-100|0-1>      quality for lossy formats (default: 95)
          --max-edge <px>            resize so the long edge is this many px;
                                     0 = don't resize (default: 1920)
          --fps <n>                  frames per second for video → gif (default: 12)
          --suffix <str>             filename suffix (default: -compressed)
          --output-dir <path>        write outputs here (default: alongside source)
          --json                     emit results as JSON lines (one per file)
          --help, -h                 show this help

        notes:
          - aspect ratio is preserved when resizing.
          - video inputs (.mp4, .mov, …) always produce gif; --format is ignored.
          - webp requires `brew install webp`; gif requires `brew install ffmpeg`.
          - exit codes: 0 ok, 1 some files failed, 2 bad arguments.

        examples:
          iso-pixel poster.png
          iso-pixel --max-edge 1080 --format webp --quality 85 *.png
          iso-pixel --max-edge 0 --quality 80 photo.jpg     # compress, don't resize
          iso-pixel --fps 15 --max-edge 480 demo.mp4         # video → gif
          iso-pixel --suffix -li --output-dir ~/Desktop a.png b.jpg
          iso-pixel --json one.png two.png
        """)
    }
}
