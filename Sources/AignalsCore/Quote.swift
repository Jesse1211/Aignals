import Foundation

/// A motivation quote fetched from the online source. In-memory only for the
/// daily quote; the saved-favorites variant is `SavedQuote`.
public struct Quote: Codable, Equatable, Sendable {
    public let text: String
    public let author: String
    public init(text: String, author: String) {
        self.text = text
        self.author = author
    }
}

/// A quote the user chose to keep, with the time it was saved. Persisted in
/// `~/.aignals/quotes.json` by `QuoteStore`.
public struct SavedQuote: Codable, Equatable, Sendable {
    public let text: String
    public let author: String
    public let savedAt: Date
    public init(text: String, author: String, savedAt: Date) {
        self.text = text
        self.author = author
        self.savedAt = savedAt
    }
}
