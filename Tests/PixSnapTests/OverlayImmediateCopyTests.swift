import Testing
import Cocoa
import CoreGraphics
@testable import PixSnap

@MainActor
struct OverlayImmediateCopyTests {
    private func makeCapturedScreen(windows: [DetectedWindow] = []) throws -> ScreenCaptureManager.CapturedScreen {
        let cs = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try #require(CGContext(
            data: nil,
            width: 240,
            height: 180,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        ctx.setFillColor(NSColor.systemBlue.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 240, height: 180))
        let img = try #require(ctx.makeImage())
        return ScreenCaptureManager.CapturedScreen(
            displayID: CGMainDisplayID(),
            image: img,
            screenFrame: CGRect(x: 0, y: 0, width: 240, height: 180),
            pixelSize: CGSize(width: 240, height: 180),
            scaleFactor: 1.0,
            windows: windows
        )
    }

    private func makeKeyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, chars: String) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: chars,
            charactersIgnoringModifiers: chars,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    @Test func cmdCAndEnterCopyImmediatelyWithoutClickingFirst() throws {
        let captured = try makeCapturedScreen()
        let window = OverlayWindow(captured: captured, isInitialActiveScreen: true)
        let view = window.overlayView
        defer { window.closeOverlay() }

        #expect(view.state == .hovering)
        #expect(view.acceptsFirstMouse(for: nil) == true)

        var closeCount = 0
        view.onCloseAll = { closeCount += 1 }

        // Cmd+C arriving via performKeyEquivalent before any mouse click must copy immediately
        let cmdC = try makeKeyEvent(keyCode: 8, modifiers: [.command], chars: "c")
        let handled = view.performKeyEquivalent(with: cmdC)
        #expect(handled == true)
        #expect(closeCount == 1)
        #expect(view.selectionRect == view.bounds)

        // Enter before any mouse click must also copy immediately
        let window2 = OverlayWindow(captured: captured, isInitialActiveScreen: true)
        let view2 = window2.overlayView
        defer { window2.closeOverlay() }
        var closeCount2 = 0
        view2.onCloseAll = { closeCount2 += 1 }

        let enter = try makeKeyEvent(keyCode: 36, modifiers: [], chars: "\r")
        view2.keyDown(with: enter)
        #expect(closeCount2 == 1)
        #expect(view2.selectionRect == view2.bounds)
    }

    @Test func cmdCWorksUnderEmptyCharactersLikeChineseIMEAndBareCKeepsColorCopy() throws {
        let captured = try makeCapturedScreen()
        let window = OverlayWindow(captured: captured, isInitialActiveScreen: true)
        let view = window.overlayView
        defer { window.closeOverlay() }

        var closeCount = 0
        view.onCloseAll = { closeCount += 1 }

        // Bare 'c' in hovering copies pixel color and must NOT close the overlay
        let bareC = try makeKeyEvent(keyCode: 8, modifiers: [], chars: "c")
        view.keyDown(with: bareC)
        #expect(closeCount == 0)

        // Cmd+C with empty characters (e.g. IME active) still matches keyCode 8 and copies immediately
        let cmdCIME = try makeKeyEvent(keyCode: 8, modifiers: [.command], chars: "")
        let handled = view.performKeyEquivalent(with: cmdCIME)
        #expect(handled == true)
        #expect(closeCount == 1)
    }
}
