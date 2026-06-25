import XCTest
@testable import AignalsCore

final class AlertSoundTests: XCTestCase {
    func testNoneHasNoSystemSound() {
        XCTAssertNil(AlertSound.none.systemSoundName)
    }

    func testKnownDefaultsMapToPingAndGlass() {
        XCTAssertEqual(AlertSound.ping.systemSoundName, "Ping")
        XCTAssertEqual(AlertSound.glass.systemSoundName, "Glass")
    }

    func testAllCasesHaveNonEmptyDisplayName() {
        for s in AlertSound.allCases {
            XCTAssertFalse(s.displayName.isEmpty, "\(s) has empty displayName")
        }
    }

    func testNonNoneCasesResolveToRealSystemSoundFiles() {
        for s in AlertSound.allCases where s != .none {
            let name = try! XCTUnwrap(s.systemSoundName, "\(s) must have a name")
            let path = "/System/Library/Sounds/\(name).aiff"
            XCTAssertTrue(FileManager.default.fileExists(atPath: path),
                          "missing system sound file: \(path)")
        }
    }

    func testRawValueRoundTrip() throws {
        for s in AlertSound.allCases {
            let data = try JSONEncoder().encode(s)
            let back = try JSONDecoder().decode(AlertSound.self, from: data)
            XCTAssertEqual(back, s)
        }
    }
}
