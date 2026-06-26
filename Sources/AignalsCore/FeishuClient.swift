import Foundation
import CryptoKit

/// Errors from a Feishu webhook send, each carrying a short string for the UI.
public enum FeishuError: Error, Equatable {
    case transport(String)   // offline / DNS / TLS — no HTTP response
    case http(Int)           // non-2xx HTTP status
    case feishu(Int, String) // HTTP ok but body code != 0 (e.g. 19021 bad sign)
}

/// Posts a text message to a Feishu custom-bot webhook. Signing and body-shaping
/// are pure statics (unit-tested); `send` (Task 4) does the URLSession POST.
public struct FeishuClient {
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
}
