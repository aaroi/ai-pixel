import SwiftUI
import UniformTypeIdentifiers
import AppKit
import Combine

struct ContentView: View {
    @Environment(\.colorScheme) private var scheme
    @StateObject private var jobs = JobsModel()
    @State private var isDropTargeted = false
    @AppStorage(SettingsKeys.outputSuffix)  private var suffix: String  = SettingsKeys.defaultSuffix
    @AppStorage(SettingsKeys.outputFormat)  private var formatRaw: String = SettingsKeys.defaultFormat
    @AppStorage(SettingsKeys.outputQuality) private var quality: Double = SettingsKeys.defaultQuality
    @AppStorage(SettingsKeys.outputMaxEdge)     private var maxEdge: Int        = SettingsKeys.defaultMaxEdge
    @AppStorage(SettingsKeys.outputMaxEdgeMode) private var maxEdgeMode: String = SettingsKeys.defaultMaxEdgeMode

    var body: some View {
        ZStack(alignment: .top) {
            Palette.bg(scheme).ignoresSafeArea()

            VStack(spacing: 0) {
                // Reserve space for the title-bar / traffic-light zone so the
                // settings bar below can use the same leading padding (16) as
                // the rows and footer — everything left-aligns to the same edge.
                Color.clear.frame(height: 22)
                settingsBar
                Hairline()

                if jobs.list.isEmpty {
                    emptyState
                } else {
                    list
                }

                if !jobs.list.isEmpty {
                    Hairline()
                    footer
                }
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .overlay {
            if isDropTargeted {
                Rectangle()
                    .strokeBorder(Palette.borderStrong(scheme), lineWidth: 2)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openImagesRequested)) { _ in openPanel() }
        .onReceive(NotificationCenter.default.publisher(for: .saveAllRequested)) { _ in jobs.saveAll() }
        .onChange(of: formatRaw) { _ in jobs.reprocessAll() }
        .onChange(of: quality)   { _ in jobs.reprocessAll() }
        .onChange(of: maxEdge)   { _ in jobs.reprocessAll() }
        .onChange(of: suffix)    { _ in jobs.applyGlobalSuffix() }
    }

    private var format: OutputFormat {
        OutputFormat(rawValue: formatRaw) ?? .jpeg
    }

    /// Bridge between the dropdown's String selection and the Int-typed
    /// `maxEdge` + the mode flag. Picking a preset sets mode = "preset" and
    /// `maxEdge` to the matching int. Picking "Custom" flips mode = "custom"
    /// without changing `maxEdge` (so the numeric field starts from the
    /// currently-effective value).
    private var maxEdgeSelection: Binding<String> {
        Binding(
            get: { maxEdgeMode == "custom" ? "custom" : String(maxEdge) },
            set: { newValue in
                if newValue == "custom" {
                    maxEdgeMode = "custom"
                } else {
                    maxEdgeMode = "preset"
                    if let n = Int(newValue) { maxEdge = n }
                }
            }
        )
    }

    /// What the resize dropdown shows when closed.
    private var maxEdgeDisplayLabel: String {
        if maxEdgeMode == "custom" {
            return maxEdge > 0 ? "\(maxEdge) px" : "Custom"
        }
        switch maxEdge {
        case 0:    return "Off"
        case 1080: return "1080 px"
        case 1920: return "1920 px"
        default:   return "\(maxEdge) px"
        }
    }

    private static let intFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 0
        f.maximum = 10000
        f.allowsFloats = false
        return f
    }()

    // MARK: - Sections

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("Drop images")
                .font(Typography.systemLarge)
                .foregroundColor(Palette.fg(scheme))
            (Text("or ").font(Typography.systemTiny)
             + Text("⌘O").font(Typography.monoTiny)
             + Text(" to open · resized to ").font(Typography.systemTiny)
             + Text("1920px").font(Typography.monoTiny)
             + Text(" · saved as ").font(Typography.systemTiny)
             + Text("<name>\(suffix).\(format.fileExtension)").font(Typography.monoTiny))
                .foregroundColor(Palette.fgMuted(scheme))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { openPanel() }
        .cursorPointer()
    }

    private var settingsBar: some View {
        HStack(spacing: 22) {
            // Suffix
            HStack(spacing: 6) {
                Text("suffix")
                    .font(Typography.systemTiny)
                    .foregroundColor(Palette.fgMuted(scheme))
                    .fixedSize()
                TextField("", text: $suffix)
                    .textFieldStyle(.plain)
                    .font(Typography.monoSmall)
                    .foregroundColor(Palette.fg(scheme))
                    .padding(.horizontal, 6)
                    .frame(width: 110, height: 24)
                    .overlay(Rectangle().strokeBorder(Palette.border(scheme), lineWidth: 1))
            }

            // Format — grayscale dropdown
            GrayDropdown(
                selection: $formatRaw,
                options: OutputFormat.available.map { ($0.rawValue, $0.label) },
                width: 78
            )

            // Resize — dropdown for presets / Custom. Numeric input only
            // appears when Custom is selected.
            HStack(spacing: 6) {
                GrayDropdown(
                    selection: maxEdgeSelection,
                    options: [
                        ("1080",   "1080 px"),
                        ("1920",   "1920 px"),
                        ("0",      "Off"),
                        ("custom", "Custom…")
                    ],
                    displayLabel: maxEdgeDisplayLabel,
                    width: 92
                )
                if maxEdgeMode == "custom" {
                    HStack(spacing: 4) {
                        TextField("", value: $maxEdge, formatter: Self.intFormatter)
                            .textFieldStyle(.plain)
                            .font(Typography.monoSmall)
                            .foregroundColor(Palette.fg(scheme))
                            .multilineTextAlignment(.trailing)
                            .padding(.horizontal, 6)
                            .frame(width: 56, height: 24)
                            .overlay(Rectangle().strokeBorder(Palette.border(scheme), lineWidth: 1))
                        Text("px")
                            .font(Typography.systemTiny)
                            .foregroundColor(Palette.fgMuted(scheme))
                    }
                }
            }

            // Quality (lossy only)
            if format.isLossy {
                HStack(spacing: 8) {
                    Text("quality")
                        .font(Typography.systemTiny)
                        .foregroundColor(Palette.fgMuted(scheme))
                        .fixedSize()
                    GraySlider(value: $quality, range: 0.50...1.00)
                        .frame(width: 130)
                    Text("\(Int((quality * 100).rounded()))%")
                        .font(Typography.monoSmall)
                        .foregroundColor(Palette.fg(scheme))
                        .frame(width: 36, alignment: .trailing)
                    estimatedSavingsLabel
                        .fixedSize()
                }
            }

            Spacer(minLength: 16)

            if !jobs.list.isEmpty {
                Button(action: { jobs.clear() }) {
                    Text("Clear")
                        .font(Typography.systemSmall)
                        .foregroundColor(Palette.fgMuted(scheme))
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .cursorPointer()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(Palette.bg(scheme))
    }

    /// Average percent saved across loaded images (real measurements). When no
    /// images are loaded yet, falls back to a quality-based heuristic so the
    /// user sees the expected ballpark.
    private var estimatedSavingsLabel: some View {
        let measured = jobs.averagePercentSaved
        let pct = measured ?? heuristicSavings(quality: quality)
        let prefix = measured == nil ? "≈ " : "avg "
        return Text("\(prefix)−\(pct)%")
            .font(Typography.monoSmall)
            .foregroundColor(Palette.success(scheme))
    }

    /// Quality → expected percent reduction for typical 3000+px source PNGs
    /// resized to 1920px. Coarse but directionally correct.
    private func heuristicSavings(quality: Double) -> Int {
        switch quality {
        case 0.95...1.00: return 85
        case 0.85..<0.95: return 92
        case 0.75..<0.85: return 95
        case 0.60..<0.75: return 96
        default:          return 97
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(jobs.list) { job in
                    JobRow(job: job)
                        .environmentObject(jobs)
                    Hairline()
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            jobs.summaryText(scheme: scheme)
                .foregroundColor(Palette.fgMuted(scheme))
            Spacer()
            Button(action: { jobs.saveAll() }) {
                Text(jobs.allSaved ? "Saved" : "Save All")
                    .font(Typography.systemSmall)
                    .foregroundColor(jobs.canSave ? Palette.fg(scheme) : Palette.fgMuted(scheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(
                        Rectangle()
                            .strokeBorder(Palette.border(scheme), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!jobs.canSave)
            .cursorPointer()
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(Palette.bg(scheme))
    }

    // MARK: - Intake

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data = data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                // Reject anything that isn't a still image. ImageProcessor would
                // fail on these too, but bouncing them at the boundary keeps the
                // list clean.
                if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
                   !type.conforms(to: .image) {
                    return
                }
                Task { @MainActor in jobs.add(url: url) }
            }
        }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            for url in panel.urls {
                jobs.add(url: url)
            }
        }
    }
}

@MainActor
final class JobsModel: ObservableObject {
    @Published private(set) var list: [ImageJob] = []
    private var cancellables: [UUID: AnyCancellable] = [:]

    func add(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path),
              !list.contains(where: { $0.sourceURL == url }),
              let job = ImageJob(sourceURL: url) else { return }
        list.append(job)
        // Forward each child's change notifications so footer summary stays in sync.
        cancellables[job.id] = job.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        Task { await job.run() }
    }

    func clear() {
        list.removeAll()
        cancellables.removeAll()
    }

    /// Re-run processing on every job, including saved ones (saved jobs go back
    /// to .ready so the user can re-export with the new format / quality).
    func reprocessAll() {
        for job in list {
            Task { await job.run() }
        }
    }

    /// Apply the current global suffix to every job whose filename hasn't been
    /// manually edited. The previously-applied suffix is stripped from the end
    /// of the stem before the new one is appended, so changing the suffix
    /// replaces it instead of stacking.
    func applyGlobalSuffix() {
        let newSuffix = UserDefaults.standard.outputSuffix
        for job in list where !job.isCustomStem {
            var stem = job.outputStem
            let last = job.lastAppliedSuffix
            if !last.isEmpty && stem.hasSuffix(last) {
                stem = String(stem.dropLast(last.count))
            }
            job.outputStem = stem + newSuffix
            job.lastAppliedSuffix = newSuffix
        }
    }

    /// Average percent reduction across all images that have a measurement.
    /// Nil if no images are loaded or none are processed.
    var averagePercentSaved: Int? {
        let pcts = list.compactMap { $0.percentSaved }
        guard !pcts.isEmpty else { return nil }
        return pcts.reduce(0, +) / pcts.count
    }

    func saveAll() {
        for job in list {
            if case .ready = job.state { job.save() }
        }
    }

    /// Mixed-font footer summary: system font for the prose, mono for counts/bytes,
    /// green for the total bytes saved.
    func summaryText(scheme: ColorScheme) -> Text {
        let total = list.count
        let savedCount = list.filter { if case .saved = $0.state { return true } else { return false } }.count
        let readyCount = list.filter { if case .ready = $0.state { return true } else { return false } }.count
        let processingCount = list.filter { if case .processing = $0.state { return true } else { return false } }.count
        let totalSavedBytes = list.compactMap { $0.bytesSaved }.reduce(0, +)

        var t = Text("\(total)").font(Typography.monoSmall)
            + Text(" image\(total == 1 ? "" : "s")").font(Typography.systemSmall)
        if processingCount > 0 {
            t = t + Text(" · ").font(Typography.systemSmall)
                + Text("\(processingCount)").font(Typography.monoSmall)
                + Text(" processing").font(Typography.systemSmall)
        }
        if readyCount > 0 {
            t = t + Text(" · ").font(Typography.systemSmall)
                + Text("\(readyCount)").font(Typography.monoSmall)
                + Text(" ready").font(Typography.systemSmall)
        }
        if savedCount > 0 {
            t = t + Text(" · ").font(Typography.systemSmall)
                + Text("\(savedCount)").font(Typography.monoSmall)
                + Text(" saved").font(Typography.systemSmall)
        }
        if totalSavedBytes > 0 {
            t = t + Text("    ").font(Typography.systemSmall)
                + Text("−\(ByteFormat.short(totalSavedBytes))")
                    .font(Typography.monoSmall)
                    .foregroundColor(Palette.success(scheme))
        }
        return t
    }

    var canSave: Bool {
        list.contains { if case .ready = $0.state { return true } else { return false } }
    }

    var allSaved: Bool {
        !list.isEmpty && list.allSatisfy { if case .saved = $0.state { return true } else { return false } }
    }
}

struct JobRow: View {
    @ObservedObject var job: ImageJob
    @EnvironmentObject var jobs: JobsModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            sourceColumn
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("→")
                .font(Typography.monoLarge)
                .foregroundColor(Palette.fgMuted(scheme))

            outputColumn
                .frame(maxWidth: .infinity, alignment: .leading)

            actionButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var sourceColumn: some View {
        HStack(spacing: 12) {
            thumbnail(image: job.sourceThumbnail)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.sourceName)
                    .font(Typography.monoSmall)
                    .foregroundColor(Palette.fg(scheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(sourceLine)
                    .font(Typography.monoTiny)
                    .foregroundColor(Palette.fgMuted(scheme))
            }
        }
    }

    private var outputColumn: some View {
        HStack(spacing: 12) {
            thumbnail(image: job.outputThumbnail ?? job.sourceThumbnail, dimmed: job.outputThumbnail == nil)
            VStack(alignment: .leading, spacing: 3) {
                filenameField
                HStack(spacing: 6) {
                    Text(outputLine)
                        .font(Typography.monoTiny)
                        .foregroundColor(outputColor)
                    if let pct = job.percentSaved, pct > 0 {
                        Text("−\(pct)%")
                            .font(Typography.monoTiny)
                            .foregroundColor(Palette.success(scheme))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var filenameField: some View {
        if case .saved(let url, _) = job.state {
            Text(url.lastPathComponent)
                .font(Typography.monoSmall)
                .foregroundColor(Palette.fg(scheme))
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            HStack(spacing: 0) {
                TextField("", text: Binding(
                    get: { job.outputStem },
                    set: { newValue in
                        if newValue != job.outputStem {
                            job.outputStem = newValue
                            job.isCustomStem = true
                        }
                    }
                ))
                .textFieldStyle(.plain)
                .font(Typography.monoSmall)
                .foregroundColor(Palette.fg(scheme))
                .fixedSize(horizontal: true, vertical: false)
                Text(".\(currentExt)")
                    .font(Typography.monoSmall)
                    .foregroundColor(Palette.fgMuted(scheme))
            }
        }
    }

    private var currentExt: String {
        if case .ready(let p) = job.state { return p.format.fileExtension }
        return UserDefaults.standard.outputFormat.fileExtension
    }

    @ViewBuilder
    private func thumbnail(image: NSImage?, dimmed: Bool = false) -> some View {
        Group {
            if let nsimg = image {
                Image(nsImage: nsimg)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
                    .opacity(dimmed ? 0.35 : 1.0)
            } else {
                Rectangle().fill(Palette.border(scheme))
            }
        }
        .frame(width: 56, height: 56)
        .background(Palette.border(scheme))
        .overlay(Rectangle().strokeBorder(Palette.border(scheme), lineWidth: 1))
    }

    private var sourceLine: String {
        let ext = (job.sourceURL.pathExtension.uppercased())
        return "\(job.sourceWidth)×\(job.sourceHeight) \(ext) · \(ByteFormat.short(job.sourceBytes))"
    }

    private var outputLine: String {
        switch job.state {
        case .processing:
            return "resizing…"
        case .ready(let p):
            let q = p.format.isLossy ? " q=\(Int((UserDefaults.standard.outputQuality * 100).rounded()))" : ""
            return "\(p.width)×\(p.height) \(p.format.label)\(q) · \(ByteFormat.short(p.data.count))"
        case .saved(_, let p):
            return "saved · \(p.width)×\(p.height) \(p.format.label) · \(ByteFormat.short(p.data.count))"
        case .failed(let msg):
            return msg
        }
    }

    private var outputColor: Color {
        switch job.state {
        case .failed: return Color(hex: 0xC04040)
        case .saved: return Palette.fg(scheme)
        default: return Palette.fgMuted(scheme)
        }
    }

    private var actionButton: some View {
        // Fixed slot width so Save / Reveal / spinner / empty all sit in the
        // same horizontal space — switching between states never reflows the row.
        Group {
            switch job.state {
            case .ready:
                Button(action: { job.save() }) {
                    Text("Save")
                        .font(Typography.systemSmall)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(Rectangle().strokeBorder(Palette.border(scheme), lineWidth: 1))
                        .foregroundColor(Palette.fg(scheme))
                }
                .buttonStyle(.plain)
                .cursorPointer()
            case .saved(let url, _):
                Button(action: { NSWorkspace.shared.activateFileViewerSelecting([url]) }) {
                    Text("Reveal")
                        .font(Typography.systemSmall)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(Rectangle().strokeBorder(Palette.border(scheme), lineWidth: 1))
                        .foregroundColor(Palette.fgMuted(scheme))
                }
                .buttonStyle(.plain)
                .cursorPointer()
            case .processing:
                ProgressView().controlSize(.small).scaleEffect(0.7)
            case .failed:
                Color.clear
            }
        }
        .frame(width: 90, alignment: .trailing)
    }
}
