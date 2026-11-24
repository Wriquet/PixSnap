import Testing
import Cocoa
import CoreGraphics
@testable import PixSnap

@Test func testColorFormattingAndCycling() {
    #expect(ColorCopyFormat.hex.format(r: 255, g: 59, b: 48) == "#FF3B30")
    #expect(ColorCopyFormat.hexNoHash.format(r: 255, g: 59, b: 48) == "FF3B30")
    #expect(ColorCopyFormat.rgb.format(r: 255, g: 59, b: 48) == "rgb(255, 59, 48)")
    #expect(ColorCopyFormat.hsl.format(r: 255, g: 0, b: 0) == "hsl(0, 100%, 50%)")
    #expect(ColorCopyFormat.hex.next == .hexNoHash)
    #expect(ColorCopyFormat.hsl.next == .hex)
}

@Test func testMultiMonitorWindowCoordinateConversion() {
    // Primary monitor 1440x900 at (0,0); Secondary monitor 1920x1080 positioned to the right at (1440, 0)
    let primaryHeight: CGFloat = 900
    let secondaryFrame = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    // A window on the secondary monitor in CG top-left coordinates:
    // x=1540, y=100, w=800, h=600 -> Cocoa global y = 900 - (100 + 600) = 200
    // Local to secondaryFrame (origin 1440, 0) -> x=100, y=200, w=800, h=600
    let cgRect = CGRect(x: 1540, y: 100, width: 800, height: 600)
    let local = WindowDetector.convertAndLocalize(
        cgRect: cgRect,
        primaryScreenHeight: primaryHeight,
        targetScreenFrame: secondaryFrame
    )

    #expect(local == CGRect(x: 100, y: 200, width: 800, height: 600))

    // Window completely on primary monitor should return nil for secondary monitor
    let primaryWindow = CGRect(x: 50, y: 50, width: 400, height: 300)
    let miss = WindowDetector.convertAndLocalize(
        cgRect: primaryWindow,
        primaryScreenHeight: primaryHeight,
        targetScreenFrame: secondaryFrame
    )
    #expect(miss == nil)
}

@Test func testAnnotationHitTestingAndTranslation() {
    let rect = Annotation(
        type: .rect,
        lineWidth: 4,
        startPoint: CGPoint(x: 100, y: 100),
        endPoint: CGPoint(x: 200, y: 200),
        isFilled: false
    )
    // On border -> hit
    #expect(rect.hitTest(point: CGPoint(x: 100, y: 150)))
    // Deep inside hollow rect -> miss
    #expect(!rect.hitTest(point: CGPoint(x: 150, y: 150)))

    let moved = rect.translated(by: 50, dy: -20)
    #expect(moved.startPoint == CGPoint(x: 150, y: 80))
    #expect(moved.endPoint == CGPoint(x: 250, y: 180))

    let counter = Annotation(type: .counter, lineWidth: 14, startPoint: CGPoint(x: 50, y: 50), counterNumber: 3)
    #expect(counter.hitTest(point: CGPoint(x: 55, y: 55)))
    #expect(!counter.hitTest(point: CGPoint(x: 90, y: 90)))
}

@Test func testShiftConstrainedEndpoints() {
    let squareEnd = Annotation.constrainEndPoint(
        from: CGPoint(x: 10, y: 10),
        to: CGPoint(x: 60, y: 30),
        for: .rect
    )
    #expect(squareEnd == CGPoint(x: 60, y: 60))

    let horizontalArrow = Annotation.constrainEndPoint(
        from: CGPoint(x: 0, y: 0),
        to: CGPoint(x: 100, y: 10),
        for: .arrow
    )
    #expect(abs(horizontalArrow.y) < 0.01)
    #expect(horizontalArrow.x > 99)
}

@Test func testGlobalShortcutValidation() {
    // Bare 'A' (keyCode 0) must be rejected so typing isn't hijacked
    #expect(!HotKeyManager.isValidGlobalShortcut(keyCode: 0, modifiers: []))
    // Shift-only 'A' must be rejected
    #expect(!HotKeyManager.isValidGlobalShortcut(keyCode: 0, modifiers: [.shift]))
    // Cmd+Shift+X allowed
    #expect(HotKeyManager.isValidGlobalShortcut(keyCode: 7, modifiers: [.command, .shift]))
    // Bare F1 (122) allowed
    #expect(HotKeyManager.isValidGlobalShortcut(keyCode: 122, modifiers: []))
}

@Test @MainActor func testTextAnnotationRendersIntoExportedImageAndPreservesDisplayP3() throws {
    // Create a solid black 200x200 Display P3 backing image (scale 2.0 -> 100x100 logical)
    let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
    let ctx = try #require(CGContext(
        data: nil,
        width: 200,
        height: 200,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: p3,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
    let baseCG = try #require(ctx.makeImage())

    let textAnnot = Annotation(
        type: .text,
        color: .white,
        startPoint: CGPoint(x: 10, y: 35),
        text: "PIXSNAP",
        fontSize: 22
    )

    let output = try #require(ImageExporter.renderCroppedImage(
        fullImage: baseCG,
        bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
        selectionRect: CGRect(x: 0, y: 0, width: 100, height: 100),
        scaleFactor: 2.0,
        annotations: [textAnnot],
        mosaicImage: nil,
        blurImage: nil
    ))

    // 1. Display P3 color space must be preserved!
    #expect(output.cgImage.colorSpace?.name == CGColorSpace.displayP3)

    // 2. Verify bright text pixels actually exist in exported bitmap (regression test for missing text bug!)
    let rep = NSBitmapImageRep(cgImage: output.cgImage)
    var brightPixelCount = 0
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.redComponent > 0.5 {
                brightPixelCount += 1
            }
        }
    }
    #expect(brightPixelCount > 50)

    // 3. Direct PNG & JPEG encoding must produce valid non-empty headers
    let pngData = try #require(ImageExporter.encode(cgImage: output.cgImage, format: .png, scaleFactor: 2.0))
    #expect(pngData.starts(with: [0x89, 0x50, 0x4E, 0x47])) // PNG magic bytes

    let jpgData = try #require(ImageExporter.encode(cgImage: output.cgImage, format: .jpeg, scaleFactor: 2.0))
    #expect(jpgData.starts(with: [0xFF, 0xD8, 0xFF])) // JPEG magic bytes
}

@Test @MainActor func testMagnifierZeroCopyPixelSamplingAtCornerAndCenter() throws {
    let cs = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let ctx = try #require(CGContext(
        data: nil,
        width: 40,
        height: 40,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    // Left half red (#FF0000), right half blue (#0000FF)
    ctx.setFillColor(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 40))
    ctx.setFillColor(NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1).cgColor)
    ctx.fill(CGRect(x: 20, y: 0, width: 20, height: 40))
    let img = try #require(ctx.makeImage())

    let mag = MagnifierView()
    mag.colorFormat = .hex

    // Exact corner (0, 0) must not crash and must sample red
    mag.update(at: CGPoint(x: 0, y: 0), in: img, viewSize: CGSize(width: 20, height: 20), scaleFactor: 2.0, selectionRect: nil)
    #expect(mag.currentRGB.r > 240 && mag.currentRGB.b < 15)
    #expect(mag.currentColorString == "#FF0000")

    // Right side must sample blue
    mag.update(at: CGPoint(x: 15, y: 10), in: img, viewSize: CGSize(width: 20, height: 20), scaleFactor: 2.0, selectionRect: nil)
    #expect(mag.currentRGB.b > 240 && mag.currentRGB.r < 15)
    #expect(mag.currentColorString == "#0000FF")
}

@Test @MainActor func testClipboardTextCardRendering() throws {
    let card = try #require(ImageExporter.renderTextCardImage(text: "Hello PixSnap 2.0\n测试贴图卡片", scaleFactor: 2.0))
    #expect(card.nsImage.size.width >= 140)
    #expect(card.nsImage.size.height >= 56)
    #expect(card.cgImage.width == Int(round(card.nsImage.size.width * 2.0)))
}

@Test @MainActor func testSharpVsRoundedSelectionExport() throws {
    let cs = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let ctx = try #require(CGContext(
        data: nil,
        width: 200,
        height: 200,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    ctx.setFillColor(NSColor(srgbRed: 0.2, green: 0.6, blue: 0.9, alpha: 1.0).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
    let baseCG = try #require(ctx.makeImage())

    // 1. Sharp export (0px) -> corner pixel (0,0) must remain fully opaque
    let sharpOut = try #require(ImageExporter.renderCroppedImage(
        fullImage: baseCG,
        bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
        selectionRect: CGRect(x: 0, y: 0, width: 100, height: 100),
        scaleFactor: 2.0,
        annotations: [],
        mosaicImage: nil,
        blurImage: nil,
        selectionCornerRadius: 0
    ))
    let sharpRep = NSBitmapImageRep(cgImage: sharpOut.cgImage)
    #expect((sharpRep.colorAt(x: 0, y: 0)?.alphaComponent ?? 0) > 0.95)

    // 2. Rounded export (14pt) -> corner pixel (0,0) must be transparent, center opaque
    let roundedOut = try #require(ImageExporter.renderCroppedImage(
        fullImage: baseCG,
        bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
        selectionRect: CGRect(x: 0, y: 0, width: 100, height: 100),
        scaleFactor: 2.0,
        annotations: [],
        mosaicImage: nil,
        blurImage: nil,
        selectionCornerRadius: 14
    ))
    let roundedRep = NSBitmapImageRep(cgImage: roundedOut.cgImage)
    #expect((roundedRep.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.05)
    #expect((roundedRep.colorAt(x: 100, y: 100)?.alphaComponent ?? 0) > 0.95)
}

@Test @MainActor func testPinHistoryStoreRollbackAndCapacityCap() {
    let store = PinHistoryStore(maxCount: 3)
    let img = NSImage(size: NSSize(width: 100, height: 80))

    let r1 = ClosedPinRecord(image: img, frame: NSRect(x: 10, y: 10, width: 100, height: 80), baseSize: NSSize(width: 100, height: 80), scale: 1.0, alphaValue: 1.0)
    let r2 = ClosedPinRecord(image: img, frame: NSRect(x: 20, y: 20, width: 150, height: 120), baseSize: NSSize(width: 100, height: 80), scale: 1.5, alphaValue: 0.8)
    let r3 = ClosedPinRecord(image: img, frame: NSRect(x: 30, y: 30, width: 200, height: 160), baseSize: NSSize(width: 100, height: 80), scale: 2.0, alphaValue: 0.6)
    let r4 = ClosedPinRecord(image: img, frame: NSRect(x: 40, y: 40, width: 100, height: 80), baseSize: NSSize(width: 100, height: 80), scale: 1.0, alphaValue: 1.0)

    store.push(r1)
    store.push(r2)
    store.push(r3)
    store.push(r4) // Evicts r1 (oldest)

    #expect(store.count == 3)
    #expect(store.recentFirst.map(\.id) == [r4.id, r3.id, r2.id])

    // Pop latest -> r4
    let latest = store.popLatest()
    #expect(latest?.id == r4.id)
    #expect(store.count == 2)

    // Take specific older item -> r2 (preserves exact scale & alpha)
    let specific = store.take(id: r2.id)
    #expect(specific?.id == r2.id)
    #expect(specific?.scale == 1.5)
    #expect(specific?.alphaValue == 0.8)
    #expect(store.count == 1)

    store.clear()
    #expect(store.isEmpty)
}
