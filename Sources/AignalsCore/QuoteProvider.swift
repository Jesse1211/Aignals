import Foundation

/// Seam over the network call so `fetchQuote` is unit-testable with a stub
/// (mirrors `FeishuTransport`).
public protocol QuoteTransport: Sendable {
    func get(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: QuoteTransport {
    public func get(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

/// The 20 categories API Ninjas supports, plus `.any` (no filter). Raw values
/// are the exact API category strings; `.any` sends no `categories` param.
public enum QuoteCategory: String, CaseIterable, Codable, Sendable {
    case any = ""
    case wisdom, philosophy, life, truth, inspirational, relationships, love
    case faith, humor, success, courage, happiness, art, writing, fear
    case nature, time, freedom, death, leadership

    /// Human label for the Settings picker.
    public var label: String {
        self == .any ? "Any" : rawValue.capitalized
    }
}

/// Fetches one quote from API Ninjas (`/v2/quotes`), optionally filtered by
/// category. No caching, no retry. Any failure (transport, non-2xx, parse)
/// yields `nil` so the UI shows a placeholder. No session coupling.
public struct QuoteProvider {
    private let transport: QuoteTransport

    public init(transport: QuoteTransport = URLSession.shared) {
        self.transport = transport
    }

    /// Build the request: `/v2/randomquotes` (returns a fresh random quote each
    /// call — `/v2/quotes` is fixed/daily) with an optional `categories` filter
    /// and the `X-Api-Key` header.
    public static func request(apiKey: String, category: QuoteCategory) -> URLRequest {
        var comps = URLComponents(string: "https://api.api-ninjas.com/v2/randomquotes")!
        if category != .any {
            comps.queryItems = [URLQueryItem(name: "categories", value: category.rawValue)]
        }
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 10
        req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        return req
    }

    /// API Ninjas returns `[{"quote": text, "author": author, ...}]`.
    public static func parse(_ data: Data) -> Quote? {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = arr.first,
              let q = first["quote"] as? String,
              let a = first["author"] as? String else { return nil }
        return Quote(text: normalize(q), author: a)
    }

    /// Some API Ninjas quotes drop the space after punctuation
    /// (e.g. "watching,Love"). Insert a space after `, ; ? !` — and after `.`
    /// too, but not between digits so decimals like "3.14" survive — whenever a
    /// letter follows immediately.
    public static func normalize(_ text: String) -> String {
        var s = text.replacingOccurrences(
            of: "([,;?!])([A-Za-z])",
            with: "$1 $2",
            options: .regularExpression)
        s = s.replacingOccurrences(
            of: "(\\.)([A-Za-z])",
            with: "$1 $2",
            options: .regularExpression)
        return s
    }

    /// Fetch one quote. Returns nil on empty key, transport error, non-2xx, or
    /// a body that doesn't parse.
    public func fetchQuote(apiKey: String, category: QuoteCategory) async -> Quote? {
        guard !apiKey.isEmpty else { return nil }
        let req = Self.request(apiKey: apiKey, category: category)
        guard let (data, response) = try? await transport.get(req) else { return nil }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return nil
        }
        return Self.parse(data)
    }
}
