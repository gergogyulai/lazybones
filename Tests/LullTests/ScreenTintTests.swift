import XCTest
import MacSystem

final class ScreenTintTests: XCTestCase {
    func testNoDimmingOrFilterLeavesTheScreenAlone() {
        let g = ScreenTint.Level.off.gains
        XCTAssertEqual(g.red, 1)
        XCTAssertEqual(g.green, 1)
        XCTAssertEqual(g.blue, 1)
    }

    func testFilteringBlueLightCutsBlueMostAndGreenSomeAndLeavesRed() {
        let g = ScreenTint.Level(dim: 0, warmth: 1).gains
        XCTAssertEqual(g.red, 1)
        XCTAssertLessThan(g.green, 1)
        XCTAssertLessThan(g.blue, g.green)
        XCTAssertLessThan(g.blue, 0.3, "a strong filter, near candlelight")
    }

    func testDimmingScalesAllChannelsEqually() {
        let g = ScreenTint.Level(dim: 0.5, warmth: 0).gains
        XCTAssertEqual(g.red, g.green)
        XCTAssertEqual(g.green, g.blue)
        XCTAssertLessThan(g.red, 1)
    }

    func testTheStrongestDimIsVeryDarkButNeverBlack() {
        let strongest = ScreenTint.Level(dim: 0.9, warmth: 0).gains
        XCTAssertLessThan(strongest.red, 0.2, "stronger than before")
        let g = ScreenTint.Level(dim: 1, warmth: 1).gains
        XCTAssertGreaterThan(g.blue, 0.005)
        XCTAssertGreaterThan(g.red, 0.04)
    }

    func testOutOfRangeLevelsAreClamped() {
        XCTAssertEqual(ScreenTint.Level(dim: 5, warmth: -1), ScreenTint.Level(dim: 1, warmth: 0))
    }
}
