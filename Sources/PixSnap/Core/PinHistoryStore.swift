import Cocoa
import ImageIO
import UniformTypeIdentifiers

@MainActor
public struct ClosedPinRecord {
    public let id: UUID
    /// Disk location for zero-RAM backed records (nil only in pure in-memory mode).
    public let fileURL: URL?
    /// Transient in-memory image (used before persisting to disk or in pure in-memory tests).
    public let inMemoryImage: NSImage?
    public let frame: NSRect
    public let baseSize: NSSize
    public let scale: CGFloat
    public let alphaValue: CGFloat
    public let closedAt: Date
    /// `true` when `frame`/`scale`/`alphaValue` came from a closed PinWindow; `false` for external image files found in the folder.
    public let hasSavedWindowGeometry: Bool
    /// `true` for PNG files created by PixSnap (`Pin_*.png`); `false` for user's own images (never auto-deleted!).
    public let isManagedByPixSnap: Bool
    /// Original file name for externally discovered images.
    public let displayName: String?

    /// Lazily resolves the image (prefers transient in-memory image, otherwise reads from `fileURL`).
    public var image: NSImage {
        if let inMemoryImage { return inMemoryImage }
        if let fileURL, let loaded = Self.loadImageFromDisk(url: fileURL, logicalSize: hasSavedWindowGeometry ? baseSize : nil) {
            return loaded
        }
        return NSImage(size: baseSize)
    }

    /// Backwards-compatible initializer (used by PinWindow.makeHistoryRecord and in-memory tests).
    public init(
        id: UUID = UUID(),
        image: NSImage,
        frame: NSRect,
        baseSize: NSSize,
        scale: CGFloat,
        alphaValue: CGFloat,
        closedAt: Date = Date()
    ) {
        self.id = id
        self.fileURL = nil
        self.inMemoryImage = image
        self.frame = frame
        self.baseSize = baseSize
        self.scale = scale
        self.alphaValue = alphaValue
        self.closedAt = closedAt
        self.hasSavedWindowGeometry = true
        self.isManagedByPixSnap = true
        self.displayName = nil
    }

    /// Zero-RAM disk-backed record initializer (stores metadata + file path only, NO full bitmap in memory!).
    public init(
        id: UUID,
        fileURL: URL,
        frame: NSRect,
        baseSize: NSSize,
        scale: CGFloat,
        alphaValue: CGFloat,
        closedAt: Date,
        hasSavedWindowGeometry: Bool,
        isManagedByPixSnap: Bool,
        displayName: String? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.inMemoryImage = nil
        self.frame = frame
        self.baseSize = baseSize
        self.scale = scale
        self.alphaValue = alphaValue
        self.closedAt = closedAt
        self.hasSavedWindowGeometry = hasSavedWindowGeometry
        self.isManagedByPixSnap = isManagedByPixSnap
        self.displayName = displayName
    }

    private static let todayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()

    private static let olderFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MM-dd HH:mm"
        return df
    }()

    public var menuTitle: String {
        let timeStr = Calendar.current.isDateInToday(closedAt)
            ? Self.todayFormatter.string(from: closedAt)
            : Self.olderFormatter.string(from: closedAt)
        let w = Int(round(baseSize.width))
        let h = Int(round(baseSize.height))
        if let name = displayName, !isManagedByPixSnap {
            let trimmed = name.count > 26 ? String(name.prefix(24)) + "…" : name
            return "\(trimmed)  (\(w) × \(h))"
        }
        return "\(w) × \(h)   (\(timeStr))"
    }

    /// Hardware-accelerated subsampled thumbnail (decodes max 68px directly from disk via ImageIO without
    /// ever expanding a full 5K screenshot into RAM!).
    public func makeMenuThumbnail(maxSize: NSSize = NSSize(width: 34, height: 24)) -> NSImage? {
        if let fileURL {
            return Self.makeSubsampledThumbnail(from: fileURL, maxSize: maxSize)
        }
        if let inMemoryImage {
            return Self.makeThumbnail(from: inMemoryImage, maxSize: maxSize)
        }
        return nil
    }

    public static func loadImageFromDisk(url: URL, logicalSize: NSSize?) -> NSImage? {
        // Read bytes into memory first AND force immediate bitmap decode (`kCGImageSourceShouldCacheImmediately`)
        // so the resulting CGImage is 100% self-contained in RAM and NEVER turns transparent if the PNG file
        // is subsequently removed or modified on disk!
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let decodeOpts: [CFString: Any] = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateImageAtIndex(src, 0, decodeOpts as CFDictionary),
              cgImage.width > 0, cgImage.height > 0 else {
            return nil
        }

        // Materialize an independent bitmap-backed CGImage via a fresh CGContext copy so CoreAnimation
        // can never hold a lazy file/data provider reference after the source file is deleted.
        let cs = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        let finalCG: CGImage
        if let ctx = CGContext(
            data: nil,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) {
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            finalCG = ctx.makeImage() ?? cgImage
        } else {
            finalCG = cgImage
        }

        let targetSize: NSSize
        if let logical = logicalSize, logical.width > 0, logical.height > 0 {
            targetSize = logical
        } else {
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let w = CGFloat(finalCG.width) / scale
            let h = CGFloat(finalCG.height) / scale
            targetSize = NSSize(width: max(1, round(w)), height: max(1, round(h)))
        }
        return NSImage(cgImage: finalCG, size: targetSize)
    }

    private static func makeSubsampledThumbnail(from url: URL, maxSize: NSSize) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let maxPx = Int(ceil(max(maxSize.width, maxSize.height) * 2.0))
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(32, maxPx)
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let ratio = min(maxSize.width / CGFloat(cgThumb.width), maxSize.height / CGFloat(cgThumb.height), 1.0)
        let ptSize = NSSize(
            width: max(12, round(CGFloat(cgThumb.width) * ratio)),
            height: max(12, round(CGFloat(cgThumb.height) * ratio))
        )
        return NSImage(cgImage: cgThumb, size: ptSize)
    }

    private static func makeThumbnail(from image: NSImage, maxSize: NSSize) -> NSImage {
        let src = image.size
        guard src.width > 0 && src.height > 0 else { return image }
        let ratio = min(maxSize.width / src.width, maxSize.height / src.height, 1.0)
        let targetSize = NSSize(
            width: max(12, round(src.width * ratio)),
            height: max(12, round(src.height * ratio))
        )
        let thumb = NSImage(size: targetSize)
        thumb.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1.0)
        thumb.unlockFocus()
        return thumb
    }
}

private struct PersistedPinMeta: Codable, Sendable {
    let id: UUID
    let fileName: String
    let frameX: Double
    let frameY: Double
    let frameW: Double
    let frameH: Double
    let baseW: Double
    let baseH: Double
    let scale: Double
    let alphaValue: Double
    let closedAt: TimeInterval

    @MainActor
    init(record: ClosedPinRecord, fileName: String) {
        self.id = record.id
        self.fileName = fileName
        self.frameX = Double(record.frame.origin.x)
        self.frameY = Double(record.frame.origin.y)
        self.frameW = Double(record.frame.size.width)
        self.frameH = Double(record.frame.size.height)
        self.baseW = Double(record.baseSize.width)
        self.baseH = Double(record.baseSize.height)
        self.scale = Double(record.scale)
        self.alphaValue = Double(record.alphaValue)
        self.closedAt = record.closedAt.timeIntervalSince1970
    }

    @MainActor
    func toRecord(in directory: URL) -> ClosedPinRecord {
        ClosedPinRecord(
            id: id,
            fileURL: directory.appendingPathComponent(fileName),
            frame: NSRect(x: frameX, y: frameY, width: frameW, height: frameH),
            baseSize: NSSize(width: baseW, height: baseH),
            scale: CGFloat(scale),
            alphaValue: CGFloat(alphaValue),
            closedAt: Date(timeIntervalSince1970: closedAt),
            hasSavedWindowGeometry: true,
            isManagedByPixSnap: true,
            displayName: fileName
        )
    }
}

/// Zero-RAM disk-backed LIFO store of closed PinWindows (plus optional pure in-memory mode for unit tests).
///
/// - Closed pins are encoded as standard PNG files into `directoryURL` on a background serial I/O queue,
///   releasing full bitmaps from RAM immediately while preserving exact window frame/scale/opacity in `.pixsnap_pins.json`.
/// - Also scans `directoryURL` for any external image files (PNG/JPG/WebP/HEIC/TIFF) placed by the user
///   so any image in the chosen folder can be restored as a floating pin — while NEVER deleting non-PixSnap files.
@MainActor
public final class PinHistoryStore {
    public private(set) var maxCount: Int
    public private(set) var directoryURL: URL?
    /// Ordered oldest -> newest so `records.last` is always the latest (LIFO).
    public private(set) var records: [ClosedPinRecord] = []

    private static let indexFileName = ".pixsnap_pins.json"
    private static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "heic", "tiff", "tif", "gif", "bmp"]
    private static let fileTimestampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        return df
    }()

    private let ioQueue = DispatchQueue(label: "com.wangqi.pixsnap.pinhistory.io", qos: .utility)
    private var managedMetadata: [UUID: PersistedPinMeta] = [:]
    /// External file paths already popped via `popLatest()` in the current cycle (never deleted on disk!).
    private var poppedExternalPaths: Set<String> = []
    private var thumbnailCache: [UUID: NSImage] = [:]

    /// Pure in-memory mode (kept for lightweight unit tests).
    public init(maxCount: Int = 20) {
        self.directoryURL = nil
        self.maxCount = max(1, maxCount)
    }

    /// Zero-RAM disk-backed mode persisted in `directoryURL` (`maxCount == 0` means unlimited).
    public init(directoryURL: URL, maxCount: Int = 100) {
        self.directoryURL = directoryURL
        self.maxCount = max(0, maxCount)
        reloadFromDisk()
    }

    public var count: Int { records.count }
    public var isEmpty: Bool { records.isEmpty }
    public var managedCount: Int { records.filter(\.isManagedByPixSnap).count }

    /// Records ordered newest-first for menu display.
    public var recentFirst: [ClosedPinRecord] {
        records.reversed()
    }

    public func setDirectory(_ newURL: URL) {
        guard directoryURL?.standardizedFileURL != newURL.standardizedFileURL else { return }
        flushPendingWrites()
        directoryURL = newURL
        poppedExternalPaths.removeAll()
        thumbnailCache.removeAll()
        reloadFromDisk()
    }

    public func setMaxCount(_ newMaxCount: Int) {
        maxCount = max(0, newMaxCount)
        if directoryURL != nil {
            pruneManagedRecordsIfNeeded()
            persistIndexAsync()
        } else if maxCount > 0 && records.count > maxCount {
            records.removeFirst(records.count - maxCount)
        }
    }

    /// Wait for any in-flight background PNG writes to finish (called before reading disk or app exit).
    public func flushPendingWrites() {
        ioQueue.sync {}
    }

    /// Cached subsampled menu thumbnail (only generated on demand for visible menu rows).
    public func thumbnail(for record: ClosedPinRecord) -> NSImage? {
        if let cached = thumbnailCache[record.id] {
            return cached
        }
        if record.fileURL != nil {
            flushPendingWrites()
        }
        guard let thumb = record.makeMenuThumbnail() else { return nil }
        if thumbnailCache.count > 48 {
            thumbnailCache.removeAll(keepingCapacity: true)
        }
        thumbnailCache[record.id] = thumb
        return thumb
    }

    /// Lazily load full-resolution image from disk (flushes pending write first if just closed).
    public func loadImage(for record: ClosedPinRecord) -> NSImage? {
        if let mem = record.inMemoryImage {
            return mem
        }
        flushPendingWrites()
        guard let url = record.fileURL else { return nil }
        return ClosedPinRecord.loadImageFromDisk(
            url: url,
            logicalSize: record.hasSavedWindowGeometry ? record.baseSize : nil
        )
    }

    public func push(_ record: ClosedPinRecord) {
        guard let dir = directoryURL else {
            // Pure in-memory mode
            records.append(record)
            if maxCount > 0 && records.count > maxCount {
                records.removeFirst(records.count - maxCount)
            }
            return
        }

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let shortID = String(record.id.uuidString.prefix(8)).lowercased()
        let ts = Self.fileTimestampFormatter.string(from: record.closedAt)
        let fileName = "Pin_\(ts)_\(shortID).png"
        let targetURL = dir.appendingPathComponent(fileName)

        // Extract CGImage before dropping NSImage reference so the background queue encodes PNG
        // and releases all pixel buffers as soon as the file lands on disk!
        let cgImageToSave: CGImage?
        if let srcImg = record.inMemoryImage {
            cgImageToSave = Self.extractCGImage(from: srcImg)
        } else if let existingURL = record.fileURL,
                  let loaded = ClosedPinRecord.loadImageFromDisk(url: existingURL, logicalSize: record.baseSize) {
            cgImageToSave = Self.extractCGImage(from: loaded)
        } else {
            cgImageToSave = nil
        }

        // Pre-generate tiny 34x24 menu thumbnail now so menu updates stay instant without hitting disk
        if record.inMemoryImage != nil, let tiny = record.makeMenuThumbnail() {
            thumbnailCache[record.id] = tiny
        }

        // Store ONLY metadata + fileURL in RAM (inMemoryImage = nil -> zero full-bitmap RAM!)
        let diskRecord = ClosedPinRecord(
            id: record.id,
            fileURL: targetURL,
            frame: record.frame,
            baseSize: record.baseSize,
            scale: record.scale,
            alphaValue: record.alphaValue,
            closedAt: record.closedAt,
            hasSavedWindowGeometry: true,
            isManagedByPixSnap: true,
            displayName: fileName
        )

        let meta = PersistedPinMeta(record: diskRecord, fileName: fileName)
        managedMetadata[diskRecord.id] = meta
        records.append(diskRecord)
        records.sort { $0.closedAt < $1.closedAt }

        if let cgImageToSave {
            ioQueue.async {
                Self.writePNG(cgImage: cgImageToSave, to: targetURL)
            }
        }

        pruneManagedRecordsIfNeeded()
        persistIndexAsync()
    }

    public func popLatest() -> ClosedPinRecord? {
        guard directoryURL != nil else {
            return records.popLast()
        }

        // Prefer newest record not yet popped in this external-file cycle
        for idx in stride(from: records.count - 1, through: 0, by: -1) {
            let rec = records[idx]
            if !rec.isManagedByPixSnap, let path = rec.fileURL?.path, poppedExternalPaths.contains(path) {
                continue
            }
            if let consumed = consumeRecord(at: idx) {
                return consumed
            }
        }

        // If every remaining record was an already-cycled external image, reset cycle and pop newest
        if !poppedExternalPaths.isEmpty && !records.isEmpty {
            poppedExternalPaths.removeAll()
            for idx in stride(from: records.count - 1, through: 0, by: -1) {
                if let consumed = consumeRecord(at: idx) {
                    return consumed
                }
            }
        }
        return nil
    }

    public func take(id: UUID) -> ClosedPinRecord? {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return nil }
        return consumeRecord(at: idx)
    }

    /// Called when a PinWindow opened from an external image in this folder is closed:
    /// re-enables it for LIFO `popLatest()` without duplicating the user's file on disk.
    public func markExternalPinClosed(fileURL: URL) {
        poppedExternalPaths.remove(fileURL.path)
    }

    /// Clear PixSnap-managed closed pins (and delete their managed `Pin_*.png` cache files).
    /// External images placed in the folder by the user are NEVER deleted!
    public func clear() {
        guard let dir = directoryURL else {
            records.removeAll()
            thumbnailCache.removeAll()
            return
        }

        flushPendingWrites()
        let managedURLs = records.compactMap { $0.isManagedByPixSnap ? $0.fileURL : nil }
        managedMetadata.removeAll()
        records.removeAll { $0.isManagedByPixSnap }
        thumbnailCache.removeAll()
        poppedExternalPaths.removeAll()

        let indexURL = dir.appendingPathComponent(Self.indexFileName)
        ioQueue.async {
            let fm = FileManager.default
            for url in managedURLs {
                try? fm.removeItem(at: url)
            }
            try? fm.removeItem(at: indexURL)
        }
    }

    /// Re-scan the configured folder so restarts, Finder additions, and Finder deletions stay in sync.
    public func reloadFromDisk() {
        guard let dir = directoryURL else { return }
        flushPendingWrites()

        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // 1. Load managed PixSnap index
        let indexURL = dir.appendingPathComponent(Self.indexFileName)
        var loadedMeta: [UUID: PersistedPinMeta] = [:]
        var managedFileNames: Set<String> = []
        var rebuilt: [ClosedPinRecord] = []

        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([PersistedPinMeta].self, from: data) {
            for meta in decoded {
                let fileURL = dir.appendingPathComponent(meta.fileName)
                if fm.fileExists(atPath: fileURL.path) {
                    loadedMeta[meta.id] = meta
                    managedFileNames.insert(meta.fileName)
                    rebuilt.append(meta.toRecord(in: dir))
                }
            }
        }
        self.managedMetadata = loadedMeta

        // 2. Discover any external image files in the folder (instant header-only metadata scan, 0 bitmap decode!)
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        if let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            for url in contents {
                let name = url.lastPathComponent
                if managedFileNames.contains(name) { continue }
                let ext = url.pathExtension.lowercased()
                guard Self.supportedExtensions.contains(ext) else { continue }

                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true else { continue }
                let modDate = values?.contentModificationDate ?? Date.distantPast

                let pixelSize = Self.readPixelSizeHeaderOnly(at: url) ?? CGSize(width: 400, height: 300)
                let logicalSize = NSSize(
                    width: max(20, round(pixelSize.width / scale)),
                    height: max(20, round(pixelSize.height / scale))
                )

                // Preserve stable UUID for already-loaded external URL so menu items & thumbnails stay smooth
                let existingID = records.first(where: { $0.fileURL?.path == url.path })?.id ?? UUID()
                rebuilt.append(ClosedPinRecord(
                    id: existingID,
                    fileURL: url,
                    frame: NSRect(origin: .zero, size: logicalSize),
                    baseSize: logicalSize,
                    scale: 1.0,
                    alphaValue: 1.0,
                    closedAt: modDate,
                    hasSavedWindowGeometry: false,
                    isManagedByPixSnap: false,
                    displayName: name
                ))
            }
        }

        rebuilt.sort { $0.closedAt < $1.closedAt }
        self.records = rebuilt

        // Drop stale thumbnail cache entries
        let validIDs = Set(rebuilt.map(\.id))
        thumbnailCache = thumbnailCache.filter { validIDs.contains($0.key) }
    }

    // MARK: - Private Helpers

    private func consumeRecord(at idx: Int) -> ClosedPinRecord? {
        let record = records[idx]
        if record.isManagedByPixSnap {
            records.remove(at: idx)
            managedMetadata.removeValue(forKey: record.id)
            thumbnailCache.removeValue(forKey: record.id)
            // Materialize the bitmap completely into RAM BEFORE scheduling managed file deletion
            let loadedImg = loadImage(for: record)
            if let fileURL = record.fileURL {
                ioQueue.async {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
            persistIndexAsync()
            guard let loadedImg else { return nil }
            return ClosedPinRecord(
                id: record.id,
                image: loadedImg,
                frame: record.frame,
                baseSize: record.baseSize,
                scale: record.scale,
                alphaValue: record.alphaValue,
                closedAt: record.closedAt
            )
        } else {
            // External user image: NEVER delete the file on disk! Just mark cycled for `popLatest()`.
            if let path = record.fileURL?.path {
                poppedExternalPaths.insert(path)
            }
            return record
        }
    }

    private func pruneManagedRecordsIfNeeded() {
        guard maxCount > 0 else { return }
        let managedIndices = records.indices.filter { records[$0].isManagedByPixSnap }
        let excess = managedIndices.count - maxCount
        guard excess > 0 else { return }

        var urlsToDelete: [URL] = []
        var idsToRemove: Set<UUID> = []
        for idx in managedIndices.prefix(excess) {
            let rec = records[idx]
            idsToRemove.insert(rec.id)
            managedMetadata.removeValue(forKey: rec.id)
            thumbnailCache.removeValue(forKey: rec.id)
            if let u = rec.fileURL { urlsToDelete.append(u) }
        }
        records.removeAll { idsToRemove.contains($0.id) }

        if !urlsToDelete.isEmpty {
            let deleteList = urlsToDelete
            ioQueue.async {
                let fm = FileManager.default
                for url in deleteList {
                    try? fm.removeItem(at: url)
                }
            }
        }
    }

    private func persistIndexAsync() {
        guard let dir = directoryURL else { return }
        let snapshot = Array(managedMetadata.values).sorted { $0.closedAt < $1.closedAt }
        let indexURL = dir.appendingPathComponent(Self.indexFileName)
        ioQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    private static func extractCGImage(from image: NSImage) -> CGImage? {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cg
        }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let w = max(1, Int(round(size.width * scale)))
        let h = max(1, Int(round(size.height * scale)))
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    nonisolated private static func writePNG(cgImage: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
    }

    private static func readPixelSizeHeaderOnly(at url: URL) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat,
              w > 0, h > 0 else {
            return nil
        }
        return CGSize(width: w, height: h)
    }
}
