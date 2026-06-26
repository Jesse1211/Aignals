import XCTest
@testable import AignalsCore

final class FeishuClientTests: XCTestCase {
    // Known vector: HMAC-SHA256 with key "1599360000\nmysecret" over empty data,
    // Base64-encoded. Recomputed independently to lock the algorithm.
    func testSignKnownVector() {
        let sig = FeishuClient.sign(timestamp: 1599360000, secret: "mysecret")
        XCTAssertEqual(sig, "Noveltng5Xd0Pz/+xbLEwM5rQ8+MoniFNJzH2juq9lk=")
    }

    func testBodyWithoutSecretOmitsSignFields() {
        let b = FeishuClient.body(text: "hi", timestamp: 1599360000, secret: "")
        XCTAssertEqual(b["msg_type"] as? String, "text")
        XCTAssertEqual((b["content"] as? [String: Any])?["text"] as? String, "hi")
        XCTAssertNil(b["timestamp"])
        XCTAssertNil(b["sign"])
    }

    func testBodyWithSecretAddsSignFields() {
        let b = FeishuClient.body(text: "hi", timestamp: 1599360000, secret: "mysecret")
        XCTAssertEqual(b["timestamp"] as? String, "1599360000")
        XCTAssertEqual(b["sign"] as? String, FeishuClient.sign(timestamp: 1599360000, secret: "mysecret"))
    }
}
