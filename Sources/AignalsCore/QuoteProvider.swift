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

/// Which ZenQuotes endpoint to hit. `.today` for the daily quote / launch /
/// midnight refresh; `.random` for the manual ⟳ refresh button.
public enum QuoteEndpoint {
    case today, random

    var url: URL {
        switch self {
        case .today:  return URL(string: "https://zenquotes.io/api/today")!
        case .random: return URL(string: "https://zenquotes.io/api/random")!
        }
    }
}

/// Fetches one quote from ZenQuotes. No retry, no caching. Any failure
/// (transport, non-2xx, parse) yields `nil` so the UI can show `—`.
/// No session coupling.
public struct QuoteProvider {
    private let transport: QuoteTransport

    public init(transport: QuoteTransport = URLSession.shared) {
        self.transport = transport
    }

    /// ZenQuotes returns a JSON array: `[{"q": text, "a": author, ...}]`.
    public static func parse(_ data: Data) -> Quote? {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = arr.first,
              let q = first["q"] as? String,
              let a = first["a"] as? String else { return nil }
        return Quote(text: q, author: a)
    }

    public func fetchQuote(_ endpoint: QuoteEndpoint = .today) async -> Quote? {
        var req = URLRequest(url: endpoint.url)
        req.timeoutInterval = 10
        let data: Data, response: URLResponse
        do {
            (data, response) = try await transport.get(req)
        } catch {
            return nil
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return nil
        }
        return Self.parse(data)
    }
}
