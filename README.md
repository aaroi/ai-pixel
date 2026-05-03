<p align="center">
  <img src="assets/icon.png" width="160" alt="ai.pixel icon" />
</p>

# ai.pixel

**The minimalistic image compression tool for macOS.**

Drop images, get LinkedIn-ready exports — resized to 1920px on the long edge,
saved as JPEG (or PNG / AVIF) with quality you control. No cloud, no telemetry,
no AI (despite the name — that's for later). Just a small grayscale window that
does one thing well.

Built on SwiftUI + ImageIO. The shipped `.app` is around 500 KB.

---

## Highlights

- **Drag & drop, or `⌘O`.** Multi-image at once. Each row processes in parallel.
- **Live re-encoding.** Pull the quality slider and every loaded image
  re-compresses on the fly. The per-row size and `−X%` saved chip update
  immediately so you can dial in the trade-off.
- **Three formats.** JPEG (universal), PNG (lossless), WebP (smaller than JPEG
  at the same visual quality). JPEG and PNG use ImageIO directly; WebP shells
  out to `cwebp` (`brew install webp`) since macOS doesn't ship a WebP encoder.
- **Editable filename per row.** Default is `<source-stem><suffix>.<ext>`.
  Click the filename to override it for one image without touching the global
  suffix.
- **Configurable suffix.** Type your preferred suffix into the home-page
  settings strip. Changing it retroactively renames every loaded image whose
  filename you haven't manually customized.
- **Real measurements, not advertising.** The savings shown next to each
  image are the actual bytes saved, not an estimate.
- **Grayscale UI, light/dark/auto.** No blue tints, no system-color glare.
  Selective monospace — used for filenames, dimensions, and byte counts;
  system font for everything else.
- **Save All, or per-row Save.** Saved files land in the source directory
  alongside the original. After save, click *Reveal* to jump to it in Finder.

## Command-line interface

The same binary runs headlessly when invoked with file arguments — no window,
no Dock icon, just compress and exit. This is what makes ai.pixel scriptable
from agents (Claude Code, shell scripts, automations).

```bash
# Path to the binary inside the .app bundle
ai-pixel=/Applications/ai.pixel.app/Contents/MacOS/ai-pixel

# Optional: drop into your PATH so you can just type `ai-pixel`
ln -sf "$ai-pixel" /usr/local/bin/ai-pixel

# Examples
ai-pixel poster.png                                     # → poster-compressed.jpg
ai-pixel --format webp --quality 85 *.png               # batch, WebP at q=85
ai-pixel --suffix -li --output-dir ~/Desktop a.png b.jpg
ai-pixel --json one.png two.png                         # one JSON object per line
```

### Flags

| Flag | Default | Notes |
|---|---|---|
| `--format <jpeg\|png\|webp>` | `jpeg` | WebP requires `brew install webp` |
| `--quality <0-100\|0-1>` | `95` | Ignored for PNG (lossless) |
| `--max-edge <px>` | `1920` | Resize so the long edge is N pixels. `0` = don't resize |
| `--suffix <str>` | `-compressed` | Appended to source basename |
| `--output-dir <path>` | source dir | Created if missing |
| `--json` | off | Emit one JSON object per file (machine-readable) |
| `--help`, `-h` | | Print help and exit |

Exit codes: `0` all succeeded, `1` some files failed, `2` invalid arguments.

### Calling from agents

JSON mode is designed for parsing. Each input file produces one line:

```json
{"input":"/path/in.png","ok":true,"output":"/path/in-compressed.jpg","source_bytes":6503556,"output_bytes":571840,"saved_percent":91}
```

Failed entries appear on **stderr**, also as JSON objects, with `"ok":false`
and an `"error"` field. So an agent can `jq` over stdout for successes, stderr
for failures, and still trust the exit code for the binary go/no-go signal.

No window opens during a CLI run; no Dock icon appears. Useful for batch jobs
or background automation. The GUI mode is reached by opening the `.app`
bundle from Finder, `open`, or any launcher that doesn't pass file arguments.

## What it does, technically

- Decodes the source via `CGImageSource`.
- Resizes by drawing into a fresh sRGB `CGContext` with high-quality
  interpolation. Long-edge target: 1920 px (preserving aspect ratio).
- Encodes via `CGImageDestination` to the chosen format. Quality flag is
  applied for lossy formats only; PNG ignores it.
- Output goes to `<source-dir>/<stem><suffix>.<ext>`, atomic write.

## Build from source

**Requires:** macOS 13+ and Xcode command-line tools (for `swift`). No external
package dependencies.

```bash
git clone https://github.com/aaroi/ai-pixel.git
cd ai-pixel
./build.sh                  # default: release
open build/ai.pixel.app     # try it
```

To install:

```bash
cp -R build/ai.pixel.app /Applications/
```

The build script ad-hoc codesigns the bundle so Gatekeeper won't quarantine it
on first launch on the same machine. For distribution to other Macs you'd want
a Developer ID Application certificate and notarization — out of scope here.

### Project layout

```
ai-pixel/
├── Package.swift              # SPM executable target, macOS 13+
├── Sources/ai-pixel/
│   ├── App.swift              # @main scene + menu commands
│   ├── ContentView.swift      # main window, drop zone, list, footer
│   ├── ImageJob.swift         # per-image state machine + ObservableObject
│   ├── ImageProcessor.swift   # resize + encode via ImageIO
│   ├── Settings.swift         # AppStorage keys + OutputFormat enum
│   ├── Controls.swift         # GraySegmented + GraySlider (custom grayscale)
│   └── Theme.swift            # palette + typography tokens
├── Resources/Info.plist
└── build.sh                   # swift build → assemble .app → ad-hoc sign
```

## Privacy

ai.pixel does not connect to the network. There are no analytics, no crash
reporters, no auto-updaters, no remote feature flags. Your images are read from
disk, processed in memory, and written back to disk — nothing leaves the
machine.

The only state persisted between launches is your settings (suffix, format,
quality), stored locally in `UserDefaults`.

## License

MIT — see [LICENSE](LICENSE).
