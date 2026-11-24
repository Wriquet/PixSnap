import Cocoa

public final class OverlayWindow: NSPanel {
    public let overlayView: OverlayView
    public let capturedScreen: ScreenCaptureManager.CapturedScreen

    public init(
        captured: ScreenCaptureManager.CapturedScreen,
        isInitialActiveScreen: Bool,
        autoOCRMode: Bool = false
    ) {
        self.capturedScreen = captured
        let frame = captured.screenFrame
        let localBounds = NSRect(origin: .zero, size: frame.size)

        self.overlayView = OverlayView(
            frame: localBounds,
            captured: captured,
            isInitialActiveScreen: isInitialActiveScreen,
            autoOCRMode: autoOCRMode
        )

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver
        self.isOpaque = true
        self.backgroundColor = .black
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // Root container splits GPU-composited frozen screenshot layer from dynamic vector OverlayView
        // so moving the mouse or drawing annotations NEVER blits the 5K screenshot on CPU!
        let container = NSView(frame: localBounds)
        container.wantsLayer = true

        let bgView = NSView(frame: localBounds)
        bgView.wantsLayer = true
        bgView.autoresizingMask = [.width, .height]
        bgView.layer?.contents = captured.image
        bgView.layer?.contentsGravity = .resize
        bgView.layer?.contentsScale = captured.scaleFactor

        overlayView.autoresizingMask = [.width, .height]

        container.addSubview(bgView)
        container.addSubview(overlayView)
        self.contentView = container
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    public func closeOverlay() {
        overlayView.cleanup()
        self.orderOut(nil)
        self.close()
    }
}
