import SiriRemote
import XCTest
@testable import Lazybones

/// Which clicks press in the focused item: the launcher's and its screens', not a page's.
@MainActor
final class PressTests: XCTestCase {
    private func model() -> AppModel {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "lazybones.tests.\(UUID())")!)
        return AppModel(options: LaunchOptions(arguments: ["--no-ext"]), store: store, startsRemote: false,
                        sounds: UISounds { _ in })
    }

    private func press(_ m: AppModel, _ c: RemoteCommand) {
        m.handle(RemoteEvent(command: c, source: .press))
    }

    func testAClickInSettingsPressesTheFocusedRow() {
        let m = model()
        m.openSettingsScreen(page: .homeScreen)
        press(m, .right)
        let before = m.presses
        press(m, .select)
        XCTAssertEqual(m.presses, before + 1)
    }

    func testAClickInControlCenterPressesTheFocusedTile() {
        let m = model()
        m.toggleControlCenter()
        press(m, .down) // off Volume, where a click would mute the Mac
        press(m, .select)
        XCTAssertEqual(m.presses, 1)
    }

    func testMovingIsNotAPress() {
        let m = model()
        press(m, .right)
        press(m, .down)
        XCTAssertEqual(m.presses, 0)
    }

    func testAClickInsideAnAppIsThePagesOwn() {
        let m = model()
        m.open(m.visible[0])
        press(m, .select)
        XCTAssertEqual(m.presses, 0)
    }
}
