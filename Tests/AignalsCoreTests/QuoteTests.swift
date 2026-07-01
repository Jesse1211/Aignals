import XCTest
@testable import AignalsCore

final class QuoteTests: XCTestCase {
    func test_quote_roundtrips_through_codable() throws {
        let q = Quote(text: "Keep going.", author: "Anon")
        let data = try JSONEncoder().encode(q)
        let back = try JSONDecoder().decode(Quote.self, from: data)
        XCTAssertEqual(back, q)
    }

    func test_savedQuote_encodes_savedAt_as_iso8601() throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let sq = SavedQuote(text: "T", author: "A", savedAt: Date(timeIntervalSince1970: 0))
        let json = String(data: try enc.encode(sq), encoding: .utf8)!
        XCTAssertTrue(json.contains("1970-01-01T00:00:00Z"))
    }
}
