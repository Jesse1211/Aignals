import SwiftUI

@main
struct AignalsApp: App {
    var body: some Scene {
        MenuBarExtra("Aignals", systemImage: "circle.fill") {
            Text("Hello from Aignals")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }
}
