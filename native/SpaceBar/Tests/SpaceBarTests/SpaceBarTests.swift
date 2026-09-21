import XCTest
@testable import SpaceBar

final class SpaceBarTests: XCTestCase {
    private func space(_ id: Int, _ index: Int, _ display: Int, _ label: String = "Code") -> Space {
        Space(id: id, index: index, label: label, display: display, focused: false, visible: true, fullscreen: false)
    }
    func testDisplayIdentityNotArrangementIndex() {
        let snapshot = Snapshot(spaces: [space(100, 7, 2), space(101, 6, 2), space(200, 1, 1)], displays: [Display(id: 42, index: 2), Display(id: 99, index: 1)])
        XCTAssertEqual(snapshot.spaces(on: 42).map(\.id), [101, 100])
        XCTAssertTrue(snapshot.spaces(on: 123).isEmpty)
    }
    func testActualYabaiSchemaWithUnknownWindowFields() throws {
        let json = #"[{"id":3,"index":2,"display":1,"label":"🏖 Free1","has-focus":false,"is-visible":true,"is-native-fullscreen":false,"windows":[1,2]}]"#
        let spaces = try JSONDecoder().decode([Space].self, from: Data(json.utf8))
        XCTAssertEqual(spaces.first?.hint, "W")
        XCTAssertEqual(spaces.first?.visible, true)
        XCTAssertEqual(spaces.first?.focused, false)
    }
    func testRenameValidationAndLiteralShellCharacters() throws {
        let spaces = [space(1, 1, 1), space(2, 2, 1, "Chat")]
        XCTAssertEqual(try validatedName("  Code  ", id: 1, spaces: spaces), "Code")
        XCTAssertEqual(try validatedName("$(echo hi) ' \"", id: 1, spaces: spaces), "$(echo hi) ' \"")
        XCTAssertThrowsError(try validatedName("Chat", id: 1, spaces: spaces))
        XCTAssertThrowsError(try validatedName(" \n ", id: 1, spaces: spaces))
        XCTAssertThrowsError(try validatedName("a\nb", id: 1, spaces: spaces))
    }
    func testProcessArgumentsNeverPassThroughShell() throws {
        let literal = "$(touch /tmp/spacebar-should-never-exist) ' \" ;"
        let output = try YabaiClient.run("/usr/bin/printf", arguments: ["%s", literal])
        XCTAssertEqual(String(data: output, encoding: .utf8), literal)
    }
    func testHungCommandTerminates() {
        let started = Date()
        XCTAssertThrowsError(try YabaiClient.run("/bin/sleep", arguments: ["5"], timeout: 0.1))
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }
    func testFailureIncludesStderr() {
        XCTAssertThrowsError(try YabaiClient.run("/bin/ls", arguments: ["/spacebar-test-missing-directory"])) { error in
            XCTAssertTrue(error.localizedDescription.contains("spacebar-test-missing-directory"))
        }
    }
}
