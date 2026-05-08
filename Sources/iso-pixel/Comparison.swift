import SwiftUI
import AppKit

/// Squoosh-style before/after comparison overlay. Shows the source image and
/// the processed image stacked, with a draggable vertical split bar; left of
/// the bar is "before", right is "after". Press ESC or click the close button
/// to dismiss.
struct ComparisonView: View {
    let beforeImage: NSImage
    let afterImage: NSImage
    let beforeCaption: String
    let afterCaption: String
    let onClose: () -> Void

    @State private var splitFraction: CGFloat = 0.5

    var body: some View {
        ZStack {
            // Dim full-window backdrop. Tapping anywhere outside the image
            // area also closes (in addition to ESC and the X button).
            Color.black
                .opacity(0.96)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            GeometryReader { geo in
                let imageFrame = aspectFitFrame(
                    container: geo.size,
                    image: beforeImage.size
                )
                let splitX = imageFrame.minX + imageFrame.width * splitFraction

                ZStack(alignment: .topLeading) {
                    // BEFORE — full image
                    Image(nsImage: beforeImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)

                    // AFTER — clipped to the right of the split
                    Image(nsImage: afterImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .mask(
                            HStack(spacing: 0) {
                                Color.clear.frame(width: splitX)
                                Color.black
                            }
                        )

                    // Split line
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: imageFrame.height)
                        .position(x: splitX, y: imageFrame.midY)

                    // Drag handle
                    Circle()
                        .fill(Color.white)
                        .frame(width: 28, height: 28)
                        .overlay(
                            HStack(spacing: 2) {
                                Text("◂").foregroundColor(.black)
                                Text("▸").foregroundColor(.black)
                            }
                            .font(.system(size: 10, weight: .bold))
                        )
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                        .position(x: splitX, y: imageFrame.midY)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let raw = value.location.x - imageFrame.minX
                                    splitFraction = max(0, min(1, raw / imageFrame.width))
                                }
                        )
                        .cursorPointer()

                    // Captions
                    Text(beforeCaption)
                        .font(Typography.monoTiny)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.5))
                        .position(x: imageFrame.minX + 80, y: imageFrame.minY + 18)

                    Text(afterCaption)
                        .font(Typography.monoTiny)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.5))
                        .position(x: imageFrame.maxX - 80, y: imageFrame.minY + 18)
                }
                // Capture taps inside the image area so they don't dismiss the
                // overlay (the backdrop tap-to-close still works outside).
                .contentShape(Rectangle())
                .onTapGesture { /* swallow */ }
            }

            // Close button — top-right
            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Text("✕")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .cursorPointer()
                    .padding(16)
                }
                Spacer()
            }
        }
        .onExitCommand { onClose() }
    }

    /// Compute the rect the image actually occupies inside `container` under
    /// `.fit` aspect ratio, so we can position the split bar precisely on top.
    private func aspectFitFrame(container: CGSize, image: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / image.width, container.height / image.height)
        let w = image.width * scale
        let h = image.height * scale
        return CGRect(
            x: (container.width - w) / 2,
            y: (container.height - h) / 2,
            width: w, height: h
        )
    }
}
