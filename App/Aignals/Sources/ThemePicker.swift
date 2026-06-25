// App/Aignals/Sources/ThemePicker.swift
import SwiftUI
import AignalsCore

/// The side pop-out theme card (ADR-0809): one row per theme with a live
/// swatch + name + a ✓ on the active one. Presented from MenuContent via a
/// `.popover` so macOS auto-picks the side and it never clips off-screen.
/// Selecting applies instantly (writes `vm.theme`) and the card STAYS OPEN so
/// the user can compare themes back-to-back.
@MainActor
struct ThemePicker: View {
    @Bindable var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Theme")
                .font(.caption2).fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)

            ForEach(Theme.allCases, id: \.self) { theme in
                Button {
                    vm.theme = theme            // applies instantly; card stays open
                } label: {
                    HStack(spacing: 10) {
                        ThemeSwatch(hexes: theme.swatchHexes)
                        Text(theme.displayName)
                            .font(.callout)
                        Spacer(minLength: 8)
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(.tint)
                            .opacity(vm.theme == theme ? 1 : 0)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(vm.theme == theme ? 0.10 : 0))
                )
            }
        }
        .padding(6)
        .frame(width: 208)
    }
}

/// A small rounded preview of a theme's palette: a horizontal gradient of its
/// `swatchHexes`.
struct ThemeSwatch: View {
    let hexes: [String]
    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(LinearGradient(
                colors: hexes.map { Color(hex: $0) },
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 26, height: 18)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.18)))
    }
}
