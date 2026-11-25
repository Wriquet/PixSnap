import Testing
import Cocoa
import CoreGraphics
@testable import PixSnap

@MainActor
struct OverlaySelectionResizeTests {
    private func makeOverlay(size: CGSize = CGSize(width: 1000, height: 700)) throws -> (OverlayWindow, OverlayView) {
        let cs = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try #require(CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(NSColor.darkGray.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        let img = try #require(ctx.makeImage())

        let captured = ScreenCaptureManager.CapturedScreen(
            displayID: CGMainDisplayID(),
            image: img,
            screenFrame: CGRect(origin: .zero, size: size),
            pixelSize: size,
            scaleFactor: 1.0,
            windows: [],
            primaryScreenHeight: size.height
        )
        let win = OverlayWindow(captured: captured, isInitialActiveScreen: true)
        return (win, win.overlayView)
    }

    private func makeMouseEvent(_ type: NSEvent.EventType, at point: CGPoint, clickCount: Int = 1) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: type == .leftMouseUp ? 0 : 1
        ))
    }

    private func drag(_ view: OverlayView, from start: CGPoint, to end: CGPoint) throws {
        view.mouseDown(with: try makeMouseEvent(.leftMouseDown, at: start))
        view.mouseDragged(with: try makeMouseEvent(.leftMouseDragged, at: end))
        view.mouseUp(with: try makeMouseEvent(.leftMouseUp, at: end))
    }

    @Test func expandSelectionViaOuterEdgeAndCornerHandles() throws {
        let (win, view) = try makeOverlay()
        defer { win.closeOverlay() }

        // Create initial selection (300, 250, 200, 150) -> x: 300..500, y: 250..400
        try drag(view, from: CGPoint(x: 300, y: 400), to: CGPoint(x: 500, y: 250))
        #expect(view.state == .selected)
        #expect(view.selectionRect == CGRect(x: 300, y: 250, width: 200, height: 150))

        // Toolbar positioned below must leave >= 14pt clearance for bottom corner/edge handles
        #expect(view.toolbar.frame.maxY <= view.selectionRect.minY - 13)

        // Grab 8pt OUTSIDE the right edge and drag outward +80pt -> expands width smoothly without resetting
        try drag(view, from: CGPoint(x: 508, y: 325), to: CGPoint(x: 588, y: 325))
        #expect(view.state == .selected)
        #expect(view.selectionRect == CGRect(x: 300, y: 250, width: 280, height: 150))

        // Grab 10pt OUTSIDE top-left corner and drag outward (-50, +60)
        try drag(view, from: CGPoint(x: 293, y: 407), to: CGPoint(x: 243, y: 467))
        #expect(view.state == .selected)
        #expect(view.selectionRect == CGRect(x: 250, y: 250, width: 330, height: 210))
    }

    @Test func expandSelectionWorksWithRectTextAndCounterToolsActive() throws {
        let (win, view) = try makeOverlay()
        defer { win.closeOverlay() }

        // Initial selection (300, 250, 240, 180) -> x: 300..540, y: 250..430
        try drag(view, from: CGPoint(x: 300, y: 430), to: CGPoint(x: 540, y: 250))
        #expect(view.state == .selected)

        // 1. Rect tool active: dragging bottom-right handle expands box instead of failing or drawing a rect
        view.toolbar.setActiveTool(.rect)
        try drag(view, from: CGPoint(x: 540, y: 250), to: CGPoint(x: 620, y: 200))
        #expect(view.selectionRect == CGRect(x: 300, y: 200, width: 320, height: 230))
        #expect(view.annotations.isEmpty)
        #expect(view.toolbar.activeTool == .rect)

        // Drawing well inside selectionRect with Rect tool still works normally
        try drag(view, from: CGPoint(x: 360, y: 360), to: CGPoint(x: 460, y: 280))
        #expect(view.annotations.count == 1)

        // 2. Text tool active: dragging top edge expands upward instead of being blocked
        view.toolbar.setActiveTool(.text)
        try drag(view, from: CGPoint(x: 460, y: 430), to: CGPoint(x: 460, y: 500))
        #expect(view.selectionRect == CGRect(x: 300, y: 200, width: 320, height: 300))
        #expect(view.toolbar.activeTool == .text)

        // 3. Counter tool active: dragging left edge expands leftward without placing a counter badge
        view.toolbar.setActiveTool(.counter)
        try drag(view, from: CGPoint(x: 294, y: 350), to: CGPoint(x: 234, y: 350))
        #expect(view.selectionRect == CGRect(x: 240, y: 200, width: 380, height: 300))
        #expect(view.annotations.count == 1)
        #expect(view.toolbar.activeTool == .counter)
    }

    @Test func redRectAnnotationAutoSelectsAndExpandsWithoutCreatingDuplicateBox() throws {
        let (win, view) = try makeOverlay()
        defer { win.closeOverlay() }

        // Create crop selection (200, 150, 600, 450) -> x: 200..800, y: 150..600
        try drag(view, from: CGPoint(x: 200, y: 600), to: CGPoint(x: 800, y: 150))
        #expect(view.state == .selected)

        // Activate Rect tool and draw a red box (350, 300, 150, 120) -> x: 350..500, y: 300..420
        view.toolbar.setActiveTool(.rect)
        try drag(view, from: CGPoint(x: 350, y: 420), to: CGPoint(x: 500, y: 300))
        #expect(view.annotations.count == 1)
        #expect(view.selectedAnnotationID == view.annotations[0].id)
        #expect(view.annotations[0].normalizedRect == CGRect(x: 350, y: 300, width: 150, height: 120))

        // Immediately grab the RIGHT midpoint handle (500, 360) and drag right -> must EXPAND, NOT create a 2nd box!
        try drag(view, from: CGPoint(x: 500, y: 360), to: CGPoint(x: 620, y: 360))
        #expect(view.annotations.count == 1)
        #expect(view.annotations[0].normalizedRect == CGRect(x: 350, y: 300, width: 270, height: 120))

        // Grab TOP-LEFT corner handle (350, 420) and expand up-left to (320, 460)
        try drag(view, from: CGPoint(x: 350, y: 420), to: CGPoint(x: 320, y: 460))
        #expect(view.annotations.count == 1)
        #expect(view.annotations[0].normalizedRect == CGRect(x: 320, y: 300, width: 300, height: 160))

        // Drag the top border away from handles (390, 460) -> moves the red box instead of creating a new one
        try drag(view, from: CGPoint(x: 390, y: 460), to: CGPoint(x: 410, y: 440))
        #expect(view.annotations.count == 1)
        #expect(view.annotations[0].normalizedRect == CGRect(x: 340, y: 280, width: 300, height: 160))

        // Dragging inside empty hollow interior starts a brand new second red box
        try drag(view, from: CGPoint(x: 420, y: 380), to: CGPoint(x: 520, y: 320))
        #expect(view.annotations.count == 2)
        #expect(view.selectedAnnotationID == view.annotations[1].id)
        #expect(view.annotations[1].normalizedRect == CGRect(x: 420, y: 320, width: 100, height: 60))

        // Undo removes 2nd box, then reverts move, then reverts corner resize
        let cmdZ = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: 0, context: nil, characters: "z", charactersIgnoringModifiers: "z",
            isARepeat: false, keyCode: 6
        ))
        #expect(view.performKeyEquivalent(with: cmdZ) == true)
        #expect(view.annotations.count == 1)
        #expect(view.performKeyEquivalent(with: cmdZ) == true)
        #expect(view.annotations[0].normalizedRect == CGRect(x: 320, y: 300, width: 300, height: 160))
    }

    @Test func ellipseAndArrowAnnotationsResizeViaHandlesWhileToolActive() throws {
        let (win, view) = try makeOverlay()
        defer { win.closeOverlay() }

        try drag(view, from: CGPoint(x: 150, y: 600), to: CGPoint(x: 850, y: 120))

        // Ellipse: draw then expand bottom-right corner
        view.toolbar.setActiveTool(.ellipse)
        try drag(view, from: CGPoint(x: 250, y: 450), to: CGPoint(x: 350, y: 350))
        #expect(view.annotations.count == 1)
        try drag(view, from: CGPoint(x: 350, y: 350), to: CGPoint(x: 430, y: 290))
        #expect(view.annotations.count == 1)
        #expect(view.annotations[0].normalizedRect == CGRect(x: 250, y: 290, width: 180, height: 160))

        // Arrow: draw then drag arrowhead endpoint to lengthen
        view.toolbar.setActiveTool(.arrow)
        try drag(view, from: CGPoint(x: 500, y: 300), to: CGPoint(x: 620, y: 360))
        #expect(view.annotations.count == 2)
        try drag(view, from: CGPoint(x: 620, y: 360), to: CGPoint(x: 740, y: 420))
        #expect(view.annotations.count == 2)
        #expect(view.annotations[1].startPoint == CGPoint(x: 500, y: 300))
        #expect(view.annotations[1].endPoint == CGPoint(x: 740, y: 420))
    }

    @Test func inlineTextEditorIsTransparentWithNoGrayBackgroundOrPlaceholder() throws {
        let (win, view) = try makeOverlay()
        defer { win.closeOverlay() }

        try drag(view, from: CGPoint(x: 200, y: 550), to: CGPoint(x: 750, y: 180))
        view.toolbar.setActiveTool(.text)
        view.mouseDown(with: try makeMouseEvent(.leftMouseDown, at: CGPoint(x: 360, y: 360)))

        let field = try #require(view.activeTextField)
        #expect(field.drawsBackground == false)
        #expect(field.backgroundColor == .clear)
        #expect(field.isOpaque == false)
        #expect((field.layer?.backgroundColor?.alpha ?? 0) == 0)
        #expect(field.placeholderString == nil)
        #expect(field.frame.width < 60) // Compact caret box, no giant empty placeholder box
    }
}
