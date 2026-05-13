import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 1pt horizontal rule in the palette's border color. Replaces SwiftUI's
/// `Divider`, which uses the system separator (darker than our gray-200).
struct Hairline: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Rectangle()
            .fill(Palette.border(scheme))
            .frame(height: 1)
    }
}

/// Minimal grayscale segmented control. The system Picker(.segmented) uses the
/// accent color for the selected pill — that doesn't match our palette, so this
/// reimplementation does it in pure grayscale.
///
/// Each segment is pinned to a fixed `width × height` so toggling selection
/// can't shift neighbours by a pixel.
struct GraySegmented: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var selection: String
    let options: [(value: String, label: String)]
    var segmentWidth: CGFloat = 56
    var segmentHeight: CGFloat = 24

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                let selected = opt.value == selection
                Button(action: { selection = opt.value }) {
                    ZStack {
                        Rectangle()
                            .fill(selected ? Palette.selection(scheme) : Color.clear)
                        Text(opt.label)
                            .font(Typography.systemTiny)
                            .lineLimit(1)
                            .foregroundColor(selected ? Palette.fg(scheme) : Palette.fgMuted(scheme))
                    }
                    .frame(width: segmentWidth, height: segmentHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .cursorPointer()
                if idx != options.count - 1 {
                    Rectangle()
                        .fill(Palette.border(scheme))
                        .frame(width: 1, height: segmentHeight)
                }
            }
        }
        .overlay(Rectangle().strokeBorder(Palette.border(scheme), lineWidth: 1))
    }
}

/// Minimal grayscale dropdown. Wraps `Menu` with a custom flat-bordered label
/// so it visually matches the TextField next to it. The label always shows
/// the current selection's label (or, for free-form values like a custom
/// resize, whatever caller passes via `displayLabel`).
struct GrayDropdown: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var selection: String
    let options: [(value: String, label: String)]
    /// What to render in the closed-state label. Defaults to the matching
    /// option's label, falling back to the raw selection string.
    var displayLabel: String? = nil
    var width: CGFloat = 78

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                Button(action: { selection = opt.value }) {
                    if opt.value == selection {
                        Label(opt.label, systemImage: "checkmark")
                    } else {
                        Text(opt.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(displayLabel ?? optionLabel(for: selection) ?? selection)
                    .font(Typography.systemTiny)
                    .foregroundColor(Palette.fg(scheme))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("▾")
                    .font(.system(size: 9))
                    .foregroundColor(Palette.fgMuted(scheme))
            }
            .padding(.horizontal, 10)
            .frame(width: width, height: 24)
            .background(Palette.bg(scheme))
            .overlay(Rectangle().strokeBorder(Palette.border(scheme), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .cursorPointer()
    }

    private func optionLabel(for value: String) -> String? {
        options.first(where: { $0.value == value })?.label
    }
}

/// Chrome-style downloads button: opens a dropdown of the most recent image
/// files in ~/Downloads. Picking one calls `onPick`, which the parent wires to
/// `jobs.add(url:)` to start compression immediately.
struct DownloadsMenuButton: View {
    @Environment(\.colorScheme) private var scheme
    let onPick: (URL) -> Void

    // Bumped on app re-activation so the menu reflects newly-downloaded files
    // without needing the user to interact with anything else first.
    @State private var version = 0

    var body: some View {
        Menu {
            let items = Self.recentDownloadImages()
            if items.isEmpty {
                Text("No recent images in Downloads")
            } else {
                ForEach(items, id: \.self) { url in
                    Button(action: { onPick(url) }) {
                        Text(url.lastPathComponent)
                    }
                }
                Divider()
                Button("Open Downloads…") {
                    if let dir = Self.downloadsURL() {
                        NSWorkspace.shared.open(dir)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.down.to.line")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Palette.fg(scheme))
                .frame(width: 28, height: 24)
                .background(Palette.bg(scheme))
                .overlay(Rectangle().strokeBorder(Palette.border(scheme), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .cursorPointer()
        .help("Recent downloads")
        .id(version)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            version &+= 1
        }
    }

    static func downloadsURL() -> URL? {
        try? FileManager.default.url(
            for: .downloadsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
    }

    /// Most-recently-modified image files in ~/Downloads, newest first.
    /// Walks only the top level — recursing into subfolders would surprise users
    /// who keep large archives in there.
    static func recentDownloadImages(limit: Int = 10) -> [URL] {
        guard let dir = downloadsURL() else { return [] }
        let keys: [URLResourceKey] = [.contentTypeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }

        let images: [(URL, Date)] = contents.compactMap { url in
            let v = try? url.resourceValues(forKeys: Set(keys))
            guard v?.isRegularFile == true,
                  v?.contentType?.conforms(to: .image) == true else { return nil }
            return (url, v?.contentModificationDate ?? .distantPast)
        }
        return images
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }
}

/// Minimal grayscale slider — flat track, square thumb, no system blue.
struct GraySlider: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var value: Double
    let range: ClosedRange<Double>

    private let trackHeight: CGFloat = 2
    private let thumbSize: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let pct = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let x = CGFloat(pct) * (w - thumbSize)

            ZStack(alignment: .leading) {
                // Full track
                Rectangle()
                    .fill(Palette.border(scheme))
                    .frame(height: trackHeight)

                // Filled portion
                Rectangle()
                    .fill(Palette.borderStrong(scheme))
                    .frame(width: x + thumbSize / 2, height: trackHeight)

                // Thumb
                Rectangle()
                    .fill(Palette.fg(scheme))
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: x)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                let clamped = max(0, min(w - thumbSize, drag.location.x - thumbSize / 2))
                                let newPct = clamped / (w - thumbSize)
                                value = range.lowerBound + Double(newPct) * (range.upperBound - range.lowerBound)
                            }
                    )
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
        }
        .frame(height: thumbSize)
    }
}
