import XCTest
@testable import AignalsCore

final class QuoteTruncationTests: XCTestCase {
    func test_short_text_unchanged() {
        XCTAssertEqual(QuoteTruncation.truncate("hi", to: 40), "hi")
    }
    func test_exact_length_unchanged() {
        XCTAssertEqual(QuoteTruncation.truncate("abcde", to: 5), "abcde")
    }
    func test_long_text_truncated_with_ellipsis() {
        XCTAssertEqual(QuoteTruncation.truncate("abcdef", to: 5), "abcde…")
    }
    func test_zero_limit_is_just_ellipsis() {
        XCTAssertEqual(QuoteTruncation.truncate("abc", to: 0), "…")
    }
}
