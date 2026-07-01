import XCTest
@testable import AignalsCore

/// A transport that returns a scripted sequence of bodies (one per call), so
/// the length-retry loop can be exercised deterministically.
private final class ScriptedTransport: QuoteTransport, @unchecked Sendable {
    private let bodies: [Result<(Data, URLResponse), Error>]
    private(set) var callCount = 0
    private let lock = NSLock()
    init(_ bodies: [Result<(Data, URLResponse), Error>]) { self.bodies = bodies }
    func get(_ request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock(); defer { lock.unlock() }
        let i = min(callCount, bodies.count - 1)
        callCount += 1
        return try bodies[i].get()
    }
}

private func ok(_ quote: String, _ author: String = "A") -> Result<(Data, URLResponse), Error> {
    let body = Data("[{\"quote\":\"\(quote)\",\"author\":\"\(author)\"}]".utf8)
    let resp = HTTPURLResponse(url: URL(string: "https://api.api-ninjas.com")!, statusCode: 200,
                               httpVersion: nil, headerFields: nil)!
    return .success((body, resp))
}
private func status(_ code: Int) -> Result<(Data, URLResponse), Error> {
    let resp = HTTPURLResponse(url: URL(string: "https://api.api-ninjas.com")!, statusCode: code,
                               httpVersion: nil, headerFields: nil)!
    return .success((Data("[]".utf8), resp))
}

final class QuoteProviderTests: XCTestCase {

    // MARK: request building

    func test_request_uses_apininjas_url_and_key_header() {
        let req = QuoteProvider.request(apiKey: "SECRET", category: .any)
        XCTAssertEqual(req.url?.absoluteString, "https://api.api-ninjas.com/v2/randomquotes")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-Api-Key"), "SECRET")
    }

    func test_request_adds_categories_param_when_not_any() {
        let req = QuoteProvider.request(apiKey: "K", category: .wisdom)
        XCTAssertEqual(req.url?.absoluteString, "https://api.api-ninjas.com/v2/randomquotes?categories=wisdom")
    }

    func test_request_omits_categories_when_any() {
        let req = QuoteProvider.request(apiKey: "K", category: .any)
        XCTAssertFalse(req.url!.absoluteString.contains("categories"))
    }

    // MARK: parsing

    func test_parse_reads_quote_and_author() {
        let body = Data(#"[{"quote":"Do it.","author":"Yoda","categories":["wisdom"]}]"#.utf8)
        XCTAssertEqual(QuoteProvider.parse(body), Quote(text: "Do it.", author: "Yoda"))
    }
    func test_parse_returns_nil_on_garbage() {
        XCTAssertNil(QuoteProvider.parse(Data("nope".utf8)))
        XCTAssertNil(QuoteProvider.parse(Data("[]".utf8)))
    }

    func test_parse_adds_missing_space_after_punctuation() {
        // API Ninjas sometimes omits the space after a comma/period.
        let body = Data(#"[{"quote":"watching,Love hurt.Sing it?Do it!Go","author":"X"}]"#.utf8)
        XCTAssertEqual(QuoteProvider.parse(body)?.text,
                       "watching, Love hurt. Sing it? Do it! Go")
    }

    func test_normalize_preserves_correct_spacing_and_decimals() {
        // Already-spaced text is untouched; numbers like 3.14 are not split.
        XCTAssertEqual(QuoteProvider.normalize("Hello, world. Done"), "Hello, world. Done")
        XCTAssertEqual(QuoteProvider.normalize("pi is 3.14 today"), "pi is 3.14 today")
    }

    // MARK: fetch

    func test_fetch_success() async {
        let p = QuoteProvider(transport: ScriptedTransport([ok("short")]))
        let q = await p.fetchQuote(apiKey: "K", category: .any)
        XCTAssertEqual(q, Quote(text: "short", author: "A"))
    }

    func test_fetch_empty_key_returns_nil_without_calling() async {
        let t = ScriptedTransport([ok("x")])
        let p = QuoteProvider(transport: t)
        let q = await p.fetchQuote(apiKey: "", category: .any)
        XCTAssertNil(q)
        XCTAssertEqual(t.callCount, 0)
    }

    func test_fetch_nil_on_transport_error() async {
        struct Boom: Error {}
        let p = QuoteProvider(transport: ScriptedTransport([.failure(Boom())]))
        let q = await p.fetchQuote(apiKey: "K", category: .any)
        XCTAssertNil(q)
    }

    func test_fetch_nil_on_non_2xx() async {
        let p = QuoteProvider(transport: ScriptedTransport([status(401)]))
        let q = await p.fetchQuote(apiKey: "K", category: .any)
        XCTAssertNil(q)
    }
}
