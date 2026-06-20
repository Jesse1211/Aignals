import XCTest
@testable import AignalsCore

final class VerbMapperTests: XCTestCase {
    func testKnownTools() {
        XCTAssertEqual(VerbMapper.verb(forTool: "Edit"), "Editing")
        XCTAssertEqual(VerbMapper.verb(forTool: "Write"), "Editing")
        XCTAssertEqual(VerbMapper.verb(forTool: "Bash"), "Running")
        XCTAssertEqual(VerbMapper.verb(forTool: "Read"), "Reading")
        XCTAssertEqual(VerbMapper.verb(forTool: "Glob"), "Searching")
        XCTAssertEqual(VerbMapper.verb(forTool: "Grep"), "Searching")
    }
    func testUnknownToolTitleCased() {
        XCTAssertEqual(VerbMapper.verb(forTool: "myTool"), "Mytool")
        XCTAssertEqual(VerbMapper.verb(forTool: "ABC"), "Abc")
    }
}
