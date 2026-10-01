import MacSystem
import SiriRemote
import XCTest
@testable import Lazybones

final class LoadFailureTests: XCTestCase {
    private let url = URL(string: "https://www.netflix.com/browse")!

    private func failure(_ code: Int, domain: String = NSURLErrorDomain, firstLoad: Bool = true) -> LoadFailure? {
        LoadFailure(NSError(domain: domain, code: code, userInfo: [NSURLErrorFailingURLErrorKey: url]), firstLoad: firstLoad)
    }

    func testLoadsThatWereReplacedAreNotFailures() {
        XCTAssertNil(failure(NSURLErrorCancelled), "a redirect or a new navigation cancelling the last")
        XCTAssertNil(failure(102, domain: "WebKitErrorDomain"), "a download taking over from the page")
        XCTAssertNil(failure(204, domain: "WebKitErrorDomain"), "a media document taking over the load")
    }

    func testReasons() {
        XCTAssertEqual(failure(NSURLErrorNotConnectedToInternet)?.reason, .offline)
        XCTAssertEqual(failure(NSURLErrorNetworkConnectionLost)?.reason, .offline)
        XCTAssertEqual(failure(NSURLErrorCannotFindHost)?.reason, .unreachable)
        XCTAssertEqual(failure(NSURLErrorTimedOut)?.reason, .unreachable)
        XCTAssertEqual(failure(NSURLErrorSecureConnectionFailed)?.reason, .insecure)
        XCTAssertEqual(failure(NSURLErrorServerCertificateUntrusted)?.reason, .insecure)
        XCTAssertEqual(failure(NSURLErrorClientCertificateRequired)?.reason, .insecure)
        if case .other = failure(NSURLErrorBadServerResponse)?.reason {} else { XCTFail("anything else keeps its own description") }
    }

    func testOnlyNetworkTroubleRetriesByItself() {
        XCTAssertTrue(failure(NSURLErrorNotConnectedToInternet)!.retryWhenOnline)
        XCTAssertTrue(failure(NSURLErrorCannotConnectToHost)!.retryWhenOnline)
        XCTAssertFalse(failure(NSURLErrorServerCertificateUntrusted)!.retryWhenOnline)
    }

    func testRemembersWhatToLoadAgainAndNamesItsHost() {
        let f = failure(NSURLErrorTimedOut)!
        XCTAssertEqual(f.url, url)
        let netflix = Service.defaults.first { $0.id == "netflix" }!
        XCTAssertEqual(f.title(for: netflix), "Can’t Open Netflix")
        XCTAssertTrue(f.message(for: netflix).hasPrefix("www.netflix.com isn’t responding"))
    }
}

/// What the remote does while an app shows that its page couldn't load.
@MainActor
final class FailureScreenTests: XCTestCase {
    private var played: [UISound] = []

    private func model() -> AppModel {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "lazybones.tests.\(UUID())")!)
        store.save(LauncherSettings())
        let sounds = UISounds { [unowned self] in played.append($0) }
        return AppModel(options: LaunchOptions(arguments: ["--no-ext"]), store: store, startsRemote: false, sounds: sounds)
    }

    private func press(_ m: AppModel, _ c: RemoteCommand) {
        m.handle(RemoteEvent(command: c, source: .press))
    }

    /// Opens the first app and has its page fail.
    private func failing(_ m: AppModel, code: Int = NSURLErrorNotConnectedToInternet, firstLoad: Bool = true) -> Service {
        let s = m.visible[0]
        m.open(s)
        let error = NSError(domain: NSURLErrorDomain, code: code, userInfo: [NSURLErrorFailingURLErrorKey: s.url])
        m.web.onFailed?(s.id, LoadFailure(error, firstLoad: firstLoad)!)
        played = []
        return s
    }

    func testAFailureReplacesTheLaunchScreen() {
        let m = model()
        let s = failing(m)
        XCTAssertTrue(m.showsFailure)
        XCTAssertFalse(m.loading.contains(s.id))
    }

    func testClickTriesAgain() {
        let m = model()
        let s = failing(m)
        press(m, .select)
        XCTAssertFalse(m.showsFailure)
        XCTAssertTrue(m.loading.contains(s.id), "back to the launch screen while it loads")
        XCTAssertEqual(played, [.select])
    }

    func testDirectionsGoNowhere() {
        let m = model()
        let s = failing(m)
        press(m, .right)
        press(m, .down)
        XCTAssertEqual(m.active?.id, s.id)
        XCTAssertTrue(m.showsFailure)
        XCTAssertEqual(played, [])
    }

    func testBackGoesHomeWhenNothingHadLoaded() {
        let m = model()
        let s = failing(m)
        press(m, .back)
        XCTAssertNil(m.active)
        XCTAssertEqual(played, [.pop])
        m.open(s)
        XCTAssertFalse(m.showsFailure, "opening it again tries again")
        XCTAssertTrue(m.loading.contains(s.id))
    }

    func testBackReturnsToThePageThatWasShowing() {
        let m = model()
        let s = failing(m, firstLoad: false)
        press(m, .back)
        XCTAssertEqual(m.active?.id, s.id)
        XCTAssertFalse(m.showsFailure)
    }

    func testANewPageClearsTheFailure() {
        let m = model()
        let s = failing(m)
        m.web.onCommit?(s.id)
        XCTAssertFalse(m.showsFailure)
    }

    func testComingBackOnlineTriesAgain() {
        let m = model()
        let s = failing(m)
        m.controlCenter.network = NetworkInfo()
        XCTAssertTrue(m.showsFailure, "still offline")
        var online = NetworkInfo()
        online.kind = .wifi
        m.controlCenter.network = online
        XCTAssertFalse(m.showsFailure)
        XCTAssertTrue(m.loading.contains(s.id))
    }

    func testCertificateTroubleWaitsForTheUser() {
        let m = model()
        _ = failing(m, code: NSURLErrorServerCertificateUntrusted)
        var online = NetworkInfo()
        online.kind = .wifi
        m.controlCenter.network = NetworkInfo()
        m.controlCenter.network = online
        XCTAssertTrue(m.showsFailure)
    }
}

@MainActor
final class ParallaxTests: XCTestCase {
    func testFollowsTheThumbInScreenCoordinates() {
        let p = Parallax()
        p.update(SIMD2(0.5, 0.25))
        XCTAssertEqual(p.offset, CGSize(width: 0.5, height: -0.25), "the surface's y grows upward, the screen's down")
        p.update(nil)
        XCTAssertEqual(p.offset, .zero)
    }

    func testOnlyTheHomeScreenTilts() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "lazybones.tests.\(UUID())")!)
        let m = AppModel(options: LaunchOptions(arguments: ["--no-ext"]), store: store, startsRemote: false,
                         sounds: UISounds { _ in })
        m.remote.onTouchRest?(SIMD2(1, 0))
        XCTAssertEqual(m.parallax.offset.width, 1)
        m.toggleControlCenter()
        m.remote.onTouchRest?(SIMD2(1, 0))
        XCTAssertEqual(m.parallax.offset, .zero)
        m.toggleControlCenter()
        m.open(m.visible[0])
        m.remote.onTouchRest?(SIMD2(1, 0))
        XCTAssertEqual(m.parallax.offset, .zero)
    }
}
