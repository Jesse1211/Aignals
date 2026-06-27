import Foundation
import CryptoKit

/// Errors from a Feishu webhook send, each carrying a short string for the UI.
public enum FeishuError: Error, Equatable {
    case transport(String)   // offline / DNS / TLS — no HTTP response
    case http(Int)           // non-2xx HTTP status
    case feishu(Int, String) // HTTP ok but body code != 0 (e.g. 19021 bad sign)
}

/// Seam over the network call so `send` is unit-testable with a stub.
public protocol FeishuTransport: Sendable {
    func post(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: FeishuTransport {
    public func post(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

/// Posts a text message to a Feishu custom-bot webhook. Signing and body-shaping
/// are pure statics (unit-tested); `send` (Task 4) does the URLSession POST.
public struct FeishuClient {
    let transport: FeishuTransport
    public init(transport: FeishuTransport = URLSession.shared) {
        self.transport = transport
    }
    /// Feishu signature: Base64(HMAC-SHA256(key: "<timestamp>\n<secret>", data: empty)).
    public static func sign(timestamp: Int, secret: String) -> String {
        let key = SymmetricKey(data: Data("\(timestamp)\n\(secret)".utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(), using: key)
        return Data(mac).base64EncodedString()
    }

    /// The JSON request body. Adds `timestamp`/`sign` only for signature-mode bots.
    public static func body(text: String, timestamp: Int, secret: String) -> [String: Any] {
        var b: [String: Any] = ["msg_type": "text", "content": ["text": text]]
        if !secret.isEmpty {
            b["timestamp"] = "\(timestamp)"
            b["sign"] = sign(timestamp: timestamp, secret: secret)
        }
        return b
    }

    /// POST `text` to `webhookURL`. `timestamp` is supplied by the caller (current
    /// Unix seconds) so signing is deterministic in tests. Best-effort: returns a
    /// `Result` rather than throwing, for the UI to surface.
    public func send(text: String, webhookURL: String, secret: String, timestamp: Int) async -> Result<Void, FeishuError> {
        guard let url = URL(string: webhookURL) else {
            return .failure(.transport("invalid URL"))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: Self.body(text: text, timestamp: timestamp, secret: secret))

        let data: Data, response: URLResponse
        do {
            (data, response) = try await transport.post(req)
        } catch {
            return .failure(.transport(error.localizedDescription))
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return .failure(.http(http.statusCode))
        }
        // Feishu returns {"code":0} on success, non-zero on rejection.
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let code = (obj?["code"] as? Int) ?? 0
        if code != 0 {
            let msg = (obj?["msg"] as? String) ?? "unknown"
            return .failure(.feishu(code, msg))
        }
        return .success(())
    }
}
