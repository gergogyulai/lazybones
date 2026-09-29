import XCTest
import MacSystem

final class ScreenTintTests: XCTestCase {
    func testNoDimmingOrFilterLeavesTheScreenAlone() {
        let g = ScreenTint.Level.off.gains
        XCTAssertEqual(g.red, 1)
        XCTAssertEqual(g.green, 1)
        XCTAssertEqual(g.blue, 1)
    }

    func testFilteringBlueLightCutsBlueMostAndGreenALittle() {
        let g = ScreenTint.Level(dim: 0, warmth: 1).gains
        XCTAssertEqual(g.red, 1)
        XCTAssertLessThan(g.green, 1)
        XCTAssertLessThan(g.blue, g.green)
    }

    func testDimmingScalesAllChannelsEqually() {
        let g = ScreenTint.Level(dim: 0.5, warmth: 0).gains
        XCTAssertEqual(g.red, g.green)
        XCTAssertEqual(g.green, g.blue)
        XCTAssertLessThan(g.red, 1)
    }

    func testTheScreenNeverGoesBlack() {
        let g = ScreenTint.Level(dim: 1, warmth: 1).gains
        XCTAssertGreaterThan(g.blue, 0.03)
        XCTAssertGreaterThan(g.red, 0.1)
    }

    func testOutOfRangeLevelsAreClamped() {
        XCTAssertEqual(ScreenTint.Level(dim: 5, warmth: -1), ScreenTint.Level(dim: 1, warmth: 0))
    }
}
