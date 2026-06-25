// App/Aignals/Sources/AboutView.swift
import SwiftUI
import AignalsCore

/// About window content (ADR-0802). Themed per the persisted selection
/// (ADR-0808/0810): the About window is its own Window scene without the shared
/// AppViewModel, so it reads the theme directly from a fresh ConfigStore.
///
/// The repository Link uses the real repo URL per OQ-82 —
/// `https://github.com/Jesse1211/Aignals`.
struct AboutView: View {
    private let style: ThemeStyle = {
        let paths = Paths()
        let theme = ConfigStore(paths: paths).config.theme
        return ThemeStyle.tokens(for: theme)
    }()

    var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14)
                .fill(AngularGradient(colors: [.red, .yellow, .green, .red], center: .center))
                .frame(width: 56, height: 56)
            Text("Aignals").font(.title2).bold()
            Text("Version \(version)").foregroundStyle(style.textSecondary)
            Text("Menu bar signal light for your AI coding agents.")
                .font(.callout).foregroundStyle(style.textSecondary)
                .multilineTextAlignment(.center)
            Link("github.com/Jesse1211/Aignals",
                 destination: URL(string: "https://github.com/Jesse1211/Aignals")!)
        }
        .padding(28)
        .frame(width: 320)
        .foregroundStyle(style.textPrimary)
        .background(aboutBackground)
    }

    @ViewBuilder
    private var aboutBackground: some View {
        if let material = style.panelMaterial {
            VisualEffectBackground(material: material, appearance: style.panelAppearance)
        } else {
            style.panelColor
        }
    }
}
