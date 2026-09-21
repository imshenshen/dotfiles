import XCTest
@testable import SpaceBar

final class AnimationTests: XCTestCase {
    func testLegacyAppearanceKeepsExistingSettings() throws {
        let legacy = Data(#"{"radius":7,"speed":1.8,"animation":false,"topOffset":44,"background":{"r":0.1,"g":0.2,"b":0.3,"a":0.7}}"#.utf8)
        let value = try JSONDecoder().decode(Appearance.self, from: legacy)
        XCTAssertEqual(value.radius, 7)
        XCTAssertEqual(value.background.g, 0.2)
        XCTAssertFalse(value.animation)
        XCTAssertEqual(value.topOffset, 44)
        XCTAssertEqual(value.height, 26)
        XCTAssertEqual(value.fontSize, 11)
        var large = value; large.fontSize = 24
        XCTAssertGreaterThanOrEqual(large.effectiveHeight, 44)
        XCTAssertEqual(try JSONDecoder().decode(Appearance.self, from: JSONEncoder().encode(large)), large)
    }
    func testRetargetPreservesPositionAndVelocity() {
        var motion = SelectionMotion(rect: CGRect(x: 0, y: 1, width: 80, height: 18))
        motion.target = CGRect(x: 280, y: 1, width: 110, height: 18)
        for _ in 0..<12 { _ = motion.advance(dt: 1.0 / 120, speed: 1) }
        let position = motion.rect
        let velocity = motion.center.velocity
        motion.target = CGRect(x: 90, y: 1, width: 75, height: 18)
        XCTAssertEqual(motion.rect, position)
        XCTAssertEqual(motion.center.velocity, velocity)
        var settled = false
        for _ in 0..<600 { settled = motion.advance(dt: 1.0 / 120, speed: 1); if settled { break } }
        XCTAssertTrue(settled)
        XCTAssertEqual(motion.rect, motion.target)
        XCTAssertEqual(motion.center.velocity, 0)
    }
    func testRapidReversalsRemainFiniteAndLandOnLastTarget() {
        var motion = SelectionMotion(rect: CGRect(x: 0, y: 1, width: 80, height: 18))
        for destination in [400.0, 20, 610, 150, 0, 300] {
            motion.target = CGRect(x: destination, y: 1, width: 70, height: 18)
            for _ in 0..<4 {
                _ = motion.advance(dt: 1.0 / 120, speed: 1)
                XCTAssertTrue(motion.rect.origin.x.isFinite)
                XCTAssertGreaterThan(motion.rect.width, 0)
            }
        }
        for _ in 0..<1200 { if motion.advance(dt: 1.0 / 120, speed: 0.4) { break } }
        XCTAssertEqual(motion.rect, motion.target)
    }
    func testFrameRateIndependentCenter() {
        let target = CGRect(x: 300, y: 1, width: 80, height: 18)
        var a = SelectionMotion(rect: CGRect(x: 0, y: 1, width: 80, height: 18))
        var b = a; a.target = target; b.target = target
        for _ in 0..<12 { _ = a.advance(dt: 1.0 / 60, speed: 1) }
        for _ in 0..<24 { _ = b.advance(dt: 1.0 / 120, speed: 1) }
        XCTAssertEqual(a.center.position, b.center.position, accuracy: 0.00001)
        XCTAssertEqual(a.center.velocity, b.center.velocity, accuracy: 0.00001)
    }
    func testAppearancePersistsAndResets() {
        let name = "SpaceBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = AppearanceStore(defaults: defaults)
        store.value.radius = 7; store.value.speed = 1.7; store.value.animation = false
        store.value.background = RGBA(0.4, alpha: 0.8)
        let reopened = AppearanceStore(defaults: defaults)
        XCTAssertEqual(reopened.value, store.value)
        reopened.reset()
        XCTAssertEqual(AppearanceStore(defaults: defaults).value, Appearance())
    }
}
