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
    }

    func testDecodeSessionWithoutAction() throws {
        let data = try loadFixture("session_no_action")
        let session = try Session.decode(from: data)
        XCTAssertEqual(session.sessionID, "abc-456")
        XCTAssertNil(session.currentAction)
        XCTAssertNil(session.pid)
        XCTAssertNil(session.cwd)
    }

    func testDecodeUnknownVersionReturnsNil() throws {
        let data = try loadFixture("session_v2")
        XCTAssertNil(try? Session.decode(from: data))
    }

    func testDecodeMissingRequiredFieldThrows() throws {
        let data = try loadFixture("session_missing_required")
        XCTAssertThrowsError(try Session.decode(from: data))
    }

    func testDecodeIgnoresUnknownExtraFields() throws {
        let raw = """
        {
          "schema_version": 1,
          "session_id": "a", "tool": "t", "project_name": "p",
          "started_at": "2026-06-16T14:00:00Z",
          "unknown_field": "ignored"
        }
        """
        let session = try Session.decode(from: Data(raw.utf8))
        XCTAssertEqual(session.sessionID, "a")
    }
}
