import Foundation

/// App-owned persistence for saved (favorited) quotes in `~/.aignals/quotes.json`.
/// Mirrors `OverrideStore`: crash-safe load (missing/malformed → empty), atomic
/// write via temp-file + `replaceItemAt`. Dedups by `text`; `saved` is kept
/// newest-first for the projector list. No session coupling.
public final class QuoteStore {
    private struct Envelope: Codable {
        var version: Int
        var quotes: [SavedQuote]
    }

    private let paths: Paths
    public private(set) var saved: [SavedQuote]

    public init(paths: Paths) {
        self.paths = paths
        if let data = try? Data(contentsOf: paths.quotesFile),
           let env = try? Self.decoder.decode(Envelope.self, from: data) {
            self.saved = env.quotes.sorted { $0.savedAt > $1.savedAt }
        } else {
            self.saved = []
        }
    }

    public func isSaved(_ text: String) -> Bool {
        saved.contains { $0.text == text }
    }

    public func save(_ quote: Quote, at date: Date) {
        guard !isSaved(quote.text) else { return }
        saved.insert(SavedQuote(text: quote.text, author: quote.author, savedAt: date), at: 0)
        saved.sort { $0.savedAt > $1.savedAt }
        persist()
    }

    public func delete(text: String) {
        let before = saved.count
        saved.removeAll { $0.text == text }
        if saved.count != before { persist() }
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    private func persist() {
        try? paths.ensureDirectories()
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let tmp = paths.quotesFile.appendingPathExtension("tmp.\(UUID().uuidString)")
        if let data = try? enc.encode(Envelope(version: 1, quotes: saved)) {
            try? data.write(to: tmp)
            _ = try? FileManager.default.replaceItemAt(paths.quotesFile, withItemAt: tmp)
        }
    }
}
