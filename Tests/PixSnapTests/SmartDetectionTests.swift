import Testing
import Cocoa
import CoreGraphics
@testable import PixSnap

struct SmartDetectionTests {
    /// Helper to render a synthetic screen image in standard Cocoa bottom-left coordinates.
    private func makeImage(width: Int, height: Int, draw: (CGContext) -> Void) throws -> CGImage {
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
        draw(ctx)
        return try #require(ctx.makeImage())
    }

    private func approxEqual(_ a: CGRect, _ b: CGRect, tol: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= tol &&
        abs(a.minY - b.minY) <= tol &&
        abs(a.maxX - b.maxX) <= tol &&
        abs(a.maxY - b.maxY) <= tol
    }

    @Test func visualDetectorFramesBrowserStandaloneImageOnDarkBackdrop() throws {
        let winRect = CGRect(x: 0, y: 0, width: 1200, height: 800)
        // Cocoa bottom-left: toolbar is y = 720..800, dark viewport is y = 0..720, photo is (400, 210, 400, 300)
        let photoRect = CGRect(x: 400, y: 210, width: 400, height: 300)

        let img = try makeImage(width: 1200, height: 800) { ctx in
            // Dark Chrome image-tab canvas
            ctx.setFillColor(CGColor(srgbRed: 0.055, green: 0.055, blue: 0.055, alpha: 1))
            ctx.fill(winRect)

            // Browser chrome top toolbar (80px tall)
            ctx.setFillColor(CGColor(srgbRed: 0.22, green: 0.22, blue: 0.24, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 720, width: 1200, height: 80))

            // Standalone photo with colorful content + an internal dark patch
            ctx.setFillColor(CGColor(srgbRed: 0.16, green: 0.52, blue: 0.88, alpha: 1))
            ctx.fill(photoRect)
            ctx.setFillColor(CGColor(srgbRed: 0.96, green: 0.72, blue: 0.24, alpha: 1))
            ctx.fill(CGRect(x: 440, y: 250, width: 180, height: 140))
            ctx.setFillColor(CGColor(srgbRed: 0.055, green: 0.055, blue: 0.055, alpha: 1))
            ctx.fill(CGRect(x: 650, y: 310, width: 40, height: 40))
        }

        let detector = try #require(VisualRegionDetector(cgImage: img, logicalSize: winRect.size))

        // 1. Hover near center of photo
        let centerHits = detector.detectRegions(at: CGPoint(x: 600, y: 360), within: winRect)
        #expect(!centerHits.isEmpty)
        #expect(approxEqual(centerHits[0], photoRect, tol: 4))

        // 2. Hover just 3pt inside the left edge of the photo -> must still snap pixel-tight
        let edgeHits = detector.detectRegions(at: CGPoint(x: 403, y: 360), within: winRect)
        #expect(!edgeHits.isEmpty)
        #expect(approxEqual(edgeHits[0], photoRect, tol: 4))

        // 3. Hover in empty dark margin outside photo -> must NOT falsely highlight the photo
        let marginHits = detector.detectRegions(at: CGPoint(x: 150, y: 360), within: winRect)
        #expect(marginHits.isEmpty)
    }

    @Test func visualDetectorFramesTallBrowserImageWithoutBleedingIntoToolbar() throws {
        let winRect = CGRect(x: 0, y: 0, width: 1200, height: 800)
        // Tall portrait image touches both toolbar bottom (y = 720) and window bottom (y = 0)
        let tallPhoto = CGRect(x: 360, y: 0, width: 480, height: 720)

        let img = try makeImage(width: 1200, height: 800) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 0.06, green: 0.06, blue: 0.06, alpha: 1))
            ctx.fill(winRect)

            // Browser toolbar y = 720..800
            ctx.setFillColor(CGColor(srgbRed: 0.90, green: 0.90, blue: 0.92, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 720, width: 1200, height: 80))

            // Tall photo filling full viewport height
            ctx.setFillColor(CGColor(srgbRed: 0.25, green: 0.68, blue: 0.45, alpha: 1))
            ctx.fill(tallPhoto)
        }

        let detector = try #require(VisualRegionDetector(cgImage: img, logicalSize: winRect.size))
        let hits = detector.detectRegions(at: CGPoint(x: 600, y: 400), within: winRect)
        #expect(!hits.isEmpty)
        // Must frame the tall portrait photo cleanly below the toolbar (never bleeding into y=720..800)
        #expect(abs(hits[0].minX - 360) <= 5)
        #expect(abs(hits[0].maxX - 840) <= 5)
        #expect(abs(hits[0].maxY - 720) <= 5)
        #expect(hits[0].minY <= 12)
    }

    @Test func visualDetectorFramesEmbeddedPhotoAndCardOnComplexWebpage() throws {
        let winRect = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let cardRect = CGRect(x: 340, y: 140, width: 640, height: 480)
        let photoRect = CGRect(x: 380, y: 240, width: 320, height: 220)

        let img = try makeImage(width: 1200, height: 800) { ctx in
            // Light gray page background
            ctx.setFillColor(CGColor(srgbRed: 0.94, green: 0.95, blue: 0.97, alpha: 1))
            ctx.fill(winRect)

            // Left dark sidebar (breaks uniform 4-corner canvas -> forces Layer 2 edge-box detector)
            ctx.setFillColor(CGColor(srgbRed: 0.14, green: 0.16, blue: 0.20, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 260, height: 800))

            // Top header bar
            ctx.setFillColor(CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1))
            ctx.fill(CGRect(x: 260, y: 720, width: 940, height: 80))

            // Elevated white card with subtle gray border
            ctx.setFillColor(CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1))
            ctx.fill(cardRect)
            ctx.setStrokeColor(CGColor(srgbRed: 0.80, green: 0.82, blue: 0.86, alpha: 1))
            ctx.setLineWidth(1.5)
            ctx.stroke(cardRect)

            // Embedded colorful photo inside the card (natural circular sun + diagonal hill, not an axis-aligned inner card)
            ctx.saveGState()
            ctx.clip(to: photoRect)
            ctx.setFillColor(CGColor(srgbRed: 0.24, green: 0.56, blue: 0.88, alpha: 1))
            ctx.fill(photoRect)
            ctx.setFillColor(CGColor(srgbRed: 0.98, green: 0.78, blue: 0.26, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: 420, y: 340, width: 80, height: 80))
            ctx.setFillColor(CGColor(srgbRed: 0.18, green: 0.58, blue: 0.36, alpha: 1))
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 380, y: 240))
            ctx.addLine(to: CGPoint(x: 560, y: 370))
            ctx.addLine(to: CGPoint(x: 700, y: 240))
            ctx.closePath()
            ctx.fillPath()
            ctx.restoreGState()
        }

        let detector = try #require(VisualRegionDetector(cgImage: img, logicalSize: winRect.size))
        let hits = detector.detectRegions(at: CGPoint(x: 520, y: 340), within: winRect)

        #expect(hits.count >= 2)
        // Innermost candidate must be the embedded photo
        #expect(approxEqual(hits[0], photoRect, tol: 6))
        // Outer candidate must include the enclosing card
        #expect(hits.contains { approxEqual($0, cardRect, tol: 8) })
    }

    @Test func visualDetectorReturnsEmptyOnFlatCanvas() throws {
        let winRect = CGRect(x: 0, y: 0, width: 800, height: 600)
        let img = try makeImage(width: 800, height: 600) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            ctx.fill(winRect)
        }
        let detector = try #require(VisualRegionDetector(cgImage: img, logicalSize: winRect.size))
        #expect(detector.detectRegions(at: CGPoint(x: 400, y: 300), within: winRect).isEmpty)
    }

    @Test func candidateStackMergesDeduplicatesAndPreservesZOrder() {
        let axImg = DetectedWindow(
            rect: CGRect(x: 400, y: 200, width: 300, height: 220),
            title: "Chrome",
            appName: "Google Chrome",
            pid: 101,
            elementRoleLabel: "图片"
        )
        let dupVisualImg = DetectedWindow(
            rect: CGRect(x: 402, y: 199, width: 298, height: 221),
            title: "Chrome",
            appName: "Google Chrome",
            pid: 101,
            elementRoleLabel: "识别区域"
        )
        let visualCard = DetectedWindow(
            rect: CGRect(x: 340, y: 140, width: 500, height: 360),
            title: "Chrome",
            appName: "Google Chrome",
            pid: 101,
            elementRoleLabel: "识别区域"
        )
        let axWebArea = DetectedWindow(
            rect: CGRect(x: 100, y: 60, width: 900, height: 620),
            title: "Chrome",
            appName: "Google Chrome",
            pid: 101,
            elementRoleLabel: "内容区"
        )
        let frontWin = DetectedWindow(
            rect: CGRect(x: 100, y: 60, width: 900, height: 700),
            title: "Chrome",
            appName: "Google Chrome",
            pid: 101
        )
        let behindWin = DetectedWindow(
            rect: CGRect(x: 50, y: 40, width: 800, height: 600),
            title: "Notes",
            appName: "备忘录",
            pid: 202
        )

        let stack = WindowDetector.buildCandidateStack(
            axCandidates: [axWebArea, axImg],
            visualCandidates: [dupVisualImg, visualCard],
            windowsAtPoint: [frontWin, behindWin]
        )

        #expect(stack.count == 5)
        // Near-duplicate visual rect must yield to AX semantic "图片"
        #expect(stack[0].elementRoleLabel == "图片")
        #expect(stack[0].hoverTagPrefix == "Google Chrome · 图片")
        #expect(stack[1].rect == visualCard.rect)
        #expect(stack[2].elementRoleLabel == "内容区")
        // Top-level windows preserved strictly in front-to-back Z-order (even though behindWin has smaller area!)
        #expect(stack[3].appName == "Google Chrome")
        #expect(stack[3].hoverTagPrefix == "Google Chrome")
        #expect(stack[4].appName == "备忘录")
    }

    @Test func axRoleLabelMappingCoversCommonControls() {
        #expect(AXElementDetector.localizedRoleLabel("AXImage") == "图片")
        #expect(AXElementDetector.localizedRoleLabel("AXButton") == "按钮")
        #expect(AXElementDetector.localizedRoleLabel("AXToolbar") == "工具栏")
        #expect(AXElementDetector.localizedRoleLabel("AXTabGroup") == "标签栏")
        #expect(AXElementDetector.localizedRoleLabel("AXWebArea") == "内容区")
        #expect(AXElementDetector.localizedRoleLabel("AXTable") == "列表")
        #expect(AXElementDetector.localizedRoleLabel("AXTextField") == "文本框")
        #expect(AXElementDetector.localizedRoleLabel("AXPopover") == "弹窗")
        #expect(AXElementDetector.localizedRoleLabel("AXSplitGroup") == "分栏")
        #expect(AXElementDetector.localizedRoleLabel("AXLink") == "链接")
        #expect(AXElementDetector.localizedRoleLabel("AXStaticText") == "文本")
        #expect(AXElementDetector.localizedRoleLabel("AXUnknownCustom") == "元素")
    }

    @Test @MainActor func overlayStepsHierarchyWithArrowsAndImmediateCopyUsesActiveLevel() throws {
        let screenRect = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let chromeRect = CGRect(x: 100, y: 50, width: 800, height: 600)
        let notesRect = CGRect(x: 20, y: 20, width: 920, height: 650)
        let photoRect = CGRect(x: 340, y: 210, width: 320, height: 220)

        let img = try makeImage(width: 1000, height: 700) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 0.15, green: 0.15, blue: 0.18, alpha: 1))
            ctx.fill(screenRect)
            ctx.setFillColor(CGColor(srgbRed: 0.06, green: 0.06, blue: 0.06, alpha: 1))
            ctx.fill(chromeRect)
            ctx.setFillColor(CGColor(srgbRed: 0.22, green: 0.22, blue: 0.25, alpha: 1))
            ctx.fill(CGRect(x: 100, y: 590, width: 800, height: 60))
            ctx.setFillColor(CGColor(srgbRed: 0.24, green: 0.62, blue: 0.92, alpha: 1))
            ctx.fill(photoRect)
        }

        let chromeWin = DetectedWindow(rect: chromeRect, title: "photo.png", appName: "Google Chrome", pid: 0)
        let notesWin = DetectedWindow(rect: notesRect, title: "备忘录", appName: "备忘录", pid: 0)

        let prevWinDetect = AppSettings.shared.enableWindowDetection
        let prevSmart = AppSettings.shared.enableSmartElementDetection
        AppSettings.shared.enableWindowDetection = true
        AppSettings.shared.enableSmartElementDetection = true
        defer {
            AppSettings.shared.enableWindowDetection = prevWinDetect
            AppSettings.shared.enableSmartElementDetection = prevSmart
        }

        let captured = ScreenCaptureManager.CapturedScreen(
            displayID: CGMainDisplayID(),
            image: img,
            screenFrame: screenRect,
            pixelSize: screenRect.size,
            scaleFactor: 1.0,
            windows: [chromeWin, notesWin],
            primaryScreenHeight: screenRect.height
        )

        let overlayWin = OverlayWindow(captured: captured, isInitialActiveScreen: true)
        let view = overlayWin.overlayView
        defer { overlayWin.closeOverlay() }

        // Inject synchronous visual detector and hover directly on the standalone browser photo
        let syncDetector = try #require(VisualRegionDetector(cgImage: img, logicalSize: screenRect.size))
        view.visualDetector = syncDetector
        view.updateHoverTarget(at: CGPoint(x: 500, y: 320), immediate: true)

        #expect(view.hoverCandidates.count >= 3)
        #expect(view.hoverCandidateIndex == 0)
        #expect(view.hoveredWindow?.elementRoleLabel == "识别区域")
        let initialPhotoRect = try #require(view.hoveredWindow?.rect)
        #expect(approxEqual(initialPhotoRect, photoRect, tol: 5))
        #expect(view.hoverAnimator.currentRect == initialPhotoRect)

        let upEvent = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: 126
        ))
        let downEvent = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: 125
        ))

        // Step outward: photo -> Chrome window -> animator morphs smoothly instead of hard snapping
        view.keyDown(with: upEvent)
        #expect(view.hoverCandidateIndex == 1)
        #expect(view.hoveredWindow?.rect == chromeRect)
        #expect(view.hoverAnimator.targetRect == chromeRect)
        #expect(view.hoverAnimator.isAnimating == true)
        #expect(view.hoverAnimator.currentRect == initialPhotoRect)

        // Small cursor jitter (3pt) right after stepping must NOT flash back to level 0
        view.updateHoverTarget(at: CGPoint(x: 503, y: 321))
        #expect(view.hoverCandidateIndex == 1)
        #expect(view.hoveredWindow?.rect == chromeRect)

        // Step outward again to Notes window behind
        view.keyDown(with: upEvent)
        #expect(view.hoverCandidateIndex == 2)
        #expect(view.hoveredWindow?.rect == notesRect)

        // Step back inward: Notes -> Chrome window
        view.keyDown(with: downEvent)
        #expect(view.hoverCandidateIndex == 1)
        #expect(view.hoveredWindow?.rect == chromeRect)

        // Immediate Cmd+C copies the exact stepped Chrome window even mid-animation
        var closed = 0
        view.onCloseAll = { closed += 1 }
        let cmdC = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: 0, context: nil, characters: "c", charactersIgnoringModifiers: "c",
            isARepeat: false, keyCode: 8
        ))
        #expect(view.performKeyEquivalent(with: cmdC) == true)
        #expect(closed == 1)
        #expect(view.selectionRect == chromeRect)
    }

    @Test func hoverRectAnimatorMorphsSmoothlyWithoutOvershootAndSettles() {
        var anim = HoverRectAnimator()
        let inner = CGRect(x: 400, y: 200, width: 300, height: 200) // minX=400, maxX=700, minY=200, maxY=400
        let outer = CGRect(x: 100, y: 100, width: 600, height: 500) // minX=100, maxX=700 (shared!), minY=100, maxY=600

        // First target snaps instantaneously (never flies in from 0,0)
        anim.setTarget(inner, immediate: true)
        #expect(anim.currentRect == inner)
        #expect(anim.currentAlpha == 1)
        #expect(anim.isAnimating == false)

        // Transition to outer level -> smooth critically-damped glide with ZERO overshoot
        anim.setTarget(outer, immediate: false)
        #expect(anim.isAnimating == true)

        var prevWidth = inner.width
        var settled = false
        for _ in 0..<40 { // up to 333ms @ 120Hz
            let keepGoing = anim.step(dt: 1.0 / 120.0)
            let cur = anim.currentRect
            // Shared right edge (maxX == 700) must stay rock-solid
            #expect(abs(cur.maxX - 700) < 0.01)
            // Monotonic expansion with zero overshoot past outer bounds
            #expect(cur.width >= prevWidth - 0.01)
            #expect(cur.minX >= outer.minX - 0.01)
            #expect(cur.minY >= outer.minY - 0.01)
            #expect(cur.maxY <= outer.maxY + 0.01)
            prevWidth = cur.width
            if !keepGoing {
                settled = true
                break
            }
        }

        #expect(settled == true)
        #expect(anim.currentRect == outer)
        #expect(anim.isAnimating == false)

        // Fading out to nil (hovering onto empty desktop) smoothly reaches alpha 0
        anim.setTarget(nil, immediate: false)
        #expect(anim.isAnimating == true)
        for _ in 0..<30 {
            if !anim.step(dt: 1.0 / 120.0) { break }
        }
        #expect(anim.currentAlpha == 0)
        #expect(anim.isAnimating == false)
    }
}
