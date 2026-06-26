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

    func testSendSuccessOnCodeZero() async {
        let client = FeishuClient(transport: StubTransport.http(200, #"{"code":0,"msg":"success"}"#))
        let r = await client.send(text: "hi", webhookURL: "https://open.feishu.cn/x", secret: "", timestamp: 1599360000)
        if case .success = r { } else { XCTFail("expected .success, got \(r)") }
    }

    func testSendFeishuRejectionOnNonZeroCode() async {
        let client = FeishuClient(transport: StubTransport.http(200, #"{"code":19021,"msg":"sign match fail"}"#))
        let r = await client.send(text: "hi", webhookURL: "https://open.feishu.cn/x", secret: "s", timestamp: 1599360000)
        if case .failure(.feishu(19021, "sign match fail")) = r { } else { XCTFail("expected .feishu(19021,...), got \(r)") }
    }

    func testSendHTTPErrorOnNon2xx() async {
        let client = FeishuClient(transport: StubTransport.http(500, "oops"))
        let r = await client.send(text: "hi", webhookURL: "https://open.feishu.cn/x", secret: "", timestamp: 1599360000)
        if case .failure(.http(500)) = r { } else { XCTFail("expected .http(500), got \(r)") }
    }

    func testSendTransportErrorWhenThrown() async {
        let stub = StubTransport(result: .failure(URLError(.notConnectedToInternet)))
        let client = FeishuClient(transport: stub)
        let r = await client.send(text: "hi", webhookURL: "https://open.feishu.cn/x", secret: "", timestamp: 1599360000)
        if case .failure(.transport) = r { } else { XCTFail("expected .transport, got \(r)") }
    }
}

private struct StubTransport: FeishuTransport {
    let result: Result<(Data, URLResponse), Error>
    func post(_ request: URLRequest) async throws -> (Data, URLResponse) {
        switch result {
        case .success(let pair): return pair
        case .failure(let err): throw err
        }
    }
    static func http(_ status: Int, _ json: String) -> StubTransport {
        let resp = HTTPURLResponse(url: URL(string: "https://x")!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return StubTransport(result: .success((Data(json.utf8), resp)))
    }
}
