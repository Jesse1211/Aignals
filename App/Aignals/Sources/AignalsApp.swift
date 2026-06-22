import SwiftUI
import AignalsCore

/// App entry point.
///
/// Per ADR-0802 UI source files live under `App/Aignals/Sources/`. The menu bar
/// item label renders the aggregate status dot via `StatusIcon` (ADR-0803:
/// running→red, idle→green, error→gray ring, `isTemplate=false`), and the
/// dropdown is driven by `MenuContent` bound to the shared `AppViewModel`.
@main
@MainActor
struct AignalsApp: App {
    @State private var vm = AppViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(vm: vm)
        } label: {
            Image(nsImage: StatusIcon.image(for: vm.store.statusCounts, hasError: vm.store.hasError))
        }
        .menuBarExtraStyle(.window)

        Window("About Aignals", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}
