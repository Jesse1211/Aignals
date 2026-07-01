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
                .task {
                    while !Task.isCancelled {
                        vm.fetchQuoteIfNeeded()
                        try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                    }
                }
        } label: {
            Image(nsImage: StatusIcon.image(for: vm.store.statusCounts, hasError: vm.store.hasError))
        }
        .menuBarExtraStyle(.window)

        Window("Aignals Settings", id: "settings") {
            SettingsView(vm: vm)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 540, height: 440)

        Window("Saved Quotes", id: "projector") {
            ProjectorView(vm: vm)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 360, height: 420)

        Window("Work Stats", id: "stat") {
            StatView(vm: vm)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 380, height: 460)
    }
}
