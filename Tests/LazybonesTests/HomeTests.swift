import LGTV
import SiriRemote
import XCTest
@testable import Lazybones

final class GridFocusTests: XCTestCase {
    /// Seven apps in rows of five: a full row and a short one.
    private func focus(at i: Int) -> GridFocus {
        var f = GridFocus()
        f.select(i, columns: 5)
        return f
    }

    func testMovingWithinARow() {
        var f = focus(at: 1)
        XCTAssertTrue(f.move(.right, count: 7, columns: 5))
        XCTAssertEqual(f.index, 2)
        XCTAssertTrue(f.move(.left, count: 7, columns: 5))
        XCTAssertEqual(f.index, 1)
    }

    func testLeftAndRightNeverWrapOntoAnotherRow() {
        var f = focus(at: 5)
        XCTAssertFalse(f.move(.left, count: 7, columns: 5))
        XCTAssertEqual(f.index, 5)
        f = focus(at: 4)
        XCTAssertFalse(f.move(.right, count: 7, columns: 5))
        XCTAssertEqual(f.index, 4)
    }

    func testRightStopsAtTheLastApp() {
        var f = focus(at: 6)
        XCTAssertFalse(f.move(.right, count: 7, columns: 5))
        XCTAssertEqual(f.index, 6)
    }

    func testDownFromTheLastRowStaysPut() {
        var f = focus(at: 5)
        XCTAssertFalse(f.move(.down, count: 7, columns: 5))
        XCTAssertEqual(f.index, 5, "used to jump sideways to the last app")
    }

    func testDownIntoAShortRowLandsOnItsLastApp() {
        var f = focus(at: 4)
        XCTAssertTrue(f.move(.down, count: 7, columns: 5))
        XCTAssertEqual(f.index, 6)
    }

    func testVerticalMovesRememberTheColumn() {
        var f = focus(at: 4)
        _ = f.move(.down, count: 7, columns: 5)
        XCTAssertTrue(f.move(.up, count: 7, columns: 5))
        XCTAssertEqual(f.index, 4, "back in the column we left, not the short row's column")
    }

    func testMovingSidewaysUpdatesTheRememberedColumn() {
        var f = focus(at: 4)
        _ = f.move(.down, count: 7, columns: 5)   // 6
        _ = f.move(.left, count: 7, columns: 5)   // 5
        XCTAssertTrue(f.move(.up, count: 7, columns: 5))
        XCTAssertEqual(f.index, 0)
    }

    func testUpFromTheFirstRowReachesTheBarAndDownComesBack() {
        var f = focus(at: 3)
        XCTAssertTrue(f.move(.up, count: 7, columns: 5))
        XCTAssertTrue(f.onBar)
        XCTAssertFalse(f.move(.up, count: 7, columns: 5))
        XCTAssertFalse(f.move(.left, count: 7, columns: 5))
        XCTAssertFalse(f.move(.right, count: 7, columns: 5))
        XCTAssertTrue(f.move(.down, count: 7, columns: 5))
        XCTAssertFalse(f.onBar)
        XCTAssertEqual(f.index, 3, "same column as before")
    }

    func testAnEmptyHomeScreenOnlyHasTheBar() {
        var f = GridFocus()
        XCTAssertFalse(f.move(.down, count: 0, columns: 5))
        XCTAssertTrue(f.onBar)
    }

    func testClampKeepsFocusOnAnAppThatStillExists() {
        var f = focus(at: 6)
        f.clamp(count: 4, columns: 5)
        XCTAssertEqual(f.index, 3)
        f.clamp(count: 0, columns: 5)
        XCTAssertEqual(f.index, 0)
    }

    func testResetGoesBackToTheFirstApp() {
        var f = focus(at: 6)
        f.selectBar()
        f.reset(columns: 5)
        XCTAssertEqual(f, GridFocus())
    }
}

final class DoubleClickTests: XCTestCase {
    func testTwoQuickClicksAreADoubleClick() {
        var d = DoubleClick()
        XCTAssertFalse(d.click(at: 10))
        XCTAssertTrue(d.click(at: 10.3))
    }

    func testSlowClicksAreNot() {
        var d = DoubleClick()
        XCTAssertFalse(d.click(at: 10))
        XCTAssertFalse(d.click(at: 10.9))
    }

    func testAThirdClickStartsOver() {
        var d = DoubleClick()
        _ = d.click(at: 10)
        XCTAssertTrue(d.click(at: 10.2))
        XCTAssertFalse(d.click(at: 10.4))
    }

    func testResetForgetsTheLastClick() {
        var d = DoubleClick()
        _ = d.click(at: 10)
        d.reset()
        XCTAssertFalse(d.click(at: 10.1))
    }
}

final class LauncherLayoutTests: XCTestCase {
    private let size = CGSize(width: 1920, height: 1080)

    private func layout(selected: Int, count: Int = 12, shelf: Bool = true, appFocused: Bool = true) -> LauncherLayout {
        LauncherLayout(size: size, columns: 5, shelf: shelf, count: count, selected: selected, appFocused: appFocused)
    }

    func testTheFirstRowSitsBelowTheShelfWithoutScrolling() {
        let l = layout(selected: 0)
        XCTAssertFalse(l.scrolled)
        XCTAssertEqual(l.scrollOffset, 0)
        XCTAssertEqual(l.frame(of: 1).minY, l.metrics.rowTop(0), accuracy: 0.001)
    }

    func testFocusingALowerRowScrollsItToTheSettledPosition() {
        let l = layout(selected: 7)
        XCTAssertTrue(l.scrolled)
        // Row 1 settles at scrolledRowTop; the focused icon grows around its own center.
        let base = l.frame(of: 6)
        XCTAssertEqual(base.minY, l.metrics.scrolledRowTop, accuracy: 0.001)
    }

    func testTheFocusedIconGrowsAroundItsCenter() {
        let focused = layout(selected: 2).frame(of: 2)
        let plain = layout(selected: 2, appFocused: false).frame(of: 2)
        XCTAssertEqual(focused.midX, plain.midX, accuracy: 0.001)
        XCTAssertEqual(focused.midY, plain.midY, accuracy: 0.001)
        XCTAssertEqual(focused.width / plain.width, LauncherLayout.focusScale, accuracy: 0.001)
    }

    func testIconsInARowShareTheSameTop() {
        let l = layout(selected: 0, appFocused: false)
        XCTAssertEqual(l.frame(of: 5).minY, l.frame(of: 9).minY, accuracy: 0.001)
        XCTAssertEqual(l.frame(of: 5).minX, l.frame(of: 0).minX, accuracy: 0.001)
    }

    func testWithoutAShelfOnlyOverflowingRowsScroll() {
        XCTAssertFalse(layout(selected: 0, shelf: false).scrolled)
    }

    func testSelectionIsClampedToTheApps() {
        XCTAssertEqual(layout(selected: 99, count: 3).selected, 2)
    }
}

final class RecentsTests: XCTestCase {
    func testMostRecentFirstWithoutDuplicates() {
        var r = Recents()
        r.touch("a"); r.touch("b"); r.touch("a")
        XCTAssertEqual(r.ids, ["a", "b"])
        r.remove("a")
        XCTAssertEqual(r.ids, ["b"])
    }
}

@MainActor
final class AppSwitcherTests: XCTestCase {
    private let apps = Array(Service.defaults.prefix(3))

    func testOpensOnTheMostRecentApp() {
        let s = AppSwitcher()
        s.open(apps)
        XCTAssertTrue(s.isOpen)
        XCTAssertEqual(s.focus, 0)
        XCTAssertEqual(s.handle(.select), .resume(apps[0]))
    }

    func testMovesAlongTheRowWithoutWrapping() {
        let s = AppSwitcher()
        s.open(apps)
        XCTAssertNil(s.handle(.left))
        XCTAssertEqual(s.focus, 0)
        _ = s.handle(.right); _ = s.handle(.right); _ = s.handle(.right)
        XCTAssertEqual(s.focus, 2)
    }

    func testUpClosesTheFocusedApp() {
        let s = AppSwitcher()
        s.open(apps)
        _ = s.handle(.right)
        XCTAssertEqual(s.handle(.up), .quit(apps[1]))
    }

    func testRemovingAnAppKeepsFocusInRange() {
        let s = AppSwitcher()
        s.open(apps)
        _ = s.handle(.right); _ = s.handle(.right)
        s.remove(apps[2].id)
        XCTAssertEqual(s.apps, [apps[0], apps[1]])
        XCTAssertEqual(s.focus, 1)
    }

    func testBackDismissesAndSelectingNothingDoes() {
        let s = AppSwitcher()
        s.open([])
        XCTAssertEqual(s.handle(.select), .dismiss)
        XCTAssertNil(s.handle(.up))
        XCTAssertEqual(s.handle(.back), .dismiss)
    }
}

@MainActor
final class SettingsScreenTests: XCTestCase {
    private var log: [String] = []

    /// A header, a toggle, a slider and a note: only the middle two take focus.
    private func screen() -> SettingsScreen {
        let s = SettingsScreen()
        s.rowsProvider = { [unowned self] _ in [
            SettingsRow(id: "h", title: "Heading", style: .header),
            SettingsRow(id: "t", title: "Toggle", style: .toggle(false), activate: { self.log.append("toggle") }),
            SettingsRow(id: "s", title: "Slider", style: .slider(0.5, label: "50%"), adjust: { self.log.append("adjust \($0)") }),
            SettingsRow(id: "n", title: "Note", style: .note),
        ] }
        s.open(page: .homeScreen)
        return s
    }

    func testOpensWithFocusInThePageList() {
        let s = screen()
        XCTAssertTrue(s.isOpen)
        XCTAssertTrue(s.inSidebar)
    }

    func testEnteringTheRowsSkipsRowsThatOnlyShowInformation() {
        let s = screen()
        s.handle(.right)
        XCTAssertFalse(s.inSidebar)
        XCTAssertEqual(s.row, 1)
        s.handle(.down)
        XCTAssertEqual(s.row, 2)
        s.handle(.down)
        XCTAssertEqual(s.row, 2, "the note below can't be focused")
        s.handle(.up); s.handle(.up)
        XCTAssertEqual(s.row, 1, "the heading above can't be focused")
    }

    func testSelectActivatesAndSideArrowsAdjust() {
        let s = screen()
        s.handle(.select)
        s.handle(.select)
        s.handle(.down)
        s.handle(.left)
        s.handle(.right)
        XCTAssertEqual(log, ["toggle", "adjust -1", "adjust 1"])
        XCTAssertFalse(s.inSidebar, "left on a slider adjusts it rather than leaving")
    }

    func testLeftOnARowThatCantAdjustGoesBackToThePageList() {
        let s = screen()
        s.handle(.right)
        s.handle(.left)
        XCTAssertTrue(s.inSidebar)
    }

    func testBackStepsOutThenCloses() {
        let s = screen()
        s.handle(.right)
        s.handle(.back)
        XCTAssertTrue(s.inSidebar)
        XCTAssertTrue(s.isOpen)
        s.handle(.back)
        XCTAssertFalse(s.isOpen)
    }

    func testPageListMovesBetweenPages() {
        let s = screen()
        s.handle(.down)
        XCTAssertEqual(s.page, .apps)
        s.handle(.up)
        s.handle(.up)
        XCTAssertEqual(s.page, .homeScreen)
    }
}

/// The app's decisions about what a button press means, with no hardware and no saved settings.
@MainActor
final class AppModelTests: XCTestCase {
    private var played: [UISound] = []

    private func model(_ settings: LauncherSettings = LauncherSettings()) -> AppModel {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "lazybones.tests.\(UUID())")!)
        store.save(settings)
        let sounds = UISounds { [unowned self] in played.append($0) }
        return AppModel(options: LaunchOptions(arguments: ["--no-ext"]), store: store, startsRemote: false, sounds: sounds)
    }

    private func press(_ m: AppModel, _ c: RemoteCommand) {
        m.handle(RemoteEvent(command: c, source: .press))
    }

    func testDoubleClickingHomeOpensTheSwitcher() {
        let m = model()
        press(m, .home)
        XCTAssertFalse(m.switcher.isOpen)
        press(m, .home)
        XCTAssertTrue(m.switcher.isOpen)
    }

    func testHomeClosesTheSwitcherRatherThanReopeningIt() {
        let m = model()
        press(m, .home); press(m, .home)
        press(m, .home)
        XCTAssertFalse(m.switcher.isOpen)
    }

    func testBackClosesTheSwitcher() {
        let m = model()
        m.openSwitcher()
        press(m, .back)
        XCTAssertFalse(m.switcher.isOpen)
    }

    func testFocusStaysInsideTheGrid() {
        let m = model()
        press(m, .left)
        XCTAssertEqual(m.selected, 0)
        for _ in 0..<20 { press(m, .right) }
        XCTAssertEqual(m.selected, 4, "the end of the first row, not the next row")
        for _ in 0..<20 { press(m, .down) }
        XCTAssertEqual(m.selected, m.visible.count - 1, "down ends on the last row's app and stays there")
    }

    func testMovingFocusPlaysTheMoveSoundOnlyWhenItMoved() {
        let m = model()
        press(m, .left)
        XCTAssertEqual(played, [], "already at the edge")
        press(m, .right)
        press(m, .down)
        XCTAssertEqual(played, [.move, .move])
    }

    func testOpeningAScreenIsAPushAndGoingBackIsAPop() {
        let m = model()
        press(m, .up)
        press(m, .select)
        XCTAssertTrue(m.settingsScreen.isOpen)
        XCTAssertEqual(played, [.move, .push], "a rising push, in place of the select sound")
        press(m, .back)
        XCTAssertEqual(played, [.move, .push, .pop])
    }

    func testGoingDeeperInsideSettingsIsAPushToo() {
        let m = model()
        m.openSettingsScreen()
        played = []
        press(m, .right)
        XCTAssertFalse(m.settingsScreen.inSidebar)
        press(m, .back)
        XCTAssertEqual(played, [.push, .pop])
    }

    func testSelectingSomethingThatStaysPutPlaysTheSelectSound() {
        let m = model()
        m.openSettingsScreen(page: .homeScreen)
        press(m, .right)
        played = []
        press(m, .down)
        press(m, .select)
        XCTAssertEqual(played, [.move, .select])
    }

    func testOverlaysPushPopAndMakeTheirOwnNavigationSounds() {
        let m = model()
        m.toggleControlCenter()
        press(m, .down)
        press(m, .down)
        m.toggleControlCenter()
        XCTAssertEqual(played, [.push, .move, .move, .pop])
    }

    func testSoundsFollowWhateverWayInTheUserTook() {
        let m = model()
        m.openSwitcher()
        m.homePressed()
        XCTAssertEqual(played, [.push, .pop])
    }

    func testNoSoundsWhenTurnedOff() {
        var settings = LauncherSettings()
        settings.navigationSounds = false
        let m = model(settings)
        press(m, .right)
        press(m, .select)
        XCTAssertEqual(played, [])
    }

    func testTogglingTheSettingTakesEffectAtOnce() {
        let m = model()
        m.settings.navigationSounds = false
        press(m, .right)
        XCTAssertEqual(played, [])
        m.settings.navigationSounds = true
        press(m, .right)
        XCTAssertEqual(played, [.move])
    }

    func testEdgeMovesStillTiltTheIconButHeldOnesDont() {
        let m = model()
        let before = m.navTick
        press(m, .left)
        XCTAssertEqual(m.navTick, before + 1)
        m.handle(RemoteEvent(command: .left, source: .repeat))
        XCTAssertEqual(m.navTick, before + 1)
    }

    func testUpFromTheFirstRowReachesSettingsAndSelectOpensThem() {
        let m = model()
        press(m, .up)
        XCTAssertTrue(m.focus.onBar)
        press(m, .select)
        XCTAssertTrue(m.settingsScreen.isOpen)
        press(m, .back)
        press(m, .back)
        XCTAssertFalse(m.settingsScreen.isOpen)
    }

    func testHomeOnTheHomeScreenGoesBackToTheFirstApp() {
        let m = model()
        press(m, .right); press(m, .right)
        press(m, .home)
        XCTAssertEqual(m.selected, 0)
    }

    func testBackOnTheHomeScreenDoesNothing() {
        let m = model()
        press(m, .right)
        press(m, .back)
        XCTAssertEqual(m.selected, 1)
        XCTAssertFalse(m.settingsScreen.isOpen)
        XCTAssertNil(m.active)
    }

    func testControlCenterOpensOnAHold() {
        let m = model()
        m.handle(RemoteEvent(command: .home, source: .hold))
        XCTAssertTrue(m.controlCenter.isOpen)
        press(m, .back)
        XCTAssertFalse(m.controlCenter.isOpen)
    }

    func testTheSettingsScreenLetsYouReorderAppsWithTheSideArrows() {
        let m = model()
        let first = m.settings.services[0].id, second = m.settings.services[1].id
        let row = m.settingsRows(for: .apps)[0]
        row.adjust?(1)
        XCTAssertEqual(m.settings.services[0].id, second)
        XCTAssertEqual(m.settings.services[1].id, first)
        // Moving off the start does nothing.
        m.settingsRows(for: .apps)[0].adjust?(-1)
        XCTAssertEqual(m.settings.services[0].id, second)
    }

    func testClickingAnAppInSettingsOpensItsOwnSettingsAndBackReturnsToIt() {
        let m = model()
        let id = m.settings.services[2].id
        m.openSettingsScreen(page: .apps)
        press(m, .right)
        press(m, .down); press(m, .down)
        played = []
        press(m, .select)
        XCTAssertEqual(m.settingsScreen.app, id)
        XCTAssertFalse(m.settingsScreen.inSidebar)
        press(m, .back)
        XCTAssertNil(m.settingsScreen.app)
        XCTAssertEqual(m.settingsScreen.row, 2, "focus goes back to the app it came from")
        XCTAssertEqual(played, [.push, .pop])
    }

    func testAnAppsOwnSettingsShowAndHideIt() {
        let m = model()
        let id = m.settings.services[0].id
        m.openSettingsScreen(page: .apps)
        m.settingsScreen.show(app: id)
        let shown = { m.settingsRows(for: .apps).first { $0.id == "app-shown" }! }
        shown().activate?()
        XCTAssertTrue(m.settings.hidden.contains(id))
        shown().activate?()
        XCTAssertFalse(m.settings.hidden.contains(id))
    }

    func testSleepSettingsAdjustInSteps() {
        let m = model()
        let dim = m.settingsRows(for: .sleepMode).first { $0.id == "dim" }!
        for _ in 0..<20 { dim.adjust?(1) }
        XCTAssertEqual(m.settings.sleepDim, LauncherSettings.maxSleepDim, accuracy: 0.001, "capped so the screen never goes black")
        let warmth = m.settingsRows(for: .sleepMode).first { $0.id == "warmth" }!
        for _ in 0..<20 { warmth.adjust?(-1) }
        XCTAssertEqual(m.settings.sleepWarmth, 0, accuracy: 0.001)
    }

    func testControlCenterTileSettingIsOffByDefaultAndToggleable() {
        let m = model()
        XCTAssertFalse(m.settings.sleepInControlCenter)
        m.settingsRows(for: .sleepMode).first { $0.id == "sleep-cc" }!.activate?()
        XCTAssertTrue(m.settings.sleepInControlCenter)
    }

    func testHidingAnAppKeepsFocusOnARealOne() {
        let m = model()
        for _ in 0..<4 { press(m, .right) }
        m.settings.hidden = Set(m.settings.services.dropFirst(2).map(\.id))
        XCTAssertEqual(m.selected, 1)
    }
}


@MainActor
final class ControlCenterQuitTests: XCTestCase {
    private func controlCenter() -> ControlCenter {
        let tv = TVLink()
        return ControlCenter(audio: VolumeRouter(tv: tv) { _, _ in }, tv: tv, sleepTimer: SleepTimer())
    }

    private func focusQuit(_ cc: ControlCenter) {
        cc.focus = .quit
    }

    func testQuitNeedsASecondClick() {
        let cc = controlCenter()
        focusQuit(cc)
        XCTAssertNil(cc.handle(.select), "the first click only asks")
        XCTAssertTrue(cc.confirmingQuit)
        XCTAssertEqual(cc.handle(.select), .quit)
    }

    func testMovingAwayForgetsTheFirstClick() {
        let cc = controlCenter()
        focusQuit(cc)
        _ = cc.handle(.select)
        _ = cc.handle(.left)
        XCTAssertFalse(cc.confirmingQuit)
        _ = cc.handle(.right)
        XCTAssertNil(cc.handle(.select), "asks again rather than quitting")
    }

    func testOpeningControlCenterStartsUnconfirmed() {
        let cc = controlCenter()
        focusQuit(cc)
        _ = cc.handle(.select)
        cc.open(canReload: false, showsSleepMode: false, sleepModeOn: false)
        XCTAssertFalse(cc.confirmingQuit)
    }
}
