import XCTest
@testable import AignalsCore

final class ThemeTests: XCTestCase {
    func testRawValuesAreStable() {
        XCTAssertEqual(Theme.glassLight.rawValue, "glassLight")
        XCTAssertEqual(Theme.glassDark.rawValue, "glassDark")
        XCTAssertEqual(Theme.terminal.rawValue, "terminal")
        XCTAssertEqual(Theme.vibrant.rawValue, "vibrant")
    }

    func testAllCasesCountIsFour() {
        XCTAssertEqual(Theme.allCases.count, 4)
    }

    func testDisplayNames() {
        XCTAssertEqual(Theme.glassLight.displayName, "Glass Light")
        XCTAssertEqual(Theme.glassDark.displayName, "Glass Dark")
        XCTAssertEqual(Theme.terminal.displayName, "Terminal")
        XCTAssertEqual(Theme.vibrant.displayName, "Vibrant")
    }

    func testSwatchHexesNonEmpty() {
        for t in Theme.allCases {
            XCTAssertFalse(t.swatchHexes.isEmpty, "\(t) must have at least one swatch hex")
            for hex in t.swatchHexes {
                XCTAssertTrue(hex.hasPrefix("#"), "swatch hex must start with #: \(hex)")
            }
        }
    }

    func testCodableRoundTrip() throws {
        for t in Theme.allCases {
            let data = try JSONEncoder().encode(t)
            let back = try JSONDecoder().decode(Theme.self, from: data)
            XCTAssertEqual(t, back)
        }
    }
}
