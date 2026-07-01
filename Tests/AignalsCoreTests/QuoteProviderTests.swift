import XCTest
@testable import AignalsCore

private struct StubTransport: QuoteTransport {
    let result: Result<(Data, URLResponse), Error>
    func get(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try result.get()
    }
}

private func http(_ code: Int) -> URLResponse {
    HTTPURLResponse(url: URL(string: "https://zenquotes.io")!, statusCode: code,
                    httpVersion: nil, headerFields: nil)!
}

final class QuoteProviderTests: XCTestCase {
    func test_parse_reads_first_element_q_and_a() {
        let body = Data(#"[{"q":"Keep going.","a":"Anon","h":"..."}]"#.utf8)
        XCTAssertEqual(QuoteProvider.parse(body), Quote(text: "Keep going.", author: "Anon"))
    }

    func test_parse_returns_nil_on_garbage() {
        XCTAssertNil(QuoteProvider.parse(Data("not json".utf8)))
        XCTAssertNil(QuoteProvider.parse(Data("[]".utf8)))
    }

    func test_fetch_success() async {
        let body = Data(#"[{"q":"Do it.","a":"Yoda"}]"#.utf8)
        let provider = QuoteProvider(transport: StubTransport(result: .success((body, http(200)))))
        let q = await provider.fetchQuote()
        XCTAssertEqual(q, Quote(text: "Do it.", author: "Yoda"))
    }

    func test_fetch_returns_nil_on_transport_error() async {
        struct Boom: Error {}
        let provider = QuoteProvider(transport: StubTransport(result: .failure(Boom())))
        let q = await provider.fetchQuote()
        XCTAssertNil(q)
    }

    func test_fetch_returns_nil_on_non_2xx() async {
        let provider = QuoteProvider(transport: StubTransport(result: .success((Data("[]".utf8), http(500)))))
        let q = await provider.fetchQuote()
        XCTAssertNil(q)
    }

    func test_fetch_returns_nil_on_malformed_body() async {
        let provider = QuoteProvider(transport: StubTransport(result: .success((Data("nope".utf8), http(200)))))
        let q = await provider.fetchQuote()
        XCTAssertNil(q)
    }
}
