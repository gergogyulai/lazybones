import XCTest
@testable import Lazybones

final class SettingsTests: XCTestCase {
    private func decode(_ json: String) throws -> LauncherSettings {
        try JSONDecoder().decode(LauncherSettings.self, from: Data(json.utf8))
    }

    func testSettingsFromAnOlderBuildStillLoad() throws {
        let s = try decode(#"{"columns": 4, "hidden": ["plex"]}"#)
        XCTAssertEqual(s.columns, 4)
        XCTAssertEqual(s.hidden, ["plex"])
        XCTAssertEqual(s.services, Service.defaults)
        XCTAssertTrue(s.showShelf)
        XCTAssertEqual(s.sleepDim, LauncherSettings().sleepDim)
        XCTAssertFalse(s.sleepInControlCenter)
        XCTAssertEqual(s.homeMotion, .lively)
        XCTAssertEqual(s.focusSize, .medium)
        XCTAssertEqual(s.iconLabels, .focused)
        XCTAssertTrue(s.showClock)
    }

    func testAnUnknownHomeStyleFallsBackToTheDefault() throws {
        let s = try decode(#"{"homeMotion": "wobbly", "focusSize": "large"}"#)
        XCTAssertEqual(s.homeMotion, .lively)
        XCTAssertEqual(s.focusSize, .large)
    }

    func testAppsSavedBeforeExtensionsWerePerAppStillLoadWithThemOn() throws {
        let s = try decode(#"""
        {"services": [{"id": "x", "name": "X", "url": "https://example.com", "tint": {"r": 0, "g": 0, "b": 0},
                       "agent": "safari", "spatialNav": true, "symbol": "globe", "tagline": "", "builtIn": false}]}
        """#)
        XCTAssertEqual(s.services.first?.blocksAds, true)
        XCTAssertEqual(s.services.first?.skipsSponsors, true)
        XCTAssertEqual(s.services.first?.symbol, "globe")
    }

    func testHiddenServicesAreLeftOutOfTheHomeScreen() throws {
        var s = LauncherSettings()
        s.hidden = ["netflix"]
        XCTAssertFalse(s.visibleServices.contains { $0.id == "netflix" })
        XCTAssertEqual(s.visibleServices.count, s.services.count - 1)
    }

    func testNewBuiltInsGoAfterTheirPredecessor() {
        var s = LauncherSettings()
        s.services.removeAll { $0.id == "netflix" }
        let merged = s.mergingNewBuiltIns()
        let ids = merged.services.map(\.id)
        let youtube = ids.firstIndex(of: "youtube")!
        XCTAssertEqual(ids[youtube + 1], "netflix")
        XCTAssertEqual(ids.count, Service.defaults.count)
    }

    func testMergingKeepsUserOrderAndCustomApps() {
        var s = LauncherSettings()
        let custom = Service.custom()
        s.services = [custom] + s.services.reversed()
        let merged = s.mergingNewBuiltIns()
        XCTAssertEqual(merged.services.map(\.id), s.services.map(\.id))
    }

    func testStoreRoundTrips() {
        let defaults = UserDefaults(suiteName: "lazybones.tests.\(UUID())")!
        let store = SettingsStore(defaults: defaults)
        var s = LauncherSettings()
        s.columns = 6
        s.hidden = ["emby"]
        store.save(s)
        XCTAssertEqual(store.load(), s)
    }

    func testUnreadableSettingsAreKeptAside() {
        let defaults = UserDefaults(suiteName: "lazybones.tests.\(UUID())")!
        defaults.set(Data("not json".utf8), forKey: "launcherSettings")
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.load(), LauncherSettings())
        XCTAssertNotNil(defaults.data(forKey: "launcherSettings.unreadable"))
    }

}

final class ServiceTests: XCTestCase {
    func testAddressesWithoutASchemeGetHTTPS() {
        XCTAssertEqual(Service.url(from: "example.com"), URL(string: "https://example.com"))
        XCTAssertEqual(Service.url(from: "  example.com/tv "), URL(string: "https://example.com/tv"))
    }

    func testLocalServersKeepTheirScheme() {
        XCTAssertEqual(Service.url(from: "http://192.168.1.5:8096/web/"), URL(string: "http://192.168.1.5:8096/web/"))
    }

    func testNonWebAddressesAreRejected() {
        XCTAssertNil(Service.url(from: ""))
        XCTAssertNil(Service.url(from: "ftp://example.com"))
        XCTAssertNil(Service.url(from: "https://"))
    }

    func testEveryBuiltInHasAUniqueID() {
        let ids = Service.defaults.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(Service.defaults.allSatisfy(\.builtIn))
    }

    func testModulesAreFoundByServiceID() {
        for s in Service.defaults {
            XCTAssertEqual(ServiceModules.module(for: s).service.id, s.id)
        }
        XCTAssertFalse(ServiceModules.handlesNavigation(Service.custom()))
        XCTAssertTrue(ServiceModules.handlesNavigation(Service.defaults.first { $0.id == "jellyfin" }!))
    }

    func testYouTubeTVAsksForFullAnimation() {
        let yt = YouTube()
        let url = yt.startURL(for: yt.service)
        XCTAssertTrue(url.absoluteString.contains("env_forceFullAnimation=true"))
        var other = yt.service
        other.url = URL(string: "https://example.com")!
        XCTAssertEqual(yt.startURL(for: other), other.url)
    }
}
