import SwiftUI
import AignalsCore

/// A list of saved quotes shown as a window from the dropdown's 📖 button.
/// Each row shows text + author + saved time and can be deleted. No session
/// coupling.
@MainActor
struct ProjectorView: View {
    @Bindable var vm: AppViewModel
    @Environment(\.dismissWindow) private var dismissWindow

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Saved Quotes").font(.headline)
                Spacer()
                Button("Done") { dismissWindow(id: "projector") }
            }
            .padding(12)
            Divider()

            if vm.savedQuotes.isEmpty {
                Text("No saved quotes yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                List {
                    ForEach(vm.savedQuotes, id: \.text) { q in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(q.text)
                            HStack {
                                if !q.author.isEmpty {
                                    Text("— \(q.author)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Self.dateFormat.string(from: q.savedAt))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .swipeActions {
                            Button(role: .destructive) {
                                vm.deleteSavedQuote(text: q.text)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .frame(width: 360, height: 420)
    }
}
