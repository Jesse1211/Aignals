import XCTest
@testable import AignalsCore

final class SessionStateTests: XCTestCase {
    // MARK: - SessionState value object

    func testValidStringsRoundTrip() {
        let cases: [(String, SessionState)] = [
            ("working", .working),
            ("waiting_permission", .waitingPermission),
            ("waiting_input", .waitingInput),
            ("disconnected", .disconnected),
        ]
        for (raw, expected) in cases {
            let parsed = SessionState(jsonValue: raw)
            XCTAssertEqual(parsed, expected, "\(raw) should parse to \(expected)")
            XCTAssertEqual(parsed?.jsonValue, raw, "\(expected) should serialize back to \(raw)")
            XCTAssertEqual(expected.rawValue, raw)
        }
    }

    func testUnknownStringYieldsNil() {
        XCTAssertNil(SessionState(jsonValue: "idle"))
        XCTAssertNil(SessionState(jsonValue: "Working"))
        XCTAssertNil(SessionState(jsonValue: ""))
        XCTAssertNil(SessionState(jsonValue: "waitingPermission"))
    }

    // MARK: - Session decode with schema v2 + state + updated_at

    func testSchemaV2WithStateAndUpdatedAtDecodes() throws {
        let raw = """
        {
          "schema_version": 2,
          "session_id": "s2",
          "tool": "claude-code",
          "project_name": "p",
          "state": "waiting_permission",
          "started_at": "2026-06-16T14:00:00Z",
          "updated_at": "2026-06-16T14:05:00Z"
        }
        """
        let session = try Session.decode(from: Data(raw.utf8))
        XCTAssertEqual(session.sessionID, "s2")
        XCTAssertEqual(session.state, .waitingPermission)
        XCTAssertEqual(
            session.updatedAt,
            ISO8601DateFormatter().date(from: "2026-06-16T14:05:00Z")
        )
    }

    func testSessionMissingStateFailsToDecode() {
        let raw = """
        {
          "schema_version": 2,
          "session_id": "s3",
          "tool": "t",
          "project_name": "p",
          "started_at": "2026-06-16T14:00:00Z",
          "updated_at": "2026-06-16T14:05:00Z"
        }
        """
        XCTAssertThrowsError(try Session.decode(from: Data(raw.utf8))) { error in
            XCTAssertEqual(error as? Session.DecodeError, .missingField("state"))
        }
        XCTAssertNil(try? Session.decode(from: Data(raw.utf8)))
    }

    func testSessionUnknownStateFailsToDecode() {
        let raw = """
        {
          "schema_version": 2,
          "session_id": "s4",
          "tool": "t",
          "project_name": "p",
          "state": "bogus",
          "started_at": "2026-06-16T14:00:00Z",
          "updated_at": "2026-06-16T14:05:00Z"
        }
        """
        XCTAssertThrowsError(try Session.decode(from: Data(raw.utf8))) { error in
            XCTAssertEqual(error as? Session.DecodeError, .missingField("state"))
        }
    }
}
