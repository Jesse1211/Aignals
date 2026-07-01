import SwiftUI
import AignalsCore

/// Read-only work-history window: a by-day list, expandable to per-segment
/// detail. Opened via openWindow(id: "stat"). No session coupling.
@MainActor
struct StatView: View {
    @Bindable var vm: AppViewModel
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var expanded: Set<String> = []

    private static let dayLabel: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d yyyy"; return f
    }()
    private static let dayParse: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let clockLabel: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    private func dayTitle(_ day: String) -> String {
        guard let d = Self.dayParse.date(from: day) else { return day }
        return Self.dayLabel.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Work Stats").font(.headline)
                Spacer()
                Button("Done") { dismissWindow(id: "stat") }
            }
            .padding(12)
            Divider()

            if vm.worklogDays.isEmpty {
                Text("No work logged yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(vm.worklogDays, id: \.day) { entry in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expanded.contains(entry.day) },
                                set: { on in
                                    if on { expanded.insert(entry.day) } else { expanded.remove(entry.day) }
                                }
                            )
                        ) {
                            ForEach(Array(entry.work.segments.enumerated()), id: \.offset) { _, seg in
                                HStack {
                                    Text("\(Self.clockLabel.string(from: seg.start))–\(Self.clockLabel.string(from: seg.end))")
                                        .font(.callout)
                                    Spacer()
                                    Text(WorktimeFormatter.human(seg.seconds))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } label: {
                            HStack {
                                Text(dayTitle(entry.day))
                                Spacer()
                                Text(WorktimeFormatter.human(entry.work.totalSeconds))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 380, height: 460)
    }
}
