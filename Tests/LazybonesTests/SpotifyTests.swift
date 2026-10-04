import XCTest
@testable import Lazybones

final class SpotifyTests: XCTestCase {
    func testMusicKeepsPlayingBehindTheHomeScreen() {
        let music: Set = ["spotify", "applemusic", "ytmusic", "soundcloud"]
        for module in ServiceModules.builtIn {
            // Music keeps playing; everything else is video and pauses.
            XCTAssertEqual(module.pausesInBackground, !music.contains(module.service.id), module.service.id)
        }
    }

    /// uBlock Origin Lite's audio-ad filters silence every track on these in WebKit.
    func testMusicWhoseAdFiltersBreakPlaybackGetsNoAdBlocking() {
        for module in ServiceModules.builtIn {
            XCTAssertEqual(module.allowsAdBlocking, !["spotify", "soundcloud"].contains(module.service.id), module.service.id)
        }
    }
}
