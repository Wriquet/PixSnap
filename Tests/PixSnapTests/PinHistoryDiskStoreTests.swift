import Testing
import Cocoa
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PixSnap

@MainActor
struct PinHistoryDiskStoreTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PixSnapPinHistoryTest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeTestImage(width: Int = 160, height: Int = 120, color: NSColor = .systemBlue) throws -> NSImage {
        let cs = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cg = try #require(ctx.makeImage())
        return NSImage(cgImage: cg, size: NSSize(width: width / 2, height: height / 2))
    }

    private func writeExternalPNG(to url: URL, width: Int = 200, height: Int = 140) throws {
        let img = try makeTestImage(width: width, height: height, color: .systemOrange)
        let cg = try #require(img.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, nil)
        #expect(CGImageDestinationFinalize(dest) == true)
    }

    @Test func diskBackedStoreHoldsZeroBitmapsInRAMAndSurvivesRestart() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = PinHistoryStore(directoryURL: dir, maxCount: 10)
        let img1 = try makeTestImage(width: 160, height: 120, color: .systemRed)
        let img2 = try makeTestImage(width: 240, height: 180, color: .systemGreen)

        let r1 = ClosedPinRecord(
            image: img1,
            frame: NSRect(x: 100, y: 200, width: 80, height: 60),
            baseSize: NSSize(width: 80, height: 60),
            scale: 1.0,
            alphaValue: 0.9,
            closedAt: Date(timeIntervalSince1970: 1000)
        )
        let r2 = ClosedPinRecord(
            image: img2,
            frame: NSRect(x: 300, y: 400, width: 180, height: 135),
            baseSize: NSSize(width: 120, height: 90),
            scale: 1.5,
            alphaValue: 0.75,
            closedAt: Date(timeIntervalSince1970: 2000)
        )

        store.push(r1)
        store.push(r2)
        store.flushPendingWrites()

        // Zero full-size bitmaps retained in RAM
        #expect(store.count == 2)
        for rec in store.records {
            #expect(rec.inMemoryImage == nil)
            let url = try #require(rec.fileURL)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }

        // Simulate full app restart by constructing a fresh PinHistoryStore pointing at the same folder
        let restarted = PinHistoryStore(directoryURL: dir, maxCount: 10)
        #expect(restarted.count == 2)
        #expect(restarted.recentFirst.map(\.id) == [r2.id, r1.id])

        let popped = try #require(restarted.popLatest())
        #expect(popped.id == r2.id)
        #expect(popped.frame == r2.frame)
        #expect(popped.scale == 1.5)
        #expect(popped.alphaValue == 0.75)

        let loadedImg = try #require(restarted.loadImage(for: popped))
        #expect(loadedImg.size == NSSize(width: 120, height: 90))
    }

    @Test func externalFolderImagesAreDiscoverableRestorableAndNeverDeleted() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let userFile = dir.appendingPathComponent("user_reference.png")
        try writeExternalPNG(to: userFile, width: 220, height: 160)

        let store = PinHistoryStore(directoryURL: dir, maxCount: 1)
        #expect(store.count == 1)
        let extRec = try #require(store.recentFirst.first)
        #expect(extRec.isManagedByPixSnap == false)
        #expect(extRec.hasSavedWindowGeometry == false)
        #expect(extRec.displayName == "user_reference.png")

        // Popping & restoring an external image MUST NOT delete the user's file
        let restored = try #require(store.popLatest())
        let img = try #require(store.loadImage(for: restored))
        #expect(img.size.width > 0 && img.size.height > 0)
        #expect(FileManager.default.fileExists(atPath: userFile.path))

        // Pushing managed pins beyond maxCount=1 prunes ONLY older PixSnap managed files, never user_reference.png
        let p1 = ClosedPinRecord(image: try makeTestImage(), frame: .zero, baseSize: NSSize(width: 80, height: 60), scale: 1, alphaValue: 1, closedAt: Date(timeIntervalSinceNow: 10))
        let p2 = ClosedPinRecord(image: try makeTestImage(), frame: .zero, baseSize: NSSize(width: 80, height: 60), scale: 1, alphaValue: 1, closedAt: Date(timeIntervalSinceNow: 20))
        store.push(p1)
        store.push(p2)
        store.flushPendingWrites()

        #expect(store.managedCount == 1)
        #expect(FileManager.default.fileExists(atPath: userFile.path))

        // Clearing PixSnap history removes managed PNGs but preserves user_reference.png untouched
        store.clear()
        store.flushPendingWrites()
        #expect(store.managedCount == 0)
        #expect(store.count == 1)
        #expect(FileManager.default.fileExists(atPath: userFile.path))
    }

    @Test func unlimitedLimitKeepsAllPinsAndSwitchingDirectoryReloads() throws {
        let dir1 = try makeTempDir()
        let dir2 = try makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: dir1)
            try? FileManager.default.removeItem(at: dir2)
        }

        let store = PinHistoryStore(directoryURL: dir1, maxCount: 0) // 0 = unlimited
        for i in 0..<5 {
            let rec = ClosedPinRecord(
                image: try makeTestImage(),
                frame: NSRect(x: i * 10, y: 10, width: 80, height: 60),
                baseSize: NSSize(width: 80, height: 60),
                scale: 1.0,
                alphaValue: 1.0,
                closedAt: Date(timeIntervalSince1970: Double(100 + i))
            )
            store.push(rec)
        }
        store.flushPendingWrites()
        #expect(store.count == 5)

        // Switch to dir2 containing a single external PNG -> immediately reflects dir2
        try writeExternalPNG(to: dir2.appendingPathComponent("from_dir2.png"))
        store.setDirectory(dir2)
        #expect(store.count == 1)
        #expect(store.recentFirst.first?.displayName == "from_dir2.png")
    }

    @Test func restoredPinImageRetainsOpaquePixelsAfterManagedFileIsDeleted() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = PinHistoryStore(directoryURL: dir, maxCount: 10)
        let redImg = try makeTestImage(width: 120, height: 80, color: NSColor(srgbRed: 0.95, green: 0.12, blue: 0.15, alpha: 1.0))
        let rec = ClosedPinRecord(
            image: redImg,
            frame: NSRect(x: 100, y: 100, width: 60, height: 40),
            baseSize: NSSize(width: 60, height: 40),
            scale: 1.0,
            alphaValue: 1.0
        )
        store.push(rec)
        store.flushPendingWrites()

        let storedURL = try #require(store.records.first?.fileURL)
        #expect(FileManager.default.fileExists(atPath: storedURL.path))

        // Popping loads the image and deletes the managed PNG asynchronously on ioQueue.
        let popped = try #require(store.popLatest())
        store.flushPendingWrites()
        #expect(!FileManager.default.fileExists(atPath: storedURL.path))

        // Even AFTER the backing PNG has been deleted from disk, drawing the restored NSImage
        // MUST render opaque red pixels (never 0-alpha transparent!).
        let loadedImg = try #require(store.loadImage(for: popped))
        let cg = try #require(loadedImg.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let cs = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var rgba = [UInt8](repeating: 0, count: 4 * 16 * 16)
        let ctx = try #require(CGContext(
            data: &rgba,
            width: 16,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 16 * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 16, height: 16))

        let centerIdx = (8 * 16 + 8) * 4
        #expect(rgba[centerIdx + 0] > 200)
        #expect(rgba[centerIdx + 1] < 60)
        #expect(rgba[centerIdx + 2] < 60)
        #expect(rgba[centerIdx + 3] > 250)
    }

    @Test func pinWindowStaysVisibleOnDeactivateAndClosesOnCancelOperation() throws {
        let img = try makeTestImage(width: 120, height: 80, color: .systemTeal)
        let pin = PinWindow(image: img, origin: CGPoint(x: 100, y: 100))

        #expect(pin.hidesOnDeactivate == false)
        #expect(pin.isClosed == false)

        var closedCount = 0
        pin.onClosed = { _ in closedCount += 1 }

        pin.cancelOperation(nil)
        #expect(closedCount == 1)
        #expect(pin.isClosed == true)

        // Calling closePin again must remain idempotent
        pin.closePin()
        #expect(closedCount == 1)
    }
}
