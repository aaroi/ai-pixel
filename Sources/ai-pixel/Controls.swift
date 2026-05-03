import SwiftUI

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

    private let segmentWidth: CGFloat = 64
    private let segmentHeight: CGFloat = 24

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
