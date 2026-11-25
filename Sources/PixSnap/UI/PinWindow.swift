import Cocoa
import VisionKit
import UniformTypeIdentifiers

final class PinContentView: NSView, ImageAnalysisOverlayViewDelegate {
    let imageView: NSImageView
    let overlay: ImageAnalysisOverlayView
    private let zoomBadge = NSTextField(labelWithString: "")
    private var zoomBadgeWorkItem: DispatchWorkItem?

    var onDoubleClicked: (() -> Void)?
    var onMiddleClicked: (() -> Void)?
    var onScrollZoom: ((NSEvent) -> Void)?
    var onMagnifyZoom: ((NSEvent) -> Void)?
    var onFoldToggleClicked: (() -> Void)?
    var isFolded: Bool = false

    init(image: NSImage, preAnalysis: ImageAnalysis? = nil) {
        self.imageView = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        self.imageView.image = image
        self.imageView.imageScaling = .scaleAxesIndependently
        self.imageView.autoresizingMask = [.width, .height]

        self.overlay = ImageAnalysisOverlayView(frame: NSRect(origin: .zero, size: image.size))
        self.overlay.autoresizingMask = [.width, .height]
        self.overlay.trackingImageView = self.imageView
        self.overlay.preferredInteractionTypes = .automatic
        self.overlay.isSupplementaryInterfaceHidden = true
        if let pre = preAnalysis {
            self.overlay.analysis = pre
        }

        super.init(frame: NSRect(origin: .zero, size: image.size))

        wantsLayer = true
        layer?.masksToBounds = true
        updateBorderAppearance()

        addSubview(imageView)
        addSubview(overlay)
        overlay.delegate = self

        // Inline zoom percentage pill HUD
        zoomBadge.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        zoomBadge.textColor = .white
        zoomBadge.alignment = .center
        zoomBadge.wantsLayer = true
        zoomBadge.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.82).cgColor
        zoomBadge.layer?.cornerRadius = 11
        zoomBadge.layer?.borderWidth = 0.8
        zoomBadge.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        zoomBadge.isHidden = true
        zoomBadge.alphaValue = 0
        addSubview(zoomBadge)

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateBorderAppearance() {
        let radius = AppSettings.shared.effectivePinCornerRadius
        layer?.cornerRadius = radius
        layer?.cornerCurve = radius > 0 ? .continuous : .circular
        layer?.masksToBounds = true
        if AppSettings.shared.pinShowBorder {
            layer?.borderWidth = 1.0
            layer?.borderColor = NSColor.gray.withAlphaComponent(0.45).cgColor
        } else {
            layer?.borderWidth = 0
            layer?.borderColor = nil
        }
        window?.invalidateShadow()
    }

    func showZoomBadge(_ text: String) {
        zoomBadgeWorkItem?.cancel()
        zoomBadge.stringValue = "  \(text)  "
        zoomBadge.sizeToFit()
        let w = max(54, ceil(zoomBadge.frame.width) + 8)
        let h: CGFloat = 24
        zoomBadge.frame = NSRect(
            x: round((bounds.width - w) / 2.0),
            y: round((bounds.height - h) / 2.0),
            width: w,
            height: h
        )
        zoomBadge.isHidden = false
        zoomBadge.alphaValue = 1.0

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                self.zoomBadge.animator().alphaValue = 0.0
            }, completionHandler: {
                Task { @MainActor in
                    if self.zoomBadge.alphaValue <= 0.01 {
                        self.zoomBadge.isHidden = true
                    }
                }
            })
        }
        zoomBadgeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: work)
    }

    override func cursorUpdate(with event: NSEvent) {
        if isFolded {
            NSCursor.pointingHand.set()
            return
        }
        let loc = convert(event.locationInWindow, from: nil)
        if !NSEvent.modifierFlags.contains(.option), overlay.hasText(at: loc) {
            NSCursor.iBeam.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if isFolded {
            NSCursor.pointingHand.set()
            return
        }
        let loc = convert(event.locationInWindow, from: nil)
        if !NSEvent.modifierFlags.contains(.option), overlay.hasText(at: loc) {
            NSCursor.iBeam.set()
        } else {
            NSCursor.arrow.set()
        }
        super.mouseMoved(with: event)
    }

    func overlayView(
        _ overlayView: ImageAnalysisOverlayView,
        shouldBeginAt point: CGPoint,
        forAnalysisType analysisType: ImageAnalysisOverlayView.InteractionTypes
    ) -> Bool {
        if isFolded || NSEvent.modifierFlags.contains(.option) {
            return false
        }
        return true
    }

    func overlayView(
        _ overlayView: ImageAnalysisOverlayView,
        updatedMenuFor menu: NSMenu,
        for event: NSEvent,
        at point: CGPoint
    ) -> NSMenu {
        if let pinMenu = self.menu {
            menu.addItem(NSMenuItem.separator())
            for item in pinMenu.items {
                if let copy = item.copy() as? NSMenuItem {
                    menu.addItem(copy)
                }
            }
        }
        return menu
    }

    override func mouseDown(with event: NSEvent) {
        if !(window?.isKeyWindow ?? false) {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        if isFolded {
            if event.clickCount == 2 {
                onFoldToggleClicked?()
                return
            }
            window?.performDrag(with: event)
            return
        }

        let loc = convert(event.locationInWindow, from: nil)
        let isOption = event.modifierFlags.contains(.option)
        let isOverText = overlay.hasText(at: loc)

        if isOption || !isOverText {
            if event.clickCount == 2 {
                onDoubleClicked?()
                return
            }
            window?.performDrag(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isFolded { return }
        let loc = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2 && !overlay.hasText(at: loc) {
            onDoubleClicked?()
        } else {
            super.mouseUp(with: event)
        }
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 {
            onMiddleClicked?()
        } else {
            super.otherMouseUp(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if !isFolded {
            onScrollZoom?(event)
        }
    }

    override func magnify(with event: NSEvent) {
        if !isFolded {
            onMagnifyZoom?(event)
        }
    }
}

public final class PinWindow: NSPanel {
    public var onClosed: ((PinWindow) -> Void)?
    public var onClickThroughChanged: (() -> Void)?
    public var onAppearanceChanged: (() -> Void)?
    public var onRestorePreviousPinRequested: (() -> Void)?

    public let sourceExternalFileURL: URL?
    public private(set) var isClickThrough: Bool = false
    public private(set) var isFolded: Bool = false
    private var preFoldSize: NSSize?
    private var opacityBeforeClickThrough: CGFloat = 1.0

    private var currentImage: NSImage
    private let contentViewWrapper: PinContentView
    private var currentScale: CGFloat = 1.0
    private var baseSize: NSSize
    private var fullRecognizedText: String?

    // For mouse-based locked anchor zoom
    private var activeGestureAnchor: (norm: CGPoint, screenAnchor: CGPoint)?
    private var gestureResetWorkItem: DispatchWorkItem?
    private var didCloseNotify: Bool = false

    public init(
        image: NSImage,
        origin: CGPoint,
        preAnalysis: ImageAnalysis? = nil,
        restoredFrame: NSRect? = nil,
        restoredBaseSize: NSSize? = nil,
        restoredScale: CGFloat = 1.0,
        restoredAlpha: CGFloat = 1.0,
        sourceExternalFileURL: URL? = nil
    ) {
        self.sourceExternalFileURL = sourceExternalFileURL
        self.currentImage = image
        self.baseSize = restoredBaseSize ?? image.size
        self.currentScale = restoredScale
        self.contentViewWrapper = PinContentView(image: image, preAnalysis: preAnalysis)

        let frame = restoredFrame ?? NSRect(origin: origin, size: image.size)
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.alphaValue = restoredAlpha
        self.isMovableByWindowBackground = false
        self.acceptsMouseMovedEvents = true
        self.contentView = contentViewWrapper
        self.isReleasedWhenClosed = false
        applySettings()

        contentViewWrapper.onDoubleClicked = { [weak self] in
            self?.closePin()
        }
        contentViewWrapper.onMiddleClicked = { [weak self] in
            self?.resetScale()
        }
        contentViewWrapper.onScrollZoom = { [weak self] event in
            self?.handleScrollZoom(event: event)
        }
        contentViewWrapper.onMagnifyZoom = { [weak self] event in
            self?.handleMagnifyZoom(event: event)
        }
        contentViewWrapper.onFoldToggleClicked = { [weak self] in
            self?.toggleFoldMode()
        }

        setupContextMenu()

        if let pre = preAnalysis {
            self.fullRecognizedText = pre.transcript
        } else {
            startLiveTextAnalysis()
        }
    }

    public convenience init(restoring record: ClosedPinRecord, image: NSImage? = nil, fallbackOrigin: CGPoint? = nil) {
        let resolvedImage = image ?? record.image
        if record.hasSavedWindowGeometry {
            self.init(
                image: resolvedImage,
                origin: record.frame.origin,
                preAnalysis: nil,
                restoredFrame: record.frame,
                restoredBaseSize: record.baseSize,
                restoredScale: record.scale,
                restoredAlpha: record.alphaValue,
                sourceExternalFileURL: nil
            )
        } else {
            // External image from user-chosen folder: fit neatly on screen & center near cursor
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
                ?? NSScreen.main
                ?? NSScreen.screens.first
            let vis = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
            let maxW = vis.width * 0.75
            let maxH = vis.height * 0.75
            let rawSize = resolvedImage.size
            let fitScale = min(1.0, min(maxW / max(1, rawSize.width), maxH / max(1, rawSize.height)))
            let displaySize = NSSize(
                width: max(40, round(rawSize.width * fitScale)),
                height: max(40, round(rawSize.height * fitScale))
            )
            let anchor = fallbackOrigin ?? NSEvent.mouseLocation
            var origin = CGPoint(
                x: round(anchor.x - displaySize.width / 2.0),
                y: round(anchor.y - displaySize.height / 2.0)
            )
            origin.x = max(vis.minX + 16, min(vis.maxX - displaySize.width - 16, origin.x))
            origin.y = max(vis.minY + 16, min(vis.maxY - displaySize.height - 16, origin.y))
            self.init(
                image: resolvedImage,
                origin: origin,
                preAnalysis: nil,
                restoredFrame: NSRect(origin: origin, size: displaySize),
                restoredBaseSize: rawSize,
                restoredScale: fitScale,
                restoredAlpha: 1.0,
                sourceExternalFileURL: record.fileURL
            )
        }
    }

    public func makeHistoryRecord() -> ClosedPinRecord {
        let saveFrame: NSRect
        if isFolded, let restoreSize = preFoldSize {
            saveFrame = NSRect(
                x: frame.minX,
                y: frame.maxY - restoreSize.height,
                width: restoreSize.width,
                height: restoreSize.height
            )
        } else {
            saveFrame = frame
        }
        let saveAlpha = isClickThrough ? opacityBeforeClickThrough : alphaValue
        return ClosedPinRecord(
            image: currentImage,
            frame: saveFrame,
            baseSize: baseSize,
            scale: currentScale,
            alphaValue: saveAlpha
        )
    }

    public func applySettings() {
        if AppSettings.shared.pinStayAcrossSpaces {
            self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        } else {
            self.collectionBehavior = [.fullScreenAuxiliary]
        }
        contentViewWrapper.updateBorderAppearance()
        self.invalidateShadow()
        setupContextMenu()
    }

    private func startLiveTextAnalysis() {
        let img = self.currentImage
        Task { @MainActor [weak self] in
            guard let self else { return }
            let analyzer = ImageAnalyzer()
            var config = ImageAnalyzer.Configuration([.text])
            config.locales = ["zh-Hans", "zh-Hant", "en-US"]
            do {
                let analysis = try await analyzer.analyze(img, orientation: .up, configuration: config)
                self.fullRecognizedText = analysis.transcript
                self.contentViewWrapper.overlay.analysis = analysis
            } catch {
                // Non-fatal: manual OCR menu remains available
            }
        }
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    private func makeMenuItem(title: String, action: Selector?, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func setupContextMenu() {
        let menu = NSMenu(title: "PinMenu")

        menu.addItem(makeMenuItem(title: "复制文字或图片 (⌘C)", action: #selector(copySelectionOrImage), keyEquivalent: "c"))
        menu.addItem(makeMenuItem(title: "一键复制全部文字 (⇧C)", action: #selector(copyAllText), keyEquivalent: "C"))
        menu.addItem(makeMenuItem(title: "仅复制图片 (⌘⌥C)", action: #selector(copyImage)))
        menu.addItem(makeMenuItem(title: "保存图片... (⌘S)", action: #selector(saveImage), keyEquivalent: "s"))
        menu.addItem(makeMenuItem(title: "识别图中文字 / 二维码 (OCR)", action: #selector(runOCR)))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(makeMenuItem(title: isFolded ? "展开完整贴图 (H / 双击)" : "折叠为缩略图 (H)", action: #selector(toggleFoldMode)))
        menu.addItem(makeMenuItem(title: "顺时针旋转 90° (R)", action: #selector(rotateClockwise)))
        menu.addItem(makeMenuItem(title: "开启鼠标穿透（可在菜单栏恢复）", action: #selector(enableClickThrough)))
        menu.addItem(NSMenuItem.separator())

        // Border & Corner style submenu
        let cornerMenu = NSMenu(title: "边框与边角")
        let s = AppSettings.shared
        let effectiveRadius = s.effectivePinCornerRadius
        let cornerPresets: [(String, CGFloat)] = [
            ("直角 (0px)", 0),
            ("小圆角 (4px)", 4),
            ("标准圆角 (8px)", 8),
            ("大圆角 (14px)", 14)
        ]
        for (title, radius) in cornerPresets {
            let item = makeMenuItem(title: title, action: #selector(setCornerPreset(_:)))
            item.representedObject = radius
            item.state = abs(effectiveRadius - radius) < 0.5 ? .on : .off
            cornerMenu.addItem(item)
        }
        if s.pinUseRoundedCorners && !cornerPresets.contains(where: { abs($0.1 - effectiveRadius) < 0.5 }) {
            let customItem = NSMenuItem(title: "自定义圆角 (\(Int(round(effectiveRadius)))px)", action: nil, keyEquivalent: "")
            customItem.state = .on
            customItem.isEnabled = false
            cornerMenu.addItem(customItem)
        }
        cornerMenu.addItem(NSMenuItem.separator())
        let borderItem = makeMenuItem(title: "显示细边框", action: #selector(toggleBorderVisible))
        borderItem.state = s.pinShowBorder ? .on : .off
        cornerMenu.addItem(borderItem)

        let cornerParent = NSMenuItem(title: "边框与边角", action: nil, keyEquivalent: "")
        cornerParent.submenu = cornerMenu
        menu.addItem(cornerParent)

        // Zoom Anchor submenu
        let anchorMenu = NSMenu(title: "缩放锚点")
        let currentMode = AppSettings.shared.pinZoomAnchorMode
        for mode in PinZoomAnchorMode.allCases {
            let item = makeMenuItem(title: mode.displayName, action: #selector(setZoomMode(_:)))
            item.representedObject = mode.rawValue
            item.state = (mode == currentMode) ? .on : .off
            anchorMenu.addItem(item)
        }
        let anchorParent = NSMenuItem(title: "缩放锚点模式", action: nil, keyEquivalent: "")
        anchorParent.submenu = anchorMenu
        menu.addItem(anchorParent)

        // Opacity submenu
        let opacityMenu = NSMenu(title: "透明度")
        let opacities: [(String, CGFloat)] = [("100%", 1.0), ("80%", 0.8), ("60%", 0.6), ("40%", 0.4), ("20%", 0.2)]
        for (title, val) in opacities {
            let item = makeMenuItem(title: title, action: #selector(setOpacity(_:)))
            item.representedObject = val
            item.state = abs(self.alphaValue - val) < 0.05 ? .on : .off
            opacityMenu.addItem(item)
        }
        let opacityParent = NSMenuItem(title: "透明度", action: nil, keyEquivalent: "")
        opacityParent.submenu = opacityMenu
        menu.addItem(opacityParent)

        menu.addItem(makeMenuItem(title: "重置 100% 原始大小 (0 / 中键)", action: #selector(resetScale), keyEquivalent: "0"))
        menu.addItem(makeMenuItem(title: "恢复上一张关闭的贴图 (⌘Z)", action: #selector(restorePreviousPin), keyEquivalent: "z"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeMenuItem(title: "关闭贴图 (Esc / 双击)", action: #selector(closePin)))

        self.contentViewWrapper.menu = menu
    }

    @objc private func setCornerPreset(_ sender: NSMenuItem) {
        guard let radius = sender.representedObject as? CGFloat else { return }
        if radius <= 0.5 {
            AppSettings.shared.pinUseRoundedCorners = false
        } else {
            AppSettings.shared.pinUseRoundedCorners = true
            AppSettings.shared.pinCornerRadius = radius
        }
        applySettings()
        onAppearanceChanged?()
    }

    @objc private func toggleBorderVisible() {
        AppSettings.shared.pinShowBorder.toggle()
        applySettings()
        onAppearanceChanged?()
    }

    @objc private func setZoomMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = PinZoomAnchorMode(rawValue: raw) else { return }
        AppSettings.shared.pinZoomAnchorMode = mode
        setupContextMenu()
    }

    @objc private func enableClickThrough() {
        isClickThrough = true
        opacityBeforeClickThrough = alphaValue
        ignoresMouseEvents = true
        if alphaValue > 0.72 {
            alphaValue = 0.65
        }
        onClickThroughChanged?()
        ToastHUD.shared.show(
            "已开启鼠标穿透（可在顶部菜单栏恢复）",
            symbolName: "cursorarrow.click.badge.clock",
            accentColor: .systemOrange,
            duration: 2.2
        )
    }

    public func disableClickThrough() {
        guard isClickThrough else { return }
        isClickThrough = false
        ignoresMouseEvents = false
        alphaValue = opacityBeforeClickThrough
        onClickThroughChanged?()
    }

    @objc private func toggleFoldMode() {
        let fixedTopLeftX = frame.minX
        let fixedTopLeftY = frame.maxY
        if !isFolded {
            preFoldSize = frame.size
            isFolded = true
            contentViewWrapper.isFolded = true
            let thumbSide: CGFloat = 68
            setFrame(
                NSRect(x: fixedTopLeftX, y: fixedTopLeftY - thumbSide, width: thumbSide, height: thumbSide),
                display: true,
                animate: true
            )
            contentViewWrapper.showZoomBadge("已折叠")
        } else {
            isFolded = false
            contentViewWrapper.isFolded = false
            let restoreSize = preFoldSize ?? NSSize(
                width: round(baseSize.width * currentScale),
                height: round(baseSize.height * currentScale)
            )
            setFrame(
                NSRect(x: fixedTopLeftX, y: fixedTopLeftY - restoreSize.height, width: restoreSize.width, height: restoreSize.height),
                display: true,
                animate: true
            )
        }
        setupContextMenu()
    }

    @objc private func rotateClockwise() {
        guard !isFolded, let cg = ImageExporter.cgImage(from: currentImage) else { return }
        let newW = cg.height
        let newH = cg.width
        let cs = cg.colorSpace ?? CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: newW,
            height: newH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        ctx.translateBy(x: CGFloat(newW) / 2.0, y: CGFloat(newH) / 2.0)
        ctx.rotate(by: -.pi / 2.0)
        ctx.draw(cg, in: CGRect(x: -CGFloat(cg.width) / 2.0, y: -CGFloat(cg.height) / 2.0, width: CGFloat(cg.width), height: CGFloat(cg.height)))
        guard let rotatedCG = ctx.makeImage() else { return }

        let swappedBase = NSSize(width: baseSize.height, height: baseSize.width)
        let rotatedNS = NSImage(cgImage: rotatedCG, size: swappedBase)
        currentImage = rotatedNS
        baseSize = swappedBase
        contentViewWrapper.imageView.image = rotatedNS
        contentViewWrapper.overlay.analysis = nil
        fullRecognizedText = nil

        let center = CGPoint(x: frame.midX, y: frame.midY)
        let newFrameW = round(baseSize.width * currentScale)
        let newFrameH = round(baseSize.height * currentScale)
        setFrame(
            NSRect(x: round(center.x - newFrameW / 2), y: round(center.y - newFrameH / 2), width: newFrameW, height: newFrameH),
            display: true,
            animate: false
        )
        contentViewWrapper.showZoomBadge("已旋转 90°")
        startLiveTextAnalysis()
    }

    private func handleScrollZoom(event: NSEvent) {
        let factor: CGFloat
        if event.hasPreciseScrollingDeltas {
            let delta = event.scrollingDeltaY * 0.003
            factor = 1.0 + max(-0.05, min(0.05, delta))
        } else {
            let sign: CGFloat = event.deltaY > 0 ? 1 : -1
            factor = 1.0 + sign * 0.06
        }

        if event.phase == .ended || event.phase == .cancelled {
            activeGestureAnchor = nil
        }

        applyScale(currentScale * factor, event: event)
    }

    private func handleMagnifyZoom(event: NSEvent) {
        let factor = 1.0 + max(-0.08, min(0.08, event.magnification))
        if event.phase == .ended || event.phase == .cancelled {
            activeGestureAnchor = nil
        }
        applyScale(currentScale * factor, event: event)
    }

    private func applyScale(_ targetScale: CGFloat, event: NSEvent?) {
        switch AppSettings.shared.pinZoomAnchorMode {
        case .topLeft:
            applyScaleTopLeft(targetScale)
        case .center:
            applyScaleCenter(targetScale)
        case .mouse:
            if let ev = event {
                applyScaleMouse(targetScale, eventLocationInWindow: ev.locationInWindow)
            } else {
                applyScaleCenter(targetScale)
            }
        }
    }

    private func applyScaleTopLeft(_ targetScale: CGFloat) {
        let newScale = max(0.15, min(6.0, targetScale))
        guard abs(newScale - currentScale) > 0.0005 else { return }

        let fixedTopLeftX = frame.minX
        let fixedTopLeftY = frame.maxY
        currentScale = newScale

        let newWidth = max(32, round(baseSize.width * currentScale))
        let newHeight = max(32, round(baseSize.height * currentScale))
        setFrame(
            NSRect(x: fixedTopLeftX, y: fixedTopLeftY - newHeight, width: newWidth, height: newHeight),
            display: true,
            animate: false
        )
        contentViewWrapper.showZoomBadge("\(Int(round(currentScale * 100)))%")
    }

    private func applyScaleCenter(_ targetScale: CGFloat) {
        let newScale = max(0.15, min(6.0, targetScale))
        guard abs(newScale - currentScale) > 0.0005 else { return }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        currentScale = newScale

        let newWidth = max(32, round(baseSize.width * currentScale))
        let newHeight = max(32, round(baseSize.height * currentScale))
        setFrame(
            NSRect(x: round(center.x - newWidth / 2.0), y: round(center.y - newHeight / 2.0), width: newWidth, height: newHeight),
            display: true,
            animate: false
        )
        contentViewWrapper.showZoomBadge("\(Int(round(currentScale * 100)))%")
    }

    private func applyScaleMouse(_ targetScale: CGFloat, eventLocationInWindow: CGPoint) {
        let newScale = max(0.15, min(6.0, targetScale))
        guard abs(newScale - currentScale) > 0.0005 else { return }

        let (normAnchor, screenAnchor): (CGPoint, CGPoint)
        if let existing = activeGestureAnchor {
            (normAnchor, screenAnchor) = existing
        } else {
            let winLoc = eventLocationInWindow
            if winLoc.x < 0 || winLoc.x > frame.width || winLoc.y < 0 || winLoc.y > frame.height {
                applyScaleTopLeft(targetScale)
                return
            }
            let u = max(0.0, min(1.0, winLoc.x / frame.width))
            let v = max(0.0, min(1.0, winLoc.y / frame.height))
            let sAnchor = CGPoint(x: frame.minX + frame.width * u, y: frame.minY + frame.height * v)
            normAnchor = CGPoint(x: u, y: v)
            screenAnchor = sAnchor
            activeGestureAnchor = (normAnchor, screenAnchor)
        }

        gestureResetWorkItem?.cancel()
        let resetWork = DispatchWorkItem { [weak self] in
            self?.activeGestureAnchor = nil
        }
        gestureResetWorkItem = resetWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: resetWork)

        currentScale = newScale
        let newWidth = max(32, round(baseSize.width * currentScale))
        let newHeight = max(32, round(baseSize.height * currentScale))
        let newX = round(screenAnchor.x - newWidth * normAnchor.x)
        let newY = round(screenAnchor.y - newHeight * normAnchor.y)

        setFrame(NSRect(x: newX, y: newY, width: newWidth, height: newHeight), display: true, animate: false)
        contentViewWrapper.showZoomBadge("\(Int(round(currentScale * 100)))%")
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard mods.contains(.command) else { return super.performKeyEquivalent(with: event) }
        let char = event.charactersIgnoringModifiers?.lowercased()
        let kc = event.keyCode

        if mods == .command && (kc == 13 || char == "w") {
            closePin()
            return true
        } else if mods == [.command, .option] && (kc == 8 || char == "c") {
            copyImage()
            return true
        } else if mods == .command && (kc == 8 || char == "c") {
            copySelectionOrImage()
            return true
        } else if mods == .command && (kc == 1 || char == "s") {
            saveImage()
            return true
        } else if mods == .command && (kc == 6 || char == "z") {
            restorePreviousPin()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    public override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let char = event.charactersIgnoringModifiers?.lowercased()

        if event.keyCode == 53 || (mods == .command && char == "w") {
            closePin()
        } else if mods == .shift && char == "c" {
            copyAllText()
        } else if mods == [.command, .option] && char == "c" {
            copyImage()
        } else if mods == .command && char == "c" {
            copySelectionOrImage()
        } else if mods == .command && char == "s" {
            saveImage()
        } else if mods == .command && char == "z" {
            restorePreviousPin()
        } else if mods.isEmpty && char == "h" {
            toggleFoldMode()
        } else if mods.isEmpty && char == "r" {
            rotateClockwise()
        } else if mods.isEmpty && (char == "0" || char == " ") {
            resetScale()
        } else if char == "+" || char == "=" {
            applyScale(currentScale * 1.1, event: nil)
        } else if char == "-" {
            applyScale(currentScale * 0.9, event: nil)
        } else {
            super.keyDown(with: event)
        }
    }

    @objc private func copySelectionOrImage() {
        if contentViewWrapper.overlay.hasActiveTextSelection,
           !contentViewWrapper.overlay.selectedText.isEmpty {
            let text = contentViewWrapper.overlay.selectedText
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            ToastHUD.shared.show("已复制选中文字", symbolName: "text.quote", accentColor: .systemGreen)
        } else {
            copyImage()
        }
    }

    @objc private func copyAllText() {
        guard let text = fullRecognizedText, !text.isEmpty else {
            runOCR()
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        ToastHUD.shared.show("已复制全部文字 (\(text.count) 字)", symbolName: "doc.on.clipboard.fill", accentColor: .systemGreen)
    }

    private func effectiveExportCGImage() -> (cgImage: CGImage, scale: CGFloat)? {
        guard let rawCG = ImageExporter.cgImage(from: currentImage) else { return nil }
        let scale = baseSize.width > 0 ? CGFloat(rawCG.width) / baseSize.width : 2.0
        let radius = AppSettings.shared.effectivePinCornerRadius
        let finalCG = radius > 0.5
            ? ImageExporter.applyRoundedCorners(to: rawCG, cornerRadiusPt: radius, scaleFactor: scale)
            : rawCG
        return (finalCG, scale)
    }

    @objc private func copyImage() {
        if let export = effectiveExportCGImage() {
            ImageExporter.copyToPasteboard(cgImage: export.cgImage, logicalSize: baseSize, scaleFactor: export.scale)
        } else {
            ImageExporter.copyToPasteboard(nsImage: currentImage)
        }
        AppSettings.shared.playFeedbackSound()
        ToastHUD.shared.show("已复制贴图到剪贴板", symbolName: "photo.on.rectangle", accentColor: .systemGreen)
    }

    @objc private func saveImage() {
        guard let export = effectiveExportCGImage() else { return }
        let cg = export.cgImage
        let scale = export.scale
        let settings = AppSettings.shared
        let format = settings.saveFormat

        let panel = NSSavePanel()
        panel.directoryURL = settings.saveDirectoryURL
        panel.allowedContentTypes = format == .jpeg ? [.jpeg, .png] : [.png, .jpeg]
        panel.nameFieldStringValue = ImageExporter.defaultFilename(format: format)

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let actualFormat: SaveImageFormat = url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "jpeg" ? .jpeg : .png
            if let data = ImageExporter.encode(cgImage: cg, format: actualFormat, scaleFactor: scale, jpegQuality: settings.jpegQuality) {
                try? data.write(to: url, options: .atomic)
                ToastHUD.shared.show("已保存 \(url.lastPathComponent)", symbolName: "arrow.down.circle.fill", accentColor: .systemBlue)
            }
        }
    }

    @objc private func runOCR() {
        guard let cg = ImageExporter.cgImage(from: currentImage) else { return }
        ToastHUD.shared.show("正在识别文字...", symbolName: "text.viewfinder", accentColor: .systemBlue, duration: 1.0)
        Task { @MainActor in
            do {
                let result = try await OCREngine.shared.recognizeText(from: cg)
                if result.fullText.isEmpty && result.qrCodes.isEmpty {
                    ToastHUD.shared.show("未识别到文字或二维码", symbolName: "exclamationmark.circle", accentColor: .systemOrange)
                } else {
                    OCRWindowManager.shared.present(result: result)
                }
            } catch {
                ToastHUD.shared.show("OCR 识别失败: \(error.localizedDescription)", symbolName: "exclamationmark.triangle.fill", accentColor: .systemRed)
            }
        }
    }

    @objc private func resetScale() {
        if isFolded {
            toggleFoldMode()
        }
        currentScale = 1.0
        switch AppSettings.shared.pinZoomAnchorMode {
        case .topLeft, .mouse:
            let fixedTopLeftX = frame.minX
            let fixedTopLeftY = frame.maxY
            setFrame(
                NSRect(x: fixedTopLeftX, y: fixedTopLeftY - baseSize.height, width: baseSize.width, height: baseSize.height),
                display: true,
                animate: true
            )
        case .center:
            let center = CGPoint(x: frame.midX, y: frame.midY)
            setFrame(
                NSRect(x: round(center.x - baseSize.width / 2.0), y: round(center.y - baseSize.height / 2.0), width: baseSize.width, height: baseSize.height),
                display: true,
                animate: true
            )
        }
        contentViewWrapper.showZoomBadge("100%")
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        guard let val = sender.representedObject as? CGFloat else { return }
        self.alphaValue = val
        setupContextMenu()
    }

    @objc private func restorePreviousPin() {
        onRestorePreviousPinRequested?()
    }

    @objc public func closePin() {
        guard !didCloseNotify else { return }
        didCloseNotify = true
        self.orderOut(nil)
        self.close()
        onClosed?(self)
    }
}
