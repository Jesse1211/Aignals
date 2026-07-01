import Foundation

/// Persists the volatile stopwatch running state to stopwatch-state.json.
/// Load is crash-safe (missing/malformed -> .idle); writes are atomic. No
/// session coupling.
public final class StopwatchStateStore {
    private let paths: Paths
    public private(set) var snapshot: StopwatchSnapshot

    private static var decoder: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    public init(paths: Paths) {
        self.paths = paths
        if let data = try? Data(contentsOf: paths.stopwatchStateFile),
           let snap = try? Self.decoder.decode(StopwatchSnapshot.self, from: data) {
            self.snapshot = snap
        } else {
            self.snapshot = .idle
        }
    }

    public func save(_ s: StopwatchSnapshot) {
        snapshot = s
        try? paths.ensureDirectories()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let tmp = paths.stopwatchStateFile.appendingPathExtension("tmp.\(UUID().uuidString)")
        if let data = try? enc.encode(s) {
            try? data.write(to: tmp)
            _ = try? FileManager.default.replaceItemAt(paths.stopwatchStateFile, withItemAt: tmp)
        }
    }
}
