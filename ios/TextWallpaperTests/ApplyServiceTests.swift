import XCTest
@testable import TextWallpaper

final class ApplyServiceTests: XCTestCase {
    func testShortcutURLRoundTrips() throws {
        let url = try XCTUnwrap(ApplyService.shortcutURL)
        XCTAssertFalse(url.absoluteString.contains("textwallpaper://"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let q = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(q["name"], "문장 배경화면")
        XCTAssertEqual(q["input"], "clipboard")
        XCTAssertEqual(q["x-success"], "textwallpaper://done")
        XCTAssertEqual(q["x-error"], "textwallpaper://error")
    }

    func testHandle() {
        XCTAssertNotNil(ApplyService.handle(url: URL(string: "textwallpaper://done")!))
        XCTAssertTrue(ApplyService.handle(url: URL(string: "textwallpaper://error?errorMessage=x")!)!.contains("x"))
        XCTAssertNil(ApplyService.handle(url: URL(string: "https://example.com")!))
    }
}
