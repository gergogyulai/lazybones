import XCTest
@testable import Lazybones

@MainActor final class BrandTests: XCTestCase {
    private static let brands = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Brands", isDirectory: true)

    override func setUp() {
        Brand.directory = Self.brands
    }

    private var branded: [(Service, Brand)] {
        Service.defaults.compactMap { s in s.brand.map { (s, $0) } }
    }

    func testEveryStreamingServiceHasOfficialArtwork() {
        let test = ["adblock", "drm"]
        for s in Service.defaults where !test.contains(s.id) {
            XCTAssertNotNil(s.brand, s.id)
        }
    }

    func testEveryBrandFileLoads() {
        for (s, b) in branded {
            for name in [b.logo] + (b.mark.map { [$0] } ?? []) {
                let image = Brand.image(name)
                XCTAssertNotNil(image, "\(s.id): \(name)")
                XCTAssertGreaterThan(image?.size.width ?? 0, 0, "\(s.id): \(name)")
            }
        }
    }

    /// Every file is used, and every file says where it came from.
    func testEveryFileIsUsedAndSourced() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.brands.path).filter { $0 != "SOURCES.md" && !$0.hasPrefix(".") }
        let used = Set(branded.flatMap { [$0.1.logo] + ($0.1.mark.map { [$0] } ?? []) })
        XCTAssertEqual(Set(files), used)
        let sources = try String(contentsOf: Self.brands.appendingPathComponent("SOURCES.md"), encoding: .utf8)
        for f in files { XCTAssertTrue(sources.contains("`\(f)`"), "\(f) isn't in SOURCES.md") }
    }

    func testCustomAppsKeepTheirSymbol() {
        var s = Service.custom()
        XCTAssertNil(s.brand)
        s.id = "netflix"
        XCTAssertNil(s.brand, "only built-ins get official artwork")
    }

    func testBrandColorsWinOverSavedOnes() {
        var s = Service.defaults.first { $0.id == "netflix" }!
        s.tint = RGB(0, 1, 0)
        s.accentTint = RGB(0, 0, 1)
        let accent = RGB(s.accent!), red = RGB(hex: 0xE50914)
        XCTAssertEqual(accent.r, red.r, accuracy: 0.001)
        XCTAssertEqual(accent.g, red.g, accuracy: 0.001)
        XCTAssertEqual(accent.b, red.b, accuracy: 0.001)
    }
}
