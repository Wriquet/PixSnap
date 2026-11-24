import Cocoa

@MainActor
public struct ClosedPinRecord {
    public let id: UUID
    public let image: NSImage
    public let frame: NSRect
    public let baseSize: NSSize
    public let scale: CGFloat
    public let alphaValue: CGFloat
    public let closedAt: Date
    public let thumbnail: NSImage

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
        self.image = image
        self.frame = frame
        self.baseSize = baseSize
        self.scale = scale
        self.alphaValue = alphaValue
        self.closedAt = closedAt
        self.thumbnail = Self.makeThumbnail(from: image, maxSize: NSSize(width: 34, height: 24))
    }

    public var menuTitle: String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        let w = Int(round(baseSize.width))
        let h = Int(round(baseSize.height))
        return "\(w) × \(h)   (\(df.string(from: closedAt)))"
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

/// Bounded LIFO store of closed PinWindows so users can undo accidental double-click/Esc dismissals
@MainActor
public final class PinHistoryStore {
    public let maxCount: Int
    /// Most recently closed pin is at the END of the array (LIFO stack)
    public private(set) var records: [ClosedPinRecord] = []

    public init(maxCount: Int = 20) {
        self.maxCount = max(1, maxCount)
    }

    public var count: Int { records.count }
    public var isEmpty: Bool { records.isEmpty }

    /// Records ordered newest-first for menu display
    public var recentFirst: [ClosedPinRecord] {
        records.reversed()
    }

    public func push(_ record: ClosedPinRecord) {
        records.append(record)
        if records.count > maxCount {
            records.removeFirst(records.count - maxCount)
        }
    }

    public func popLatest() -> ClosedPinRecord? {
        records.popLast()
    }

    public func take(id: UUID) -> ClosedPinRecord? {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return nil }
        return records.remove(at: idx)
    }

    public func clear() {
        records.removeAll()
    }
}
