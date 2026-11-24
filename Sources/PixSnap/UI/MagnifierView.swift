import Cocoa

public final class MagnifierView: NSView {
    private let gridSize = 15 // 15 x 15 pixels
    private let cellSize: CGFloat = 9.0 // Exact 9pt square per pixel -> 135x135 grid!
    private var pixelSample: CGImage?
    private var sampleDrawRect: CGRect = .zero

    public private(set) var currentRGB: (r: UInt8, g: UInt8, b: UInt8) = (0, 0, 0)
    public var colorFormat: ColorCopyFormat = .hex
    public private(set) var currentColorString: String = "#000000"
    public private(set) var coordText: String = "0, 0"
    public var selectionSizeText: String?

    /// Reusable 1x1 sRGB RGBA buffer for O(1) zero-copy single-pixel sampling (never copies full 5K bitmap!)
    private var pixelBytes: [UInt8] = [0, 0, 0, 255]
    private lazy var sampleContext: CGContext? = {
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CGContext(
            data: &pixelBytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }()

    public override init(frame frameRect: NSRect) {
        let gridDim = CGFloat(15) * 9.0 // 135
        let totalW = gridDim + 16       // 151
        let totalH = gridDim + 76       // 211
        super.init(frame: NSRect(x: 0, y: 0, width: totalW, height: totalH))

        wantsLayer = true
        layer?.cornerRadius = PixTheme.barRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = PixTheme.hudBorder.cgColor
        layer?.backgroundColor = PixTheme.hudSolid.cgColor

        self.colorFormat = AppSettings.shared.colorCopyFormat
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func cycleColorFormat() -> ColorCopyFormat {
        colorFormat = colorFormat.next
        AppSettings.shared.colorCopyFormat = colorFormat
        currentColorString = colorFormat.format(r: currentRGB.r, g: currentRGB.g, b: currentRGB.b)
        needsDisplay = true
        return colorFormat
    }

    public func update(
        at point: CGPoint,
        in fullImage: CGImage,
        viewSize: CGSize,
        scaleFactor: CGFloat,
        selectionRect: CGRect?
    ) {
        let imgW = fullImage.width
        let imgH = fullImage.height
        guard imgW > 0 && imgH > 0 && viewSize.width > 0 && viewSize.height > 0 else { return }

        let scaleX = CGFloat(imgW) / viewSize.width
        let scaleY = CGFloat(imgH) / viewSize.height

        // Convert Cocoa bottom-left point to CGImage top-left pixel index (clamped safely inside [0, dim - 1])
        let rawPixelX = Int(floor(point.x * scaleX))
        let rawPixelY = Int(floor((viewSize.height - point.y) * scaleY))
        let pixelX = max(0, min(imgW - 1, rawPixelX))
        let pixelY = max(0, min(imgH - 1, rawPixelY))

        let half = gridSize / 2 // 7
        // Desired crop window centered EXACTLY at (pixelX, pixelY)
        let idealMinX = pixelX - half
        let idealMinY = pixelY - half
        let idealMaxX = idealMinX + gridSize
        let idealMaxY = idealMinY + gridSize

        // Clamp crop to image bounds, and compute exact sub-rect offset inside the 15x15 grid
        // so the center yellow reticle ALWAYS targets (pixelX, pixelY) even at screen corners!
        let cropMinX = max(0, idealMinX)
        let cropMinY = max(0, idealMinY)
        let cropMaxX = min(imgW, idealMaxX)
        let cropMaxY = min(imgH, idealMaxY)
        let cropW = max(1, cropMaxX - cropMinX)
        let cropH = max(1, cropMaxY - cropMinY)

        let cropRect = CGRect(x: cropMinX, y: cropMinY, width: cropW, height: cropH)
        self.pixelSample = fullImage.cropping(to: cropRect)

        // Offset within 15x15 grid (in Cocoa bottom-left coordinates!)
        let offsetLeftCells = CGFloat(cropMinX - idealMinX)
        let offsetBottomCells = CGFloat(idealMaxY - cropMaxY)
        let gridOriginX: CGFloat = 8
        let gridOriginY: CGFloat = bounds.height - 8 - CGFloat(gridSize) * cellSize
        self.sampleDrawRect = CGRect(
            x: gridOriginX + offsetLeftCells * cellSize,
            y: gridOriginY + offsetBottomCells * cellSize,
            width: CGFloat(cropW) * cellSize,
            height: CGFloat(cropH) * cellSize
        )

        // O(1) single-pixel extraction via 1x1 crop -> 1x1 sRGB CGContext (4 bytes, no full-screen copy!)
        if let onePixel = fullImage.cropping(to: CGRect(x: pixelX, y: pixelY, width: 1, height: 1)),
           let ctx = sampleContext {
            ctx.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
            ctx.draw(onePixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            currentRGB = (pixelBytes[0], pixelBytes[1], pixelBytes[2])
            currentColorString = colorFormat.format(r: currentRGB.r, g: currentRGB.g, b: currentRGB.b)
        }

        coordText = "(\(Int(round(point.x))), \(Int(round(point.y))))"
        if let sel = selectionRect, sel.width > 0, sel.height > 0 {
            let pw = Int(round(sel.width * scaleFactor))
            let ph = Int(round(sel.height * scaleFactor))
            selectionSizeText = "\(Int(round(sel.width)))×\(Int(round(sel.height)))  [\(pw)×\(ph)px]"
        } else {
            selectionSizeText = nil
        }

        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let gridDim = CGFloat(gridSize) * cellSize // 135
        let gridRect = CGRect(x: 8, y: bounds.height - 8 - gridDim, width: gridDim, height: gridDim)

        // 1. Pixel grid
        ctx.saveGState()
        let gridPath = CGPath(roundedRect: gridRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.addPath(gridPath)
        ctx.clip()

        // Dark background for out-of-bounds areas near screen edges
        ctx.setFillColor(NSColor(white: 0.06, alpha: 1.0).cgColor)
        ctx.fill(gridRect)

        if let sample = pixelSample {
            ctx.interpolationQuality = .none
            ctx.draw(sample, in: sampleDrawRect)
        }

        // Crisp 15x15 grid lines
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
        ctx.setLineWidth(0.5)
        for i in 1..<gridSize {
            let x = gridRect.minX + CGFloat(i) * cellSize
            ctx.move(to: CGPoint(x: x, y: gridRect.minY))
            ctx.addLine(to: CGPoint(x: x, y: gridRect.maxY))

            let y = gridRect.minY + CGFloat(i) * cellSize
            ctx.move(to: CGPoint(x: gridRect.minX, y: y))
            ctx.addLine(to: CGPoint(x: gridRect.maxX, y: y))
        }
        ctx.strokePath()

        // Subtle crosshair guides leading to center pixel
        let centerIdx = CGFloat(gridSize / 2)
        let centerRect = CGRect(
            x: gridRect.minX + centerIdx * cellSize,
            y: gridRect.minY + centerIdx * cellSize,
            width: cellSize,
            height: cellSize
        )
        ctx.setFillColor(PixTheme.accent.withAlphaComponent(0.18).cgColor)
        ctx.fill(CGRect(x: gridRect.minX, y: centerRect.minY, width: centerRect.minX - gridRect.minX, height: cellSize))
        ctx.fill(CGRect(x: centerRect.maxX, y: centerRect.minY, width: gridRect.maxX - centerRect.maxX, height: cellSize))
        ctx.fill(CGRect(x: centerRect.minX, y: gridRect.minY, width: cellSize, height: centerRect.minY - gridRect.minY))
        ctx.fill(CGRect(x: centerRect.minX, y: centerRect.maxY, width: cellSize, height: gridRect.maxY - centerRect.maxY))

        // High-contrast double reticle around exact target pixel
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        ctx.setLineWidth(2.4)
        ctx.stroke(centerRect.insetBy(dx: -0.5, dy: -0.5))
        ctx.setStrokeColor(NSColor.systemYellow.cgColor)
        ctx.setLineWidth(1.4)
        ctx.stroke(centerRect)

        ctx.restoreGState()

        // Border around grid
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.16).cgColor)
        ctx.setLineWidth(0.75)
        ctx.addPath(gridPath)
        ctx.strokePath()

        // 2. Swatch + Primary Color Value
        let swatchRect = CGRect(x: 10, y: 45, width: 16, height: 16)
        let swatchColor = NSColor(
            srgbRed: CGFloat(currentRGB.r) / 255.0,
            green: CGFloat(currentRGB.g) / 255.0,
            blue: CGFloat(currentRGB.b) / 255.0,
            alpha: 1.0
        )
        swatchColor.setFill()
        let swatchPath = NSBezierPath(roundedRect: swatchRect, xRadius: 4, yRadius: 4)
        swatchPath.fill()
        swatchPath.lineWidth = 1
        NSColor.white.withAlphaComponent(0.55).setStroke()
        swatchPath.stroke()

        let colorAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        (currentColorString as NSString).draw(
            in: NSRect(x: 32, y: 45, width: bounds.width - 40, height: 16),
            withAttributes: colorAttr
        )

        // 3. Coordinates or Selection Size
        let secondaryText = selectionSizeText ?? "坐标 \(coordText) · \(colorFormat.shortLabel)"
        let secondaryAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: NSColor(white: 1.0, alpha: 0.72)
        ]
        (secondaryText as NSString).draw(
            in: NSRect(x: 10, y: 26, width: bounds.width - 18, height: 15),
            withAttributes: secondaryAttr
        )

        // 4. Shortcut hint
        let hintText = "C 复制色值 · Tab 切换格式"
        let hintAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9.0, weight: .medium),
            .foregroundColor: PixTheme.textSecondary
        ]
        (hintText as NSString).draw(
            in: NSRect(x: 10, y: 9, width: bounds.width - 18, height: 14),
            withAttributes: hintAttr
        )
    }
}
