import Foundation

/// Truncates menubar quote text to a character budget, adding `…` when cut.
public enum QuoteTruncation {
    public static func truncate(_ text: String, to limit: Int) -> String {
        guard limit > 0 else { return "…" }
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }
}
