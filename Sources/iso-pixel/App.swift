import SwiftUI

struct IsoPixelApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 860, minHeight: 360)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { NotificationCenter.default.post(name: .openImagesRequested, object: nil) }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .saveItem) {
                Button("Save All") { NotificationCenter.default.post(name: .saveAllRequested, object: nil) }
                    .keyboardShortcut("s", modifiers: .command)
            }
        }

    }
}

extension Notification.Name {
    static let openImagesRequested = Notification.Name("openImagesRequested")
    static let saveAllRequested = Notification.Name("saveAllRequested")
}
