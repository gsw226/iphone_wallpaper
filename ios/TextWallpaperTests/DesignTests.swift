import XCTest
@testable import TextWallpaper

final class DesignTests: XCTestCase {
    func testDesignRoundTrips() throws {
        let d = Design()
        XCTAssertEqual(try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(d)), d)
    }
}
