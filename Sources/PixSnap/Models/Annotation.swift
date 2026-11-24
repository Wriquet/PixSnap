import Cocoa

public enum ToolType: Int, Equatable, CaseIterable, Sendable {
    case none = 0
    case rect = 1
    case ellipse = 2
    case arrow = 3
    case pen = 4
    case highlighter = 5
    case mosaic = 6
    case text = 7
    case counter = 8

    public var hasColorPicker: Bool {
        switch self {
        case .none, .mosaic: return false
        default: return true
        }
    }

    public var hasStyleBar: Bool {
        self != .none
    }

    public var isShapeTool: Bool {
        self == .rect || self == .ellipse
    }
}

public enum MosaicStyle: String, Equatable, Sendable {
    case pixelate
    case blur
}

public enum StrokeSizePreset: Int, CaseIterable, Sendable {
    case small = 0
    case medium = 1
    case large = 2

    public var strokeWidth: CGFloat {
        switch self {
        case .small: return 2.5
        case .medium: return 4.0
        case .large: return 7.0
        }
    }

    public var highlighterWidth: CGFloat {
        switch self {
        case .small: return 14.0
        case .medium: return 22.0
        case .large: return 34.0
        }
    }

    public var mosaicWidth: CGFloat {
        switch self {
        case .small: return 16.0
        case .medium: return 26.0
        case .large: return 40.0
        }
    }

    public var fontSize: CGFloat {
        switch self {
        case .small: return 14.0
        case .medium: return 19.0
        case .large: return 27.0
        }
    }

    public var counterRadius: CGFloat {
        switch self {
        case .small: return 11.0
        case .medium: return 14.0
        case .large: return 18.0
        }
    }
}

public struct Annotation: Equatable {
    public let id: UUID
    public var type: ToolType
    public var color: NSColor
    public var lineWidth: CGFloat
    public var startPoint: CGPoint
    public var endPoint: CGPoint
    public var points: [CGPoint]
    public var text: String
    public var fontSize: CGFloat
    public var counterNumber: Int
    public var isFilled: Bool
    public var cornerRadius: CGFloat
    public var mosaicStyle: MosaicStyle

    public init(
        id: UUID = UUID(),
        type: ToolType,
        color: NSColor = .systemRed,
        lineWidth: CGFloat = 4.0,
        startPoint: CGPoint = .zero,
        endPoint: CGPoint = .zero,
        points: [CGPoint] = [],
        text: String = "",
        fontSize: CGFloat = 19.0,
        counterNumber: Int = 1,
        isFilled: Bool = false,
        cornerRadius: CGFloat = 0.0,
        mosaicStyle: MosaicStyle = .pixelate
    ) {
        self.id = id
        self.type = type
        self.color = color
        self.lineWidth = lineWidth
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.points = points
        self.text = text
        self.fontSize = fontSize
        self.counterNumber = counterNumber
        self.isFilled = isFilled
        self.cornerRadius = cornerRadius
        self.mosaicStyle = mosaicStyle
    }

    public var normalizedRect: CGRect {
        CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
    }

    public var textBoundingSize: CGSize {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let nsStr = text as NSString
        let size = nsStr.size(withAttributes: [.font: font])
        return CGSize(width: max(12, ceil(size.width)), height: max(fontSize * 1.25, ceil(size.height)))
    }

    public var boundingBox: CGRect {
        switch type {
        case .none:
            return .zero
        case .rect, .ellipse:
            return normalizedRect.insetBy(dx: -max(4, lineWidth / 2), dy: -max(4, lineWidth / 2))
        case .arrow:
            return normalizedRect.insetBy(dx: -max(12, lineWidth * 3), dy: -max(12, lineWidth * 3))
        case .pen, .highlighter, .mosaic:
            guard let first = points.first else { return .zero }
            var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
            for p in points {
                minX = min(minX, p.x)
                maxX = max(maxX, p.x)
                minY = min(minY, p.y)
                maxY = max(maxY, p.y)
            }
            let pad = max(6, lineWidth / 2 + 2)
            return CGRect(x: minX - pad, y: minY - pad, width: (maxX - minX) + pad * 2, height: (maxY - minY) + pad * 2)
        case .text:
            let size = textBoundingSize
            return CGRect(origin: startPoint, size: size).insetBy(dx: -4, dy: -3)
        case .counter:
            let r = lineWidth // lineWidth stores counterRadius for .counter
            return CGRect(x: startPoint.x - r - 2, y: startPoint.y - r - 2, width: (r + 2) * 2, height: (r + 2) * 2)
        }
    }

    public func hitTest(point: CGPoint, tolerance: CGFloat = 8.0) -> Bool {
        switch type {
        case .none:
            return false
        case .rect:
            let r = normalizedRect
            if isFilled {
                return r.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
            }
            let outer = r.insetBy(dx: -(lineWidth / 2 + tolerance), dy: -(lineWidth / 2 + tolerance))
            let inner = r.insetBy(dx: lineWidth / 2 + tolerance, dy: lineWidth / 2 + tolerance)
            if inner.width > 0 && inner.height > 0 {
                return outer.contains(point) && !inner.contains(point)
            }
            return outer.contains(point)
        case .ellipse:
            let r = normalizedRect
            guard r.width > 1 && r.height > 1 else { return false }
            let cx = r.midX, cy = r.midY
            let rx = r.width / 2, ry = r.height / 2
            let dx = point.x - cx, dy = point.y - cy
            let normOuter = (dx * dx) / pow(rx + lineWidth / 2 + tolerance, 2) + (dy * dy) / pow(ry + lineWidth / 2 + tolerance, 2)
            if isFilled {
                return normOuter <= 1.0
            }
            let innerRx = max(1, rx - lineWidth / 2 - tolerance)
            let innerRy = max(1, ry - lineWidth / 2 - tolerance)
            let normInner = (dx * dx) / (innerRx * innerRx) + (dy * dy) / (innerRy * innerRy)
            return normOuter <= 1.0 && (rx <= lineWidth / 2 + tolerance || ry <= lineWidth / 2 + tolerance || normInner >= 1.0)
        case .arrow:
            return Self.distanceFromPoint(point, toSegmentStart: startPoint, end: endPoint) <= max(tolerance, lineWidth * 2.2)
        case .pen, .highlighter, .mosaic:
            guard !points.isEmpty else { return false }
            if points.count == 1 {
                return hypot(point.x - points[0].x, point.y - points[0].y) <= max(tolerance, lineWidth / 2 + 4)
            }
            let threshold = max(tolerance, lineWidth / 2 + 4)
            for i in 0..<(points.count - 1) {
                if Self.distanceFromPoint(point, toSegmentStart: points[i], end: points[i + 1]) <= threshold {
                    return true
                }
            }
            return false
        case .text:
            return boundingBox.insetBy(dx: -4, dy: -4).contains(point)
        case .counter:
            let r = lineWidth + 4
            return hypot(point.x - startPoint.x, point.y - startPoint.y) <= r
        }
    }

    public func translated(by dx: CGFloat, dy: CGFloat) -> Annotation {
        var copy = self
        copy.startPoint = CGPoint(x: startPoint.x + dx, y: startPoint.y + dy)
        copy.endPoint = CGPoint(x: endPoint.x + dx, y: endPoint.y + dy)
        if !points.isEmpty {
            copy.points = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        }
        return copy
    }

    public static func distanceFromPoint(_ p: CGPoint, toSegmentStart a: CGPoint, end b: CGPoint) -> CGFloat {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let lenSq = abx * abx + aby * aby
        if lenSq < 0.0001 {
            return hypot(p.x - a.x, p.y - a.y)
        }
        let t = max(0, min(1, ((p.x - a.x) * abx + (p.y - a.y) * aby) / lenSq))
        let projX = a.x + t * abx
        let projY = a.y + t * aby
        return hypot(p.x - projX, p.y - projY)
    }

    /// Constrain endpoint when holding Shift (square/circle for rect/ellipse, 45° snap for arrow/highlighter)
    public static func constrainEndPoint(from start: CGPoint, to end: CGPoint, for tool: ToolType) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        switch tool {
        case .rect, .ellipse:
            let side = max(abs(dx), abs(dy))
            return CGPoint(
                x: start.x + (dx >= 0 ? side : -side),
                y: start.y + (dy >= 0 ? side : -side)
            )
        case .arrow, .highlighter, .pen:
            let angle = atan2(dy, dx)
            let snappedAngle = round(angle / (.pi / 4)) * (.pi / 4)
            let dist = hypot(dx, dy)
            return CGPoint(
                x: start.x + cos(snappedAngle) * dist,
                y: start.y + sin(snappedAngle) * dist
            )
        default:
            return end
        }
    }
}
