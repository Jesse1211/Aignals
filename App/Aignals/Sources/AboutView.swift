import SwiftUI

/// About window content.
///
/// Per ADR-0802 this view lives under `App/Aignals/Sources/` (the path already
/// wired into `project.yml`), NOT a separate `UI/` directory. The repository
/// Link uses the real repo URL per OQ-82 — `https://github.com/Jesse1211/Aignals`
/// — not the `YOUR-USERNAME` placeholder from the draft plan.
struct AboutView: View {
    var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aignals").font(.title2).bold()
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("Menu bar indicator for AI coding agent activity.")
            Link("github.com/Jesse1211/Aignals",
                 destination: URL(string: "https://github.com/Jesse1211/Aignals")!)
        }
        .padding(24)
        .frame(width: 360)
    }
}
