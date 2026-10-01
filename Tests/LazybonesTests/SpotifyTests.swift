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
}
