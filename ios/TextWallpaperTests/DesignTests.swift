import XCTest
@testable import TextWallpaper

final class DesignTests: XCTestCase {
    func testDesignRoundTrips() throws {
        let d = Design()
        XCTAssertEqual(try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(d)), d)
    }

    /// Older files lack fields added later; those must fall back to defaults, not fail.
    func testMissingFieldsDecodeWithDefaults() throws {
        let json = #"{"background":{"color":{"_0":{"r":0,"g":0,"b":0,"a":1}}},"blocks":[{"text":"hi"}]}"#
        let d = try JSONDecoder().decode(Design.self, from: Data(json.utf8))
        XCTAssertEqual(d.dim, Design().dim)
        XCTAssertEqual(d.background, .color(.black))
        let b = try XCTUnwrap(d.blocks.first), def = TextBlock(text: "")
        XCTAssertEqual(b.text, "hi")
        XCTAssertEqual(b.font, def.font)
        XCTAssertEqual(b.size, def.size)
        XCTAssertEqual(b.color, def.color)
        XCTAssertEqual(b.center, def.center)
        XCTAssertEqual(b.width, def.width)
    }
}
