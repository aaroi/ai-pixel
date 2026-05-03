import SwiftUI
import AppKit

/// Push/pop the pointing-hand cursor while hovering. Use on any clickable view.
extension View {
    func cursorPointer() -> some View {
        self.onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
