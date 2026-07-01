import Foundation

/// Persists sealed work history to worklog.json, keyed by local day. Append
/// adds a segment to its day and keeps totalSeconds in sync. Load is
/// crash-safe (missing/malformed -> empty); writes are atomic. No session coupling.
public final class WorklogStore {
    private struct Envelope: Codable {
        var version: Int
        var days: [String: WorkDay]
    }

    private let paths: Paths
    private var days: [String: WorkDay]

    private static var decoder: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    public init(paths: Paths) {
        self.paths = paths
        if let data = try? Data(contentsOf: paths.worklogFile),
           let env = try? Self.decoder.decode(Envelope.self, from: data) {
            self.days = env.days
        } else {
            self.days = [:]
        }
    }

    public func append(_ sealed: SealedSegment) {
        var day = days[sealed.day] ?? WorkDay()
        day.segments.append(sealed.segment)
        day.totalSeconds += sealed.segment.seconds
        days[sealed.day] = day
        persist()
    }

    public func append(_ sealed: [SealedSegment]) {
        guard !sealed.isEmpty else { return }
        for s in sealed { append(s) }
    }

    public var daysNewestFirst: [(day: String, work: WorkDay)] {
        days.keys.sorted(by: >).map { ($0, days[$0]!) }
    }

    private func persist() {
        try? paths.ensureDirectories()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let tmp = paths.worklogFile.appendingPathExtension("tmp.\(UUID().uuidString)")
        if let data = try? enc.encode(Envelope(version: 1, days: days)) {
            try? data.write(to: tmp)
            _ = try? FileManager.default.replaceItemAt(paths.worklogFile, withItemAt: tmp)
        }
    }
}
