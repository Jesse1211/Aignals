import XCTest
@testable import AignalsCore

final class FeishuMessageTests: XCTestCase {
    func testWorkingAndDisconnectedAreNil() {
        XCTAssertNil(FeishuMessage.text(displayName: "p", state: .working))
        XCTAssertNil(FeishuMessage.text(displayName: "p", state: .disconnected))
    }

    func testPermissionText() {
        let t = FeishuMessage.text(displayName: "my-project", state: .waitingPermission)
        XCTAssertEqual(t, "Aignals • my-project: 🟡 waiting for permission — go click Allow")
    }

    func testInputText() {
        let t = FeishuMessage.text(displayName: "my-project", state: .waitingInput)
        XCTAssertEqual(t, "Aignals • my-project: 🟢 finished — your turn")
    }

    func testDisplayNameHonored() {
        let t = FeishuMessage.text(displayName: "renamed!", state: .waitingInput)
        XCTAssertTrue(t!.contains("renamed!"))
    }

    func testEmptyKeywordAppendsNothing() {
        let t = FeishuMessage.text(displayName: "p", state: .waitingInput, keyword: "")
        XCTAssertFalse(t!.contains("["))
    }

    func testKeywordAlreadyPresentAppendsNothing() {
        // "Aignals" is always in the text, so an Aignals keyword adds nothing.
        let t = FeishuMessage.text(displayName: "p", state: .waitingInput, keyword: "Aignals")
        XCTAssertFalse(t!.contains("[Aignals]"))
    }

    func testNovelKeywordIsAppended() {
        let t = FeishuMessage.text(displayName: "p", state: .waitingInput, keyword: "robot")
        XCTAssertTrue(t!.hasSuffix(" [robot]"))
        XCTAssertTrue(t!.contains("robot"))
    }
}
