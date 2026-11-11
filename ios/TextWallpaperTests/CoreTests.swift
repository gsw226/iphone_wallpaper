import XCTest
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
@testable import TextWallpaper

@MainActor
final class DesignStoreTests: XCTestCase {
    var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func sampleDesign() -> Design {
        var d = Design()
        d.dim = 0.4
        d.blocks.append(TextBlock(text: "두 번째", font: .pen, size: 0.1, color: .black,
                                  center: CGPoint(x: 0.3, y: 0.8), width: 0.5))
        return d
    }

    /// Solid grey PNG, built in an 8-bit grey bitmap so huge sizes stay cheap.
    private func solidPNG(_ size: CGSize, gray: CGFloat = 0.5) -> Data {
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: gray, alpha: 1)
        ctx.fill(CGRect(origin: .zero, size: size))
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return data as Data
    }

    func testSaveNowRoundTrips() {
        let store = DesignStore(directory: dir)
        let d = sampleDesign()
        store.design = d
        store.saveNow()
        XCTAssertEqual(DesignStore(directory: dir).design, d)
    }

    func testDesignAutosavesWithoutSaveNow() {
        let store = DesignStore(directory: dir)
        let d = sampleDesign()
        store.design = d
        let exp = expectation(description: "autosave")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(DesignStore(directory: dir).design, d)
    }

    /// Design() makes fresh block ids, so compare defaults with ids stripped.
    private func assertIsDefault(_ d: Design, file: StaticString = #filePath, line: UInt = #line) {
        var d = d, def = Design()
        for i in d.blocks.indices { d.blocks[i].id = UUID(uuid: UUID_NULL) }
        for i in def.blocks.indices { def.blocks[i].id = UUID(uuid: UUID_NULL) }
        XCTAssertEqual(d, def, file: file, line: line)
    }

    func testMissingFileGivesDefault() {
        assertIsDefault(DesignStore(directory: dir).design)
        XCTAssertNil(DesignStore(directory: dir).photo)
    }

    func testCorruptJSONGivesDefault() throws {
        try Data("{not json".utf8).write(to: dir.appending(path: "design.json"))
        assertIsDefault(DesignStore(directory: dir).design)
    }

    func testCorruptJSONIsPreservedAsBadFile() throws {
        let bad = Data("{not json".utf8)
        try bad.write(to: dir.appending(path: "design.json"))
        let store = DesignStore(directory: dir)
        store.saveNow()
        XCTAssertEqual(try Data(contentsOf: dir.appending(path: "design.bad.json")), bad)
    }

    func testInitDeletesUnreferencedPhotos() throws {
        try Data("x".utf8).write(to: dir.appending(path: "photo-orphan.jpg"))
        _ = DesignStore(directory: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appending(path: "photo-orphan.jpg").path))
    }

    func testSetPhotoWritesFileAndReloads() async throws {
        let store = DesignStore(directory: dir)
        try await store.setPhoto(solidPNG(CGSize(width: 400, height: 800)))
        guard case .photo(let name) = store.design.background else { return XCTFail("not photo") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appending(path: name).path))
        XCTAssertNotNil(store.photo)

        let reloaded = DesignStore(directory: dir)
        XCTAssertEqual(reloaded.design.background, .photo(name))
        XCTAssertNotNil(reloaded.photo)
    }

    func testSetPhotoReplacesPreviousFile() async throws {
        let store = DesignStore(directory: dir)
        try await store.setPhoto(solidPNG(CGSize(width: 400, height: 800)))
        guard case .photo(let first) = store.design.background else { return XCTFail() }
        try await store.setPhoto(solidPNG(CGSize(width: 400, height: 800), gray: 0.2))
        guard case .photo(let second) = store.design.background else { return XCTFail() }
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appending(path: first).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appending(path: second).path))
    }

    func testSetPhotoDownscalesHugeImage() async throws {
        let store = DesignStore(directory: dir)
        let out = WallpaperRenderer.outputSize
        try await store.setPhoto(solidPNG(CGSize(width: out.width * 4, height: out.height * 4)))
        let px = store.photo!.size.width * store.photo!.scale
        XCTAssertLessThanOrEqual(px, out.width * 1.5 + 1)
        XCTAssertGreaterThanOrEqual(px, out.width * 1.5 - 1)
    }

    /// A panorama must still shrink: cropped to the output aspect, at most 1.5× output.
    func testSetPhotoCropsAndDownscalesPanorama() async throws {
        let store = DesignStore(directory: dir)
        let out = WallpaperRenderer.outputSize
        try await store.setPhoto(solidPNG(CGSize(width: 16000, height: 3400)))
        let cg = try XCTUnwrap(store.photo?.cgImage)
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        XCTAssertLessThanOrEqual(w, out.width * 1.5 + 1)
        XCTAssertLessThanOrEqual(h, out.height * 1.5 + 1)
        XCTAssertEqual(w, h * out.width / out.height, accuracy: 1)
    }

    func testClearPhotoDeletesFileAndSetsColor() async throws {
        let store = DesignStore(directory: dir)
        try await store.setPhoto(solidPNG(CGSize(width: 400, height: 800)))
        guard case .photo(let name) = store.design.background else { return XCTFail() }
        store.clearPhoto(color: .black)
        XCTAssertEqual(store.design.background, .color(.black))
        XCTAssertNil(store.photo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appending(path: name).path))
        XCTAssertEqual(DesignStore(directory: dir).design.background, .color(.black))
    }

    func testMissingPhotoFileFallsBackToColor() throws {
        var d = sampleDesign()
        d.background = .photo("gone.jpg")
        try JSONEncoder().encode(d).write(to: dir.appending(path: "design.json"))
        let store = DesignStore(directory: dir)
        XCTAssertEqual(store.design.background, Design().background)
        XCTAssertNil(store.photo)
        XCTAssertEqual(store.design.blocks, d.blocks)
    }
}

/// RGBA8 pixel reader for rendered images.
struct Pixels {
    let width: Int, height: Int
    private var data: [UInt8]

    init(_ image: UIImage) {
        let cg = image.cgImage!
        width = cg.width; height = cg.height
        data = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// Red channel at (x, y), y from the top.
    func red(_ x: Int, _ y: Int) -> UInt8 { data[(y * width + x) * 4] }

    /// Pixels whose red channel exceeds 128 (white text on black).
    func inkCount() -> Int { stride(from: 0, to: data.count, by: 4).filter { data[$0] > 128 }.count }

    /// Bounding box of ink as fractions of the image.
    func inkBox() -> CGRect {
        var minX = width, minY = height, maxX = 0, maxY = 0
        for y in 0..<height { for x in 0..<width where red(x, y) > 128 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        return CGRect(x: Double(minX) / Double(width), y: Double(minY) / Double(height),
                      width: Double(maxX - minX) / Double(width), height: Double(maxY - minY) / Double(height))
    }
}

@MainActor
final class RendererTests: XCTestCase {
    private func textDesign(_ font: FontChoice = .sans) -> Design {
        var d = Design()
        d.background = .color(.black)
        d.blocks = [TextBlock(text: "가나다 라마\n바사아", font: font, size: 0.1, color: .white,
                              center: CGPoint(x: 0.5, y: 0.5), width: 0.8)]
        return d
    }

    func testRenderIsExactlyOutputSizePixels() {
        let img = WallpaperRenderer.render(Design(), photo: nil)!
        let out = WallpaperRenderer.outputSize
        XCTAssertEqual(CGFloat(img.cgImage!.width), out.width)
        XCTAssertEqual(CGFloat(img.cgImage!.height), out.height)
    }

    func testOutputSizeIsPortrait() {
        let out = WallpaperRenderer.outputSize
        XCTAssertGreaterThan(out.height, out.width)
    }

    func testPNGDataNonEmpty() {
        let png = WallpaperRenderer.pngData(Design(), photo: nil)
        XCTAssertGreaterThan(png?.count ?? 0, 1000)
    }

    func testTextDrawsNearBlockCenter() {
        let px = Pixels(WallpaperRenderer.render(textDesign(), photo: nil)!)
        XCTAssertEqual(px.red(5, 5), 0, "background should be black")
        let box = px.inkBox()
        XCTAssertGreaterThan(px.inkCount(), 1000)
        XCTAssertEqual(box.midX, 0.5, accuracy: 0.03)
        XCTAssertEqual(box.midY, 0.5, accuracy: 0.03)
    }

    func testPhotoBackgroundFillsWithDim() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let wide = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 100), format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 100))
        }
        var d = Design()
        d.background = .photo("x.jpg")
        d.dim = 0.5
        d.blocks = []
        let px = Pixels(WallpaperRenderer.render(d, photo: wide)!)
        // aspect-fill: every corner covered by the photo, dimmed to ~50% grey
        for (x, y) in [(1, 1), (px.width - 2, 1), (1, px.height - 2), (px.width - 2, px.height - 2)] {
            XCTAssertEqual(Double(px.red(x, y)), 127.5, accuracy: 6)
        }
    }

    func testLayoutIsResolutionIndependent() {
        func box(_ size: CGSize) -> CGRect {
            let r = ImageRenderer(content: WallpaperView(design: textDesign(), photo: nil)
                .frame(width: size.width, height: size.height))
            r.scale = 1
            let px = Pixels(r.uiImage!)
            XCTAssertGreaterThan(px.inkCount(), 100)
            return px.inkBox()
        }
        let small = box(CGSize(width: 393, height: 852)), big = box(CGSize(width: 1179, height: 2556))
        XCTAssertEqual(small.minX, big.minX, accuracy: 0.01)
        XCTAssertEqual(small.minY, big.minY, accuracy: 0.01)
        XCTAssertEqual(small.width, big.width, accuracy: 0.01)
        XCTAssertEqual(small.height, big.height, accuracy: 0.01)
    }
}

@MainActor
final class FontTests: XCTestCase {
    func testBundledFontsAreRegistered() {
        for name in ["NotoSansKR-Thin", "NotoSerifKR-ExtraLight", "GowunDodum-Regular", "NanumPen-Regular"] {
            XCTAssertNotNil(UIFont(name: name, size: 20), name)
        }
    }

    func testLabelsAreKorean() {
        XCTAssertEqual(FontChoice.allCases.map(\.label), ["고딕", "명조", "고운돋움", "손글씨"])
    }

    private func ink(_ font: Font) -> Int {
        let r = ImageRenderer(content: Text("가나다라마").font(font).foregroundStyle(.white)
            .padding(10).background(Color.black))
        r.scale = 1
        return Pixels(r.uiImage!).inkCount()
    }

    /// Variable Noto fonts must render at weight 700, not their thin default instance.
    func testNotoFontsRenderBold() {
        XCTAssertGreaterThan(ink(FontChoice.sans.font(size: 60)),
                             2 * ink(.custom("NotoSansKR-Thin", fixedSize: 60)))
        XCTAssertGreaterThan(ink(FontChoice.serif.font(size: 60)),
                             2 * ink(.custom("NotoSerifKR-ExtraLight", fixedSize: 60)))
    }
}
