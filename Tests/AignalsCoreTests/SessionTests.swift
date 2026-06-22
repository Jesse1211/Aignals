import XCTest
@testable import AignalsCore

final class SessionTests: XCTestCase {
    private func loadFixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: name, withExtension: "json")
        )
        return try Data(contentsOf: url)
    }

    func testDecodeGoodSession() throws {
        let data = try loadFixture("session_good")
        let session = try Session.decode(from: data)
        XCTAssertEqual(session.sessionID, "abc-123")
        XCTAssertEqual(session.tool, "claude-code")
        XCTAssertEqual(session.pid, 48217)
        XCTAssertEqual(session.projectName, "Aignals")
        XCTAssertEqual(session.cwd, "/Users/jesseliu/Desktop/Chore/Aignals")
        XCTAssertEqual(session.currentAction?.tool, "Edit")
        XCTAssertEqual(session.currentAction?.target, "main.swift")
        XCTAssertEqual(session.state, .working)
        XCTAssertEqual(
            session.updatedAt,
            ISO8601DateFormatter().date(from: "2026-06-16T14:54:31Z")
        )
    }

    func testDecodeSessionWithoutAction() throws {
        let data = try loadFixture("session_no_action")
        let session = try Session.decode(from: data)
        XCTAssertEqual(session.sessionID, "abc-456")
        XCTAssertNil(session.currentAction)
        XCTAssertNil(session.pid)
        XCTAssertNil(session.cwd)
        XCTAssertEqual(session.state, .waitingInput)
    }

    func testDecodeUnknownVersionReturnsNil() throws {
        // schema_version=99 is an unsupported future version (the accepted
        // version is now 2 — see SessionStateTests for the v2 happy path).
        let data = try loadFixture("session_v2")
        XCTAssertNil(try? Session.decode(from: data))
    }

    func testDecodeMissingRequiredFieldThrows() throws {
        let data = try loadFixture("session_missing_required")
        XCTAssertThrowsError(try Session.decode(from: data))
    }

    /// H1 / INV-8: `aignals-hook`'s `now_iso` stamps millisecond precision
    /// (e.g. "2026-06-22T13:51:33.739Z") so two events in the same wall-clock
    /// second still order correctly. The decoder must parse the fractional form
    /// AND preserve sub-second precision, otherwise two same-second updates would
    /// decode to equal Dates and the store's `updatedAt >` guard would tie-break
    /// wrong. Regression for the bug where Session only parsed second-granular
    /// ISO8601 and silently failed (invalidDate) on the millisecond stamp.
    func testDecodeMillisecondUpdatedAt() throws {
        let raw = """
        {
          "schema_version": 2,
          "session_id": "ms", "tool": "claude-code", "project_name": "p",
          "state": "working",
          "started_at": "2026-06-22T13:51:33.739Z",
          "updated_at": "2026-06-22T13:51:33.739Z"
        }
        """
        let session = try Session.decode(from: Data(raw.utf8))
        let expected = ISO8601DateFormatter.fractionalForTest.date(from: "2026-06-22T13:51:33.739Z")
        XCTAssertEqual(session.updatedAt, expected)
        XCTAssertEqual(session.startedAt, expected)
    }

    /// Two same-second updates that differ only in milliseconds must decode to
    /// DISTINCT, correctly-ordered Dates (the precise property INV-8 relies on).
    func testMillisecondUpdatesAreDistinctAndOrdered() throws {
        func decode(_ ts: String) throws -> Session {
            let raw = """
            {"schema_version":2,"session_id":"x","tool":"t","project_name":"p",
             "state":"working","started_at":"\(ts)","updated_at":"\(ts)"}
            """
            return try Session.decode(from: Data(raw.utf8))
        }
        let early = try decode("2026-06-22T13:51:33.100Z")
        let late  = try decode("2026-06-22T13:51:33.900Z")
        XCTAssertNotEqual(early.updatedAt, late.updatedAt)
        XCTAssertLessThan(early.updatedAt, late.updatedAt)
    }

    /// The plain second-granular form (the `now_iso` fallback / older files) must
    /// still decode — the fractional parser must not have displaced the legacy one.
    func testDecodeStillAcceptsSecondGranularUpdatedAt() throws {
        let raw = """
        {"schema_version":2,"session_id":"s","tool":"t","project_name":"p",
         "state":"working","started_at":"2026-06-22T13:51:33Z","updated_at":"2026-06-22T13:51:33Z"}
        """
        let session = try Session.decode(from: Data(raw.utf8))
        XCTAssertEqual(session.updatedAt, ISO8601DateFormatter().date(from: "2026-06-22T13:51:33Z"))
    }

    func testDecodeIgnoresUnknownExtraFields() throws {
        let raw = """
        {
          "schema_version": 2,
          "session_id": "a", "tool": "t", "project_name": "p",
          "state": "working",
          "started_at": "2026-06-16T14:00:00Z",
          "updated_at": "2026-06-16T14:00:00Z",
          "unknown_field": "ignored"
        }
        """
        let session = try Session.decode(from: Data(raw.utf8))
        XCTAssertEqual(session.sessionID, "a")
    }
}

private extension ISO8601DateFormatter {
    static let fractionalForTest: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
