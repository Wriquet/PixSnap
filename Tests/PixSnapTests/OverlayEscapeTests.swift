import Testing
import Cocoa
import CoreGraphics
@testable import PixSnap

@MainActor
struct OverlayEscapeTests {
    private func makeCapturedScreen() throws -> ScreenCaptureManager.CapturedScreen {
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
        ctx.setFillColor(NSColor.darkGray.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        let img = try #require(ctx.makeImage())
        return ScreenCaptureManager.CapturedScreen(
            displayID: CGMainDisplayID(),
            image: img,
            screenFrame: CGRect(x: 0, y: 0, width: 200, height: 200),
            pixelSize: CGSize(width: 200, height: 200),
            scaleFactor: 1.0,
            windows: []
        )
    }

    private func makeEscEvent() throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ))
    }

    private func dragRegion(in view: OverlayView, from start: CGPoint, to end: CGPoint) throws {
        let down = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: start,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        let drag = try #require(NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: end,
            modifierFlags: [],
            timestamp: 0.05,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        let up = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: end,
            modifierFlags: [],
            timestamp: 0.1,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
        view.mouseDown(with: down)
        view.mouseDragged(with: drag)
        view.mouseUp(with: up)
    }

    @Test func escExitsImmediatelyAfterRegionSelection() throws {
        let captured = try makeCapturedScreen()
        let window = OverlayWindow(captured: captured, isInitialActiveScreen: true)
        let view = window.overlayView
        defer { window.closeOverlay() }

        var closeCount = 0
        view.onCloseAll = { closeCount += 1 }

        try dragRegion(in: view, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 140, y: 120))
        #expect(view.state == .selected)

        view.keyDown(with: try makeEscEvent())
        #expect(closeCount == 1)
        #expect(view.state == .selected) // must not step back to .hovering
    }

    @Test func escExitsImmediatelyEvenWithActiveAnnotationTool() throws {
        let captured = try makeCapturedScreen()
        let window = OverlayWindow(captured: captured, isInitialActiveScreen: true)
        let view = window.overlayView
        defer { window.closeOverlay() }

        var closeCount = 0
        view.onCloseAll = { closeCount += 1 }

        try dragRegion(in: view, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 140, y: 120))
        view.toolbar.setActiveTool(.rect)
        #expect(view.state == .selected)
        #expect(view.toolbar.activeTool == .rect)

        view.keyDown(with: try makeEscEvent())
        #expect(closeCount == 1)
    }

    @Test func escExitsImmediatelyInHoverStateAndViaCancelOperation() throws {
        let captured = try makeCapturedScreen()
        let window = OverlayWindow(captured: captured, isInitialActiveScreen: true)
        let view = window.overlayView
        defer { window.closeOverlay() }

        var closeCount = 0
        view.onCloseAll = { closeCount += 1 }

        #expect(window.initialFirstResponder === view)
        #expect(view.state == .hovering)

        view.keyDown(with: try makeEscEvent())
        #expect(closeCount == 1)

        window.cancelOperation(nil)
        #expect(closeCount == 2)
    }
}
