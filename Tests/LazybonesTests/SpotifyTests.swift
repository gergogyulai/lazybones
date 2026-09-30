import XCTest
@testable import Lazybones


final class SpotifyTests: XCTestCase {
    func testMusicKeepsPlayingBehindTheHomeScreen() {
        XCTAssertFalse(Spotify().pausesInBackground)
        // Everything else is video and pauses.
        for module in ServiceModules.builtIn where module.service.id != "spotify" {
            XCTAssertTrue(module.pausesInBackground, module.service.id)
        }
    }

    func testPlayPauseUsesThePlayerBar() {
        XCTAssertTrue(Spotify().playPauseScript?.contains("control-button-playpause") == true)
        XCTAssertNil(Netflix().playPauseScript)
    }

    func testItIsAWebPlayerFairPlayNeedsToLookLikeSafari() {
        let s = Spotify().service
        XCTAssertEqual(s.agent, .safari)
        XCTAssertEqual(s.url.host, "open.spotify.com")
        XCTAssertTrue(s.spatialNav)
    }
}

final class PageScriptsTests: XCTestCase {
    func testEveryPageGetsThePlaybackReporter() {
        XCTAssertTrue(Scripts.shared(spatialNav: false).contains { $0.source == Scripts.playback })
    }

    func testPauseCoversAudioToo() {
        XCTAssertTrue(Scripts.pause.contains("audio"))
    }
}
