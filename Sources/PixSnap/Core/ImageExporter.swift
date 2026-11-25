import Cocoa
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum AnnotationRenderer {
    /// Draw a single annotation into a CGContext (works both in NSView.draw and offscreen CGContext!)
    public static func draw(
        _ annot: Annotation,
        in ctx: CGContext,
        canvasBounds: CGRect,
        mosaicImage: CGImage?,
        blurImage: CGImage?
    ) {
        ctx.saveGState()
        defer { ctx.restoreGState() }

        switch annot.type {
        case .rect:
            let r = annot.normalizedRect
            guard r.width > 0.5 || r.height > 0.5 else { return }
            let clampedRadius = min(annot.cornerRadius, min(r.width, r.height) * 0.5)
            let path: CGPath
            if clampedRadius > 0.5 {
                path = CGPath(roundedRect: r, cornerWidth: clampedRadius, cornerHeight: clampedRadius, transform: nil)
            } else {
                path = CGPath(rect: r, transform: nil)
            }
            if annot.isFilled {
                ctx.setFillColor(annot.color.withAlphaComponent(0.24).cgColor)
                ctx.addPath(path)
                ctx.fillPath()
            }
            ctx.setStrokeColor(annot.color.cgColor)
            ctx.setLineWidth(annot.lineWidth)
            ctx.setLineJoin(clampedRadius > 0.5 ? .round : .miter)
            ctx.addPath(path)
            ctx.strokePath()

        case .ellipse:
            let r = annot.normalizedRect
            guard r.width > 0.5 || r.height > 0.5 else { return }
            if annot.isFilled {
                ctx.setFillColor(annot.color.withAlphaComponent(0.24).cgColor)
                ctx.fillEllipse(in: r)
            }
            ctx.setStrokeColor(annot.color.cgColor)
            ctx.setLineWidth(annot.lineWidth)
            ctx.strokeEllipse(in: r)

        case .arrow:
            drawSleekArrow(from: annot.startPoint, to: annot.endPoint, color: annot.color, lineWidth: annot.lineWidth, in: ctx)

        case .pen:
            guard !annot.points.isEmpty else { return }
            ctx.setStrokeColor(annot.color.cgColor)
            ctx.setFillColor(annot.color.cgColor)
            ctx.setLineWidth(annot.lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            if annot.points.count == 1 {
                let p = annot.points[0]
                let r = annot.lineWidth / 2
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            } else {
                addSmoothPath(points: annot.points, to: ctx)
                ctx.strokePath()
            }

        case .highlighter:
            guard !annot.points.isEmpty else { return }
            ctx.saveGState()
            ctx.setBlendMode(.multiply)
            ctx.setStrokeColor(annot.color.withAlphaComponent(0.38).cgColor)
            ctx.setFillColor(annot.color.withAlphaComponent(0.38).cgColor)
            ctx.setLineWidth(annot.lineWidth)
            ctx.setLineCap(.square)
            ctx.setLineJoin(.round)
            if annot.points.count == 1 {
                let p = annot.points[0]
                let r = annot.lineWidth / 2
                ctx.fill(CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            } else {
                addSmoothPath(points: annot.points, to: ctx)
                ctx.strokePath()
            }
            ctx.restoreGState()

        case .mosaic:
            let sourceImage = (annot.mosaicStyle == .blur ? blurImage : mosaicImage) ?? mosaicImage ?? blurImage
            guard let effectImg = sourceImage, !annot.points.isEmpty else { return }
            ctx.saveGState()
            let path = CGMutablePath()
            if annot.points.count == 1 {
                let p = annot.points[0]
                let r = annot.lineWidth / 2
                path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                ctx.addPath(path)
            } else {
                path.move(to: annot.points[0])
                for pt in annot.points.dropFirst() {
                    path.addLine(to: pt)
                }
                let stroked = path.copy(strokingWithWidth: annot.lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
                ctx.addPath(stroked)
            }
            ctx.clip()
            ctx.draw(effectImg, in: canvasBounds)
            ctx.restoreGState()

        case .text:
            guard !annot.text.isEmpty else { return }
            // Explicitly bind NSGraphicsContext so offscreen CGContext renders text reliably!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

            let font = NSFont.systemFont(ofSize: annot.fontSize, weight: .semibold)
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: annot.color
            ]
            // Only add a gentle legibility shadow for very light ink (e.g. white/yellow);
            // saturated & dark ink stays razor-sharp with no gray smudge underneath.
            if let rgb = annot.color.usingColorSpace(.sRGB) {
                let luma = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
                if luma > 0.72 {
                    let shadow = NSShadow()
                    shadow.shadowColor = NSColor.black.withAlphaComponent(0.40)
                    shadow.shadowOffset = NSSize(width: 0, height: -0.8)
                    shadow.shadowBlurRadius = 1.8
                    attrs[.shadow] = shadow
                }
            }
            (annot.text as NSString).draw(at: annot.startPoint, withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()

        case .counter:
            drawCounterBadge(number: annot.counterNumber, at: annot.startPoint, radius: annot.lineWidth, color: annot.color, in: ctx)

        case .none:
            break
        }
    }

    /// Tapered modern arrow (PixPin / Snipaste style — shaft tapers smoothly into crisp arrowhead without poking through tip)
    private static func drawSleekArrow(from start: CGPoint, to end: CGPoint, color: NSColor, lineWidth: CGFloat, in ctx: CGContext) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 2.0 else { return }

        let ux = dx / length
        let uy = dy / length
        let px = -uy
        let py = ux

        let headLength = min(length * 0.45, max(12.0, lineWidth * 4.2))
        let headHalfWidth = max(6.0, lineWidth * 2.15)
        let neckHalfWidth = max(1.8, lineWidth * 0.72)
        let tailHalfWidth = max(0.9, lineWidth * 0.28)

        let neckCenter = CGPoint(x: end.x - ux * (headLength * 0.78), y: end.y - uy * (headLength * 0.78))
        let headBaseCenter = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)

        let tailL = CGPoint(x: start.x + px * tailHalfWidth, y: start.y + py * tailHalfWidth)
        let tailR = CGPoint(x: start.x - px * tailHalfWidth, y: start.y - py * tailHalfWidth)
        let neckL = CGPoint(x: neckCenter.x + px * neckHalfWidth, y: neckCenter.y + py * neckHalfWidth)
        let neckR = CGPoint(x: neckCenter.x - px * neckHalfWidth, y: neckCenter.y - py * neckHalfWidth)
        let wingL = CGPoint(x: headBaseCenter.x + px * headHalfWidth, y: headBaseCenter.y + py * headHalfWidth)
        let wingR = CGPoint(x: headBaseCenter.x - px * headHalfWidth, y: headBaseCenter.y - py * headHalfWidth)

        let path = CGMutablePath()
        path.move(to: end)
        path.addLine(to: wingL)
        path.addLine(to: neckL)
        path.addLine(to: tailL)
        path.addLine(to: tailR)
        path.addLine(to: neckR)
        path.addLine(to: wingR)
        path.closeSubpath()

        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 2.5, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
    }

    private static func addSmoothPath(points: [CGPoint], to ctx: CGContext) {
        guard points.count >= 2 else { return }
        ctx.move(to: points[0])
        if points.count == 2 {
            ctx.addLine(to: points[1])
            return
        }
        for i in 1..<(points.count - 1) {
            let mid = CGPoint(
                x: (points[i].x + points[i + 1].x) * 0.5,
                y: (points[i].y + points[i + 1].y) * 0.5
            )
            ctx.addQuadCurve(to: mid, control: points[i])
        }
        if let last = points.last {
            ctx.addLine(to: last)
        }
    }

    private static func drawCounterBadge(number: Int, at center: CGPoint, radius: CGFloat, color: NSColor, in ctx: CGContext) {
        let circleRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 3.5, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: circleRect)
        ctx.restoreGState()

        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.92).cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: circleRect)

        // Choose contrasting label color (dark text on bright colors like yellow/white)
        let labelColor = isLightColor(color) ? NSColor(white: 0.1, alpha: 1.0) : NSColor.white
        let str = "\(number)" as NSString
        let font = NSFont.systemFont(ofSize: radius * 1.15, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: labelColor
        ]
        let textSize = str.size(withAttributes: attrs)
        let textPoint = CGPoint(
            x: center.x - textSize.width / 2.0,
            y: center.y - textSize.height / 2.0 + 0.5
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        str.draw(at: textPoint, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func isLightColor(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.sRGB) else { return false }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.72
    }
}

public enum ImageExporter {
    /// Render final cropped CGImage + NSImage with exact display color space, optional rounded corner clip & crisp annotations
    public static func renderCroppedImage(
        fullImage: CGImage,
        bounds: CGRect,
        selectionRect: CGRect,
        scaleFactor: CGFloat,
        annotations: [Annotation],
        mosaicImage: CGImage?,
        blurImage: CGImage?,
        selectionCornerRadius: CGFloat = 0.0
    ) -> (cgImage: CGImage, nsImage: NSImage)? {
        guard selectionRect.width >= 1 && selectionRect.height >= 1 else { return nil }

        let imgW = CGFloat(fullImage.width)
        let imgH = CGFloat(fullImage.height)
        let scaleX = imgW / bounds.width
        let scaleY = imgH / bounds.height

        let rawX = round(selectionRect.minX * scaleX)
        let rawY = round((bounds.height - selectionRect.maxY) * scaleY)
        let rawW = max(1, round(selectionRect.width * scaleX))
        let rawH = max(1, round(selectionRect.height * scaleY))

        let clampedX = max(0, min(imgW - 1, rawX))
        let clampedY = max(0, min(imgH - 1, rawY))
        let clampedW = max(1, min(imgW - clampedX, rawW))
        let clampedH = max(1, min(imgH - clampedY, rawH))
        let pixelRect = CGRect(x: clampedX, y: clampedY, width: clampedW, height: clampedH)

        guard let cropped = fullImage.cropping(to: pixelRect) else { return nil }

        let width = cropped.width
        let height = cropped.height
        let colorSpace = fullImage.colorSpace
            ?? CGColorSpace(name: CGColorSpace.displayP3)
            ?? CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high

        // Optional rounded-corner mask on exported image (0 = crisp 90° sharp corners)
        if selectionCornerRadius > 0.5 {
            let maxPtRadius = min(selectionRect.width, selectionRect.height) * 0.5
            let clampedPtRadius = min(selectionCornerRadius, maxPtRadius)
            let rx = clampedPtRadius * scaleX
            let ry = clampedPtRadius * scaleY
            let clipPath = CGPath(
                roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
                cornerWidth: rx,
                cornerHeight: ry,
                transform: nil
            )
            ctx.addPath(clipPath)
            ctx.clip()
        }

        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Map view-local annotation coordinates into cropped image pixel space
        ctx.scaleBy(x: scaleX, y: scaleY)
        ctx.translateBy(x: -selectionRect.minX, y: -selectionRect.minY)

        for annot in annotations {
            AnnotationRenderer.draw(
                annot,
                in: ctx,
                canvasBounds: bounds,
                mosaicImage: mosaicImage,
                blurImage: blurImage
            )
        }

        guard let finalCG = ctx.makeImage() else { return nil }
        let logicalSize = CGSize(width: CGFloat(width) / scaleFactor, height: CGFloat(height) / scaleFactor)
        let nsImg = NSImage(cgImage: finalCG, size: logicalSize)
        return (finalCG, nsImg)
    }

    /// Clip an existing CGImage to a rounded corner radius (for copying/saving rounded PinWindows)
    public static func applyRoundedCorners(to cgImage: CGImage, cornerRadiusPt: CGFloat, scaleFactor: CGFloat) -> CGImage {
        guard cornerRadiusPt > 0.5 else { return cgImage }
        let width = cgImage.width
        let height = cgImage.height
        let rx = min(cornerRadiusPt * scaleFactor, CGFloat(width) * 0.5)
        let ry = min(cornerRadiusPt * scaleFactor, CGFloat(height) * 0.5)
        let cs = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return cgImage }

        let clipPath = CGPath(
            roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
            cornerWidth: rx,
            cornerHeight: ry,
            transform: nil
        )
        ctx.addPath(clipPath)
        ctx.clip()
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage() ?? cgImage
    }

    /// Encode CGImage directly to PNG or JPEG with accurate Retina DPI metadata (no intermediate TIFF!)
    public static func encode(
        cgImage: CGImage,
        format: SaveImageFormat,
        scaleFactor: CGFloat = 2.0,
        jpegQuality: Double = 0.92
    ) -> Data? {
        let data = NSMutableData()
        let utType: CFString = (format == .jpeg ? UTType.jpeg.identifier : UTType.png.identifier) as CFString
        guard let dest = CGImageDestinationCreateWithData(data, utType, 1, nil) else { return nil }

        let dpi = 72.0 * max(1.0, Double(scaleFactor))
        var props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi
        ]
        if format == .jpeg {
            props[kCGImageDestinationLossyCompressionQuality] = jpegQuality
        }

        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Write both PNG and TIFF to pasteboard for universal high-quality pasting across all macOS apps
    @MainActor
    public static func copyToPasteboard(cgImage: CGImage, logicalSize: CGSize, scaleFactor: CGFloat = 2.0) {
        let pb = NSPasteboard.general
        pb.clearContents()

        let item = NSPasteboardItem()
        if let pngData = encode(cgImage: cgImage, format: .png, scaleFactor: scaleFactor) {
            item.setData(pngData, forType: .png)
        }
        let nsImage = NSImage(cgImage: cgImage, size: logicalSize)
        if let tiffData = nsImage.tiffRepresentation {
            item.setData(tiffData, forType: .tiff)
        }
        pb.writeObjects([item])
    }

    @MainActor
    public static func copyToPasteboard(nsImage: NSImage) {
        if let cgImage = cgImage(from: nsImage) {
            let scale = nsImage.size.width > 0 ? CGFloat(cgImage.width) / nsImage.size.width : 2.0
            copyToPasteboard(cgImage: cgImage, logicalSize: nsImage.size, scaleFactor: scale)
        } else {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([nsImage])
        }
    }

    public static func cgImage(from nsImage: NSImage) -> CGImage? {
        var rect = NSRect(origin: .zero, size: nsImage.size)
        if let cg = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return cg
        }
        if let tiff = nsImage.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff) {
            return rep.cgImage
        }
        return nil
    }

    /// Generate timestamped filename like PixSnap_20261124_093012.png
    public static func defaultFilename(format: SaveImageFormat) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        return "PixSnap_\(df.string(from: Date())).\(format.fileExtension)"
    }

    /// Render a crisp Retina card image from clipboard text so users can pin copied text snippets!
    @MainActor
    public static func renderTextCardImage(text: String, scaleFactor: CGFloat = 2.0) -> (cgImage: CGImage, nsImage: NSImage)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let padding: CGFloat = 18
        let maxWidth: CGFloat = 480
        let maxHeight: CGFloat = 520
        let font = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.lineBreakMode = .byWordWrapping

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(white: 0.95, alpha: 1.0),
            .paragraphStyle: paragraph
        ]

        let attrStr = NSAttributedString(string: trimmed, attributes: attrs)
        let measured = attrStr.boundingRect(
            with: NSSize(width: maxWidth - padding * 2, height: maxHeight - padding * 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        let cardW = max(140, min(maxWidth, ceil(measured.width) + padding * 2))
        let cardH = max(56, min(maxHeight, ceil(measured.height) + padding * 2))
        let logicalSize = CGSize(width: cardW, height: cardH)

        let pixelW = Int(round(cardW * scaleFactor))
        let pixelH = Int(round(cardH * scaleFactor))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.scaleBy(x: scaleFactor, y: scaleFactor)

        // Rich dark card background
        ctx.setFillColor(NSColor(red: 0.11, green: 0.12, blue: 0.15, alpha: 1.0).cgColor)
        ctx.fill(CGRect(origin: .zero, size: logicalSize))

        // Subtle top accent bar
        ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.85).cgColor)
        ctx.fill(CGRect(x: 0, y: cardH - 3, width: cardW, height: 3))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let drawRect = NSRect(x: padding, y: padding, width: cardW - padding * 2, height: cardH - padding * 2)
        attrStr.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()

        guard let cg = ctx.makeImage() else { return nil }
        return (cg, NSImage(cgImage: cg, size: logicalSize))
    }

    /// Read an image (or fallback text card) from system pasteboard for "Pin Clipboard"
    @MainActor
    public static func readImageOrTextFromPasteboard(scaleFactor: CGFloat = 2.0) -> (image: NSImage, isTextCard: Bool)? {
        let pb = NSPasteboard.general

        // 1. Try direct image types (PNG / TIFF / NSImage)
        if let img = NSImage(pasteboard: pb), img.isValid, img.size.width >= 1, img.size.height >= 1 {
            // Ensure logical size matches pixel size / scale for Retina PNGs without inflated size
            if let cg = cgImage(from: img) {
                let logicalSize: CGSize
                if img.size.width > 0 && img.size.height > 0 {
                    logicalSize = img.size
                } else {
                    logicalSize = CGSize(width: CGFloat(cg.width) / scaleFactor, height: CGFloat(cg.height) / scaleFactor)
                }
                return (NSImage(cgImage: cg, size: logicalSize), false)
            }
            return (img, false)
        }

        // 2. Try file URL pointing to an image
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let first = urls.first,
           let img = NSImage(contentsOf: first), img.isValid {
            return (img, false)
        }

        // 3. Fallback: render copied text as a sleek sticky card
        if let str = pb.string(forType: .string), !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let card = renderTextCardImage(text: str, scaleFactor: scaleFactor) {
            return (card.nsImage, true)
        }

        return nil
    }
}
