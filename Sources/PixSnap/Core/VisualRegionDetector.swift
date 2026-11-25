import Cocoa
import CoreGraphics

/// Zero-permission, sub-millisecond visual rectangle & image border detector operating directly on
/// the frozen screen capture (`CGImage`).
///
/// Combines two complementary detectors:
/// 1. **Uniform-Backdrop Island Detector** — nails standalone images opened in browsers (Chrome dark
///    tab, Safari white page, Preview, chat image viewers), including transparent PNGs or images with
///    edges that partially blend into the background.
/// 2. **4-Sided Straight-Edge Box Detector (Prefix-Sum Accelerated)** — detects embedded photos,
///    UI cards, code blocks, sidebars, dialogs, and panels on complex pages using `O(1)` edge-coverage
///    queries over 3-channel max-diff gradients.
public final class VisualRegionDetector: Sendable {
    public let logicalSize: CGSize
    private let width: Int
    private let height: Int
    private let scaleX: CGFloat
    private let scaleY: CGFloat

    /// Contiguous RGBA8 buffer (size = width * height * 4)
    private let rgba: [UInt8]
    /// Exact horizontal edge mask (vertical gradient |Δy|, size = width * height)
    private let edgeH: [UInt8]
    /// Exact vertical edge mask (horizontal gradient |Δx|, size = width * height)
    private let edgeV: [UInt8]
    /// 1D row prefix sum of 3px-vertically-dilated horizontal edges: index = y * (width + 1) + x
    private let rowPrefixH: [Int32]
    /// 1D column prefix sum of 3px-horizontally-dilated vertical edges: index = x * (height + 1) + y
    private let colPrefixV: [Int32]

    public init?(cgImage: CGImage, logicalSize: CGSize) {
        guard logicalSize.width >= 64, logicalSize.height >= 64 else { return nil }
        self.logicalSize = logicalSize

        // Downsample to ~1x logical points (capped at 1600px on the longest side) for <20ms indexing
        // and <1ms per-move queries with clean Retina anti-aliasing suppression.
        let maxDim: CGFloat = 1600
        let maxLogical = max(logicalSize.width, logicalSize.height)
        let ratio = maxLogical > maxDim ? (maxDim / maxLogical) : 1.0
        let w = max(64, Int(round(logicalSize.width * ratio)))
        let h = max(64, Int(round(logicalSize.height * ratio)))
        self.width = w
        self.height = h
        self.scaleX = CGFloat(w) / logicalSize.width
        self.scaleY = CGFloat(h) / logicalSize.height

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let rendered = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(
                data: buf.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard rendered else { return nil }
        self.rgba = pixels

        var eH = [UInt8](repeating: 0, count: w * h)
        var eV = [UInt8](repeating: 0, count: w * h)

        let threshold1: Int = 11
        let threshold2: Int = 15

        // Compute channel-max horizontal & vertical edge maps
        for y in 1..<(h - 1) {
            let row = y * w
            let prevRow = (y - 1) * w
            let nextRow = (y + 1) * w
            for x in 1..<(w - 1) {
                let idx = (row + x) * 4
                let r = Int(pixels[idx])
                let g = Int(pixels[idx + 1])
                let b = Int(pixels[idx + 2])

                // Vertical gradient -> horizontal border
                let up = (prevRow + x) * 4
                let d1y = max(abs(r - Int(pixels[up])), max(abs(g - Int(pixels[up + 1])), abs(b - Int(pixels[up + 2]))))
                if d1y >= threshold1 {
                    eH[row + x] = 1
                } else {
                    let dn = (nextRow + x) * 4
                    let d2y = max(abs(Int(pixels[dn]) - Int(pixels[up])), max(abs(Int(pixels[dn + 1]) - Int(pixels[up + 1])), abs(Int(pixels[dn + 2]) - Int(pixels[up + 2]))))
                    if d2y >= threshold2 {
                        eH[row + x] = 1
                    }
                }

                // Horizontal gradient -> vertical border
                let lt = (row + x - 1) * 4
                let d1x = max(abs(r - Int(pixels[lt])), max(abs(g - Int(pixels[lt + 1])), abs(b - Int(pixels[lt + 2]))))
                if d1x >= threshold1 {
                    eV[row + x] = 1
                } else {
                    let rt = (row + x + 1) * 4
                    let d2x = max(abs(Int(pixels[rt]) - Int(pixels[lt])), max(abs(Int(pixels[rt + 1]) - Int(pixels[lt + 1])), abs(Int(pixels[rt + 2]) - Int(pixels[lt + 2]))))
                    if d2x >= threshold2 {
                        eV[row + x] = 1
                    }
                }
            }
        }
        self.edgeH = eH
        self.edgeV = eV

        // 1D row prefix sums of 3px-dilated horizontal edges (handles ±1px anti-aliasing effortlessly)
        let rowStride = w + 1
        var rPrefix = [Int32](repeating: 0, count: h * rowStride)
        for y in 0..<h {
            let y0 = max(0, y - 1) * w
            let y1 = y * w
            let y2 = min(h - 1, y + 1) * w
            let pBase = y * rowStride
            var acc: Int32 = 0
            for x in 0..<w {
                if eH[y0 + x] != 0 || eH[y1 + x] != 0 || eH[y2 + x] != 0 {
                    acc += 1
                }
                rPrefix[pBase + x + 1] = acc
            }
        }
        self.rowPrefixH = rPrefix

        // 1D column prefix sums of 3px-dilated vertical edges
        let colStride = h + 1
        var cPrefix = [Int32](repeating: 0, count: w * colStride)
        for x in 0..<w {
            let x0 = max(0, x - 1)
            let x2 = min(w - 1, x + 1)
            let pBase = x * colStride
            var acc: Int32 = 0
            for y in 0..<h {
                let row = y * w
                if eV[row + x0] != 0 || eV[row + x] != 0 || eV[row + x2] != 0 {
                    acc += 1
                }
                cPrefix[pBase + y + 1] = acc
            }
        }
        self.colPrefixV = cPrefix
    }

    // MARK: - Public Query API

    /// Detect visual sub-regions (images, cards, blocks) enclosing `localPoint` inside `windowRect`.
    /// Coordinates are in `OverlayView` local bottom-left points. Results are ordered smallest -> largest.
    public func detectRegions(at localPoint: CGPoint, within windowRect: CGRect) -> [CGRect] {
        guard windowRect.width >= 56, windowRect.height >= 56 else { return [] }
        guard windowRect.contains(localPoint) else { return [] }

        let px = clampInt(Int(round(localPoint.x * scaleX)), 2, width - 3)
        let py = clampInt(Int(round((logicalSize.height - localPoint.y) * scaleY)), 2, height - 3)

        // Convert Cocoa bottom-left windowRect -> top-left working pixels (inset 2px from window frame)
        let bMinX = clampInt(Int(floor(windowRect.minX * scaleX)) + 2, 1, width - 2)
        let bMaxX = clampInt(Int(ceil(windowRect.maxX * scaleX)) - 2, 1, width - 2)
        let bMinY = clampInt(Int(floor((logicalSize.height - windowRect.maxY) * scaleY)) + 2, 1, height - 2)
        let bMaxY = clampInt(Int(ceil((logicalSize.height - windowRect.minY) * scaleY)) - 2, 1, height - 2)

        guard bMaxX - bMinX >= 44, bMaxY - bMinY >= 44 else { return [] }
        guard px > bMinX + 4, px < bMaxX - 4, py > bMinY + 4, py < bMaxY - 4 else { return [] }

        var rawBoxes: [(rect: CGRect, score: CGFloat)] = []

        // 1. Standalone image / lightbox on uniform canvas (e.g., Chrome/Safari opened image tab)
        var lockedViewerIsland = false
        if let island = detectUniformBackdropIsland(px: px, py: py, bMinX: bMinX, bMaxX: bMaxX, bMinY: bMinY, bMaxY: bMaxY) {
            rawBoxes.append((island.rect, 2.5))
            // On dedicated dark image-viewer canvases (e.g. Chrome #0E0E0E image tab, Lightbox, Preview),
            // frame the whole opened image directly instead of fragmenting on internal shapes inside the image.
            lockedViewerIsland = island.isStandaloneViewerCanvas
        }

        // 2. General 4-sided straight-edge boxes (embedded photos, cards, code blocks, panels)
        if !lockedViewerIsland {
            let edgeBoxes = detectEdgeAlignedBoxes(px: px, py: py, bMinX: bMinX, bMaxX: bMaxX, bMinY: bMinY, bMaxY: bMaxY)
            rawBoxes.append(contentsOf: edgeBoxes)
        }

        guard !rawBoxes.isEmpty else { return [] }

        // Convert to logical Cocoa rects, filter out near-window-sized duplicates, and deduplicate
        let winArea = windowRect.width * windowRect.height
        var logicalResults: [CGRect] = []

        // Sort smallest area first (preferring higher score on similar areas)
        rawBoxes.sort { a, b in
            let areaA = a.rect.width * a.rect.height
            let areaB = b.rect.width * b.rect.height
            if abs(areaA - areaB) / max(1, max(areaA, areaB)) < 0.12 {
                return a.score > b.score
            }
            return areaA < areaB
        }

        for item in rawBoxes {
            let r = toLogicalCocoaRect(item.rect).intersection(windowRect)
            guard !r.isNull, r.width >= 32, r.height >= 32 else { continue }
            guard r.contains(localPoint) else { continue }
            // Skip boxes that are basically the entire window
            if (r.width * r.height) / max(1, winArea) > 0.94 { continue }

            let isDup = logicalResults.contains { existing in
                abs(existing.minX - r.minX) <= 8 &&
                abs(existing.minY - r.minY) <= 8 &&
                abs(existing.maxX - r.maxX) <= 8 &&
                abs(existing.maxY - r.maxY) <= 8
            }
            if !isDup {
                logicalResults.append(r)
                if logicalResults.count >= 4 { break }
            }
        }

        return logicalResults
    }

    // MARK: - Detector 1: Uniform Backdrop Island (Browser Single Image / Lightbox / Viewer)

    private func detectUniformBackdropIsland(
        px: Int,
        py: Int,
        bMinX: Int,
        bMaxX: Int,
        bMinY: Int,
        bMaxY: Int
    ) -> (rect: CGRect, isStandaloneViewerCanvas: Bool)? {
        // Check viewport content area (skip potential top browser chrome / titlebar up to 110px)
        let bW = bMaxX - bMinX
        let bH = bMaxY - bMinY
        guard bW >= 120, bH >= 120 else { return nil }

        // Probe candidate backdrop color along interior corners of the lower/middle viewport
        let topSampleY = min(bMaxY - 12, bMinY + min(120, bH / 4))
        let botSampleY = bMaxY - 10
        let leftSampleX = bMinX + 10
        let rightSampleX = bMaxX - 10

        let samples: [(Int, Int)] = [
            (leftSampleX, topSampleY),
            (rightSampleX, topSampleY),
            (leftSampleX, botSampleY),
            (rightSampleX, botSampleY)
        ]

        // Pick a dominant uniform corner color (at least 3 of 4 corners agree within tol 8)
        var bgColor: (Int, Int, Int)?
        for i in 0..<samples.count {
            let c0 = rgbAt(samples[i].0, samples[i].1)
            var matches = 0
            for j in 0..<samples.count {
                if colorDiff(c0, rgbAt(samples[j].0, samples[j].1)) <= 8 {
                    matches += 1
                }
            }
            if matches >= 3 {
                bgColor = c0
                break
            }
        }
        guard let bg = bgColor else { return nil }

        let tol = 10

        // Locate exact viewport vertical bounds along the uniform margins so tall standalone images
        // in browsers never bleed upward into Chrome/Safari's tab bar & address bar!
        var vpMinY = topSampleY
        while vpMinY > bMinY + 1 {
            let yAbove = vpMinY - 1
            if colorDiff(rgbAt(leftSampleX, yAbove), bg) <= tol &&
               colorDiff(rgbAt(rightSampleX, yAbove), bg) <= tol {
                vpMinY = yAbove
            } else {
                break
            }
        }
        var vpMaxY = botSampleY
        while vpMaxY < bMaxY - 1 {
            let yBelow = vpMaxY + 1
            if colorDiff(rgbAt(leftSampleX, yBelow), bg) <= tol &&
               colorDiff(rgbAt(rightSampleX, yBelow), bg) <= tol {
                vpMaxY = yBelow
            } else {
                break
            }
        }

        let vpH = vpMaxY - vpMinY + 1
        guard vpH >= 64, py >= vpMinY, py <= vpMaxY else { return nil }

        // Cursor must be on foreground content (or inside an image whose interior has a bg-colored patch)
        let cursorOnForeground = colorDiff(rgbAt(px, py), bg) > tol
        var seedRadius = 2
        if !cursorOnForeground {
            var nearForeground = false
            for d in stride(from: -16, through: 16, by: 4) {
                let sx = clampInt(px + d, bMinX, bMaxX)
                let sy = clampInt(py + d, vpMinY, vpMaxY)
                if colorDiff(rgbAt(sx, py), bg) > tol || colorDiff(rgbAt(px, sy), bg) > tol {
                    nearForeground = true
                    break
                }
            }
            guard nearForeground else { return nil }
            seedRadius = 16
        }

        var minX = max(bMinX, px - seedRadius)
        var maxX = min(bMaxX, px + seedRadius)
        var minY = max(vpMinY, py - seedRadius)
        var maxY = min(vpMaxY, py + seedRadius)

        func rowHasForeground(_ y: Int, x0: Int, x1: Int) -> Bool {
            let step = max(1, (x1 - x0) / 160)
            var x = x0
            while x <= x1 {
                if colorDiff(rgbAt(x, y), bg) > tol { return true }
                x += step
            }
            return colorDiff(rgbAt(x1, y), bg) > tol
        }

        func colHasForeground(_ x: Int, y0: Int, y1: Int) -> Bool {
            let step = max(1, (y1 - y0) / 160)
            var y = y0
            while y <= y1 {
                if colorDiff(rgbAt(x, y), bg) > tol { return true }
                y += step
            }
            return colorDiff(rgbAt(x, y1), bg) > tol
        }

        // Iteratively expand bounding box until surrounded by clean background (or viewport edge)
        let vpArea = CGFloat(max(1, bW * vpH))
        var changed = true
        var guardLoops = 0
        while changed && guardLoops < 16 {
            changed = false
            guardLoops += 1

            while minX > bMinX && colHasForeground(minX - 1, y0: minY, y1: maxY) {
                minX -= 1
                changed = true
            }
            while maxX < bMaxX && colHasForeground(maxX + 1, y0: minY, y1: maxY) {
                maxX += 1
                changed = true
            }
            while minY > vpMinY && rowHasForeground(minY - 1, x0: minX, x1: maxX) {
                minY -= 1
                changed = true
            }
            while maxY < vpMaxY && rowHasForeground(maxY + 1, x0: minX, x1: maxX) {
                maxY += 1
                changed = true
            }
            if CGFloat((maxX - minX + 1) * (maxY - minY + 1)) / vpArea >= 0.92 {
                return nil
            }
        }

        // Trim any pure-bg perimeter rows/columns left by the initial seed radius so edges snap pixel-exact
        while minX < maxX && !colHasForeground(minX, y0: minY, y1: maxY) { minX += 1 }
        while maxX > minX && !colHasForeground(maxX, y0: minY, y1: maxY) { maxX -= 1 }
        while minY < maxY && !rowHasForeground(minY, x0: minX, x1: maxX) { minY += 1 }
        while maxY > minY && !rowHasForeground(maxY, x0: minX, x1: maxX) { maxY -= 1 }

        // Reject if trimming proved the cursor was actually outside the foreground island in empty margin
        guard minX <= px && px <= maxX && minY <= py && py <= maxY else { return nil }

        let w = maxX - minX + 1
        let h = maxY - minY + 1
        guard w >= 36, h >= 36 else { return nil }
        guard CGFloat(w * h) / vpArea < 0.90 else { return nil }

        var cleanMargins = 0
        if minX > bMinX + 4 { cleanMargins += 1 }
        if maxX < bMaxX - 4 { cleanMargins += 1 }
        if minY > vpMinY + 4 { cleanMargins += 1 }
        if maxY < vpMaxY - 4 { cleanMargins += 1 }

        let isNeutral = abs(bg.0 - bg.1) <= 6 && abs(bg.1 - bg.2) <= 6
        let maxChan = max(bg.0, max(bg.1, bg.2))
        // Chrome dark image tab (#0E0E0E, maxChan=14) or dark Preview/Lightbox canvas with clean margins
        let isStandaloneViewer = isNeutral && (
            (maxChan <= 24 && cleanMargins >= 2) ||
            (maxChan <= 52 && cleanMargins >= 3)
        )

        return (CGRect(x: minX, y: minY, width: w, height: h), isStandaloneViewer)
    }

    // MARK: - Detector 2: 4-Sided Straight-Edge Boxes (Cards, Embedded Photos, Panels)

    private struct LineSeg {
        let coord: Int
        let spanMin: Int
        let spanMax: Int
        var length: Int { spanMax - spanMin }
    }

    private func detectEdgeAlignedBoxes(
        px: Int,
        py: Int,
        bMinX: Int,
        bMaxX: Int,
        bMinY: Int,
        bMaxY: Int
    ) -> [(rect: CGRect, score: CGFloat)] {
        let minSide = 34

        let topCands = scanHorizontalCandidates(fromY: py - 8, toY: bMinY, step: -1, px: px, bMinX: bMinX, bMaxX: bMaxX, minSpan: minSide)
        let botCands = scanHorizontalCandidates(fromY: py + 8, toY: bMaxY, step: 1, px: px, bMinX: bMinX, bMaxX: bMaxX, minSpan: minSide)
        let leftCands = scanVerticalCandidates(fromX: px - 8, toX: bMinX, step: -1, py: py, bMinY: bMinY, bMaxY: bMaxY, minSpan: minSide)
        let rightCands = scanVerticalCandidates(fromX: px + 8, toX: bMaxX, step: 1, py: py, bMinY: bMinY, bMaxY: bMaxY, minSpan: minSide)

        guard !topCands.isEmpty, !botCands.isEmpty, !leftCands.isEmpty, !rightCands.isEmpty else {
            return []
        }

        var results: [(rect: CGRect, score: CGFloat)] = []

        for l in leftCands {
            for r in rightCands {
                let w = r.coord - l.coord
                guard w >= minSide else { continue }
                let hPad = min(22, max(3, Int(CGFloat(w) * 0.16)))

                // Filter top & bottom candidates that have strong horizontal edge coverage across [l.coord, r.coord]
                var matchingTops: [(seg: LineSeg, cov: CGFloat)] = []
                for t in topCands {
                    let cov = horizontalCoverage(y: t.coord, x1: l.coord + hPad, x2: r.coord - hPad)
                    if cov >= 0.72 {
                        matchingTops.append((t, cov))
                    }
                }
                if matchingTops.isEmpty { continue }

                var matchingBots: [(seg: LineSeg, cov: CGFloat)] = []
                for b in botCands {
                    let cov = horizontalCoverage(y: b.coord, x1: l.coord + hPad, x2: r.coord - hPad)
                    if cov >= 0.72 {
                        matchingBots.append((b, cov))
                    }
                }
                if matchingBots.isEmpty { continue }

                for (t, covT) in matchingTops {
                    for (b, covB) in matchingBots {
                        let h = b.coord - t.coord
                        guard h >= minSide else { continue }
                        let vPad = min(22, max(3, Int(CGFloat(h) * 0.16)))

                        let covL = verticalCoverage(x: l.coord, y1: t.coord + vPad, y2: b.coord - vPad)
                        guard covL >= 0.72 else { continue }
                        let covR = verticalCoverage(x: r.coord, y1: t.coord + vPad, y2: b.coord - vPad)
                        guard covR >= 0.72 else { continue }

                        let avgCov = (covT + covB + covL + covR) * 0.25
                        guard avgCov >= 0.80 else { continue }

                        // Every traced side must actually span between its orthogonal borders
                        // (eliminates phantom hybrid boxes formed by mixing edges of nested rectangles).
                        let tolSpan = min(24, max(8, min(w, h) / 6))
                        guard t.spanMin <= l.coord + tolSpan, t.spanMax >= r.coord - tolSpan,
                              b.spanMin <= l.coord + tolSpan, b.spanMax >= r.coord - tolSpan,
                              l.spanMin <= t.coord + tolSpan, l.spanMax >= b.coord - tolSpan,
                              r.spanMin <= t.coord + tolSpan, r.spanMax >= b.coord - tolSpan else {
                            continue
                        }

                        // Count distinct anchored corners (each of the 4 corners contributes 0 or 1,
                        // preventing 2 corners from masking 2 completely unaligned opposite corners).
                        let tolCorner = max(14, min(28, min(w, h) / 6))
                        let tlHit = (abs(t.spanMin - l.coord) <= tolCorner || abs(l.spanMin - t.coord) <= tolCorner)
                        let trHit = (abs(t.spanMax - r.coord) <= tolCorner || abs(r.spanMin - t.coord) <= tolCorner)
                        let blHit = (abs(b.spanMin - l.coord) <= tolCorner || abs(l.spanMax - b.coord) <= tolCorner)
                        let brHit = (abs(b.spanMax - r.coord) <= tolCorner || abs(r.spanMax - b.coord) <= tolCorner)
                        let anchoredCorners = (tlHit ? 1 : 0) + (trHit ? 1 : 0) + (blHit ? 1 : 0) + (brHit ? 1 : 0)
                        guard anchoredCorners >= 3 else { continue }

                        let score = avgCov + CGFloat(anchoredCorners) * 0.12
                        results.append((CGRect(x: l.coord, y: t.coord, width: w, height: h), score))
                    }
                }
            }
        }

        return results
    }

    private func scanHorizontalCandidates(
        fromY: Int,
        toY: Int,
        step: Int,
        px: Int,
        bMinX: Int,
        bMaxX: Int,
        minSpan: Int
    ) -> [LineSeg] {
        var found: [LineSeg] = []
        let probeOffsets = [0, -24, 24, -56, 56]
        var y = fromY
        while (step < 0 ? y >= toY : y <= toY) {
            var hitX: Int?
            for off in probeOffsets {
                let tx = px + off
                if tx >= bMinX && tx <= bMaxX && edgeH[y * width + tx] != 0 {
                    hitX = tx
                    break
                }
            }
            if let hx = hitX {
                let (sMin, sMax) = traceHorizontalSpan(y: y, seedX: hx, bMinX: bMinX, bMaxX: bMaxX)
                if sMin <= px && sMax >= px && (sMax - sMin) >= minSpan {
                    // Non-maximum suppression: merge with immediately adjacent row candidate
                    if let last = found.last, abs(last.coord - y) <= 4 {
                        if (sMax - sMin) > last.length {
                            found[found.count - 1] = LineSeg(coord: y, spanMin: sMin, spanMax: sMax)
                        }
                    } else {
                        found.append(LineSeg(coord: y, spanMin: sMin, spanMax: sMax))
                        if found.count >= 12 { break }
                    }
                }
            }
            y += step
        }
        return found
    }

    private func scanVerticalCandidates(
        fromX: Int,
        toX: Int,
        step: Int,
        py: Int,
        bMinY: Int,
        bMaxY: Int,
        minSpan: Int
    ) -> [LineSeg] {
        var found: [LineSeg] = []
        let probeOffsets = [0, -24, 24, -56, 56]
        var x = fromX
        while (step < 0 ? x >= toX : x <= toX) {
            var hitY: Int?
            for off in probeOffsets {
                let ty = py + off
                if ty >= bMinY && ty <= bMaxY && edgeV[ty * width + x] != 0 {
                    hitY = ty
                    break
                }
            }
            if let hy = hitY {
                let (sMin, sMax) = traceVerticalSpan(x: x, seedY: hy, bMinY: bMinY, bMaxY: bMaxY)
                if sMin <= py && sMax >= py && (sMax - sMin) >= minSpan {
                    if let last = found.last, abs(last.coord - x) <= 4 {
                        if (sMax - sMin) > last.length {
                            found[found.count - 1] = LineSeg(coord: x, spanMin: sMin, spanMax: sMax)
                        }
                    } else {
                        found.append(LineSeg(coord: x, spanMin: sMin, spanMax: sMax))
                        if found.count >= 12 { break }
                    }
                }
            }
            x += step
        }
        return found
    }

    private func traceHorizontalSpan(y: Int, seedX: Int, bMinX: Int, bMaxX: Int) -> (Int, Int) {
        let y0 = max(0, y - 1) * width
        let y1 = y * width
        let y2 = min(height - 1, y + 1) * width
        let maxGap = 4

        var left = seedX
        var gap = 0
        var x = seedX - 1
        while x >= bMinX {
            if edgeH[y0 + x] != 0 || edgeH[y1 + x] != 0 || edgeH[y2 + x] != 0 {
                left = x
                gap = 0
            } else {
                gap += 1
                if gap > maxGap { break }
            }
            x -= 1
        }

        var right = seedX
        gap = 0
        x = seedX + 1
        while x <= bMaxX {
            if edgeH[y0 + x] != 0 || edgeH[y1 + x] != 0 || edgeH[y2 + x] != 0 {
                right = x
                gap = 0
            } else {
                gap += 1
                if gap > maxGap { break }
            }
            x += 1
        }
        return (left, right)
    }

    private func traceVerticalSpan(x: Int, seedY: Int, bMinY: Int, bMaxY: Int) -> (Int, Int) {
        let x0 = max(0, x - 1)
        let x2 = min(width - 1, x + 1)
        let maxGap = 4

        var top = seedY
        var gap = 0
        var y = seedY - 1
        while y >= bMinY {
            let row = y * width
            if edgeV[row + x0] != 0 || edgeV[row + x] != 0 || edgeV[row + x2] != 0 {
                top = y
                gap = 0
            } else {
                gap += 1
                if gap > maxGap { break }
            }
            y -= 1
        }

        var bot = seedY
        gap = 0
        y = seedY + 1
        while y <= bMaxY {
            let row = y * width
            if edgeV[row + x0] != 0 || edgeV[row + x] != 0 || edgeV[row + x2] != 0 {
                bot = y
                gap = 0
            } else {
                gap += 1
                if gap > maxGap { break }
            }
            y += 1
        }
        return (top, bot)
    }

    // MARK: - O(1) Coverage & Pixel Helpers

    @inline(__always)
    private func horizontalCoverage(y: Int, x1: Int, x2: Int) -> CGFloat {
        let a = max(0, min(width - 1, x1))
        let b = max(a + 1, min(width, x2 + 1))
        let rowBase = max(0, min(height - 1, y)) * (width + 1)
        let count = rowPrefixH[rowBase + b] - rowPrefixH[rowBase + a]
        return CGFloat(count) / CGFloat(b - a)
    }

    @inline(__always)
    private func verticalCoverage(x: Int, y1: Int, y2: Int) -> CGFloat {
        let a = max(0, min(height - 1, y1))
        let b = max(a + 1, min(height, y2 + 1))
        let colBase = max(0, min(width - 1, x)) * (height + 1)
        let count = colPrefixV[colBase + b] - colPrefixV[colBase + a]
        return CGFloat(count) / CGFloat(b - a)
    }

    @inline(__always)
    private func rgbAt(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let idx = (y * width + x) * 4
        return (Int(rgba[idx]), Int(rgba[idx + 1]), Int(rgba[idx + 2]))
    }

    @inline(__always)
    private func colorDiff(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Int {
        max(abs(a.0 - b.0), max(abs(a.1 - b.1), abs(a.2 - b.2)))
    }

    @inline(__always)
    private func clampInt(_ v: Int, _ lo: Int, _ hi: Int) -> Int {
        max(lo, min(hi, v))
    }

    private func toLogicalCocoaRect(_ pixelRect: CGRect) -> CGRect {
        let x = pixelRect.minX / scaleX
        let w = pixelRect.width / scaleX
        let h = pixelRect.height / scaleY
        let y = logicalSize.height - (pixelRect.maxY / scaleY)
        return CGRect(x: round(x), y: round(y), width: round(w), height: round(h))
    }
}
