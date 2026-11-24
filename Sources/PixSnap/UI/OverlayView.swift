import Cocoa
import CoreImage
import VisionKit

final class InlineTextField: NSTextField, NSTextFieldDelegate {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    private var maxBounds: CGRect

    init(origin: CGPoint, color: NSColor, fontSize: CGFloat, maxBounds: CGRect) {
        self.maxBounds = maxBounds
        let initW: CGFloat = 150
        let initH: CGFloat = max(30, ceil(fontSize * 1.45) + 8)

        let clampedX = min(max(maxBounds.minX + 2, origin.x), max(maxBounds.minX + 2, maxBounds.maxX - initW - 2))
        let clampedY = min(max(maxBounds.minY + 2, origin.y - initH / 2), max(maxBounds.minY + 2, maxBounds.maxY - initH - 2))

        super.init(frame: NSRect(x: clampedX, y: clampedY, width: initW, height: initH))

        self.delegate = self
        self.isBordered = false
        self.drawsBackground = false
        self.backgroundColor = .clear
        self.textColor = color
        self.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        self.focusRingType = .none
        self.placeholderString = "输入文字 (↵ 确认 · ⇧↵ 换行)"
        self.usesSingleLineMode = false
        self.lineBreakMode = .byWordWrapping
        self.cell?.wraps = false
        self.cell?.isScrollable = true

        self.wantsLayer = true
        self.layer?.cornerRadius = 5
        self.layer?.borderWidth = 1.2
        self.layer?.borderColor = PixTheme.accent.withAlphaComponent(0.9).cgColor
        self.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.38).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateStyle(color: NSColor, fontSize: CGFloat) {
        self.textColor = color
        self.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        resizeToFitContent()
    }

    func resizeToFitContent() {
        let currentFont = font ?? NSFont.systemFont(ofSize: 19, weight: .semibold)
        let displayStr = stringValue.isEmpty ? "输入文字..." : stringValue
        let measured = (displayStr as NSString).size(withAttributes: [.font: currentFont])
        let maxAvailW = max(120, maxBounds.maxX - frame.minX - 4)
        let newW = min(maxAvailW, max(130, ceil(measured.width) + 22))
        let newH = max(ceil(currentFont.pointSize * 1.45) + 8, ceil(measured.height) + 10)
        // Keep top-left anchored visually while growing
        let topY = frame.maxY
        frame = NSRect(x: frame.minX, y: max(maxBounds.minY + 2, topY - newH), width: newW, height: newH)
    }

    func controlTextDidChange(_ obj: Notification) {
        resizeToFitContent()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if let event = NSApp.currentEvent, event.modifierFlags.contains(.shift) {
                textView.insertNewlineIgnoringFieldEditor(nil)
                resizeToFitContent()
                return true
            }
            onCommit?()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onCancel?()
            return true
        }
        return false
    }
}

public final class OverlayView: NSView {
    public let capturedScreen: ScreenCaptureManager.CapturedScreen
    public var detectedWindows: [DetectedWindow]
    public let autoOCRMode: Bool

    // Selection state
    public enum SelectionState {
        case hovering
        case selecting
        case selected
    }

    public private(set) var state: SelectionState = .hovering
    public var selectionRect: CGRect = .zero
    private var hoveredWindow: DetectedWindow?
    private var dragCandidateWindow: DetectedWindow?
    private var isActiveHoverScreen: Bool

    // Dragging & Resizing
    private var dragStartPoint: CGPoint = .zero
    private var isMouseDown: Bool = false
    private var activeHandle: HandleType?
    private var initialSelectionRect: CGRect = .zero

    private enum HandleType: Hashable {
        case move
        case moveAnnotation(UUID)
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    // Annotations + Undo / Redo + Selection
    public private(set) var annotations: [Annotation] = []
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    private var currentAnnotation: Annotation?
    private var selectedAnnotationID: UUID?
    private var dragOriginalAnnotation: Annotation?
    private var didMoveAnnotationDuringDrag: Bool = false
    private var nextCounterNumber: Int = 1
    private var activeTextField: InlineTextField?

    // Lazy effect images (generated ONLY when Mosaic/Blur tool is actually used!)
    nonisolated private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])
    private var mosaicImage: CGImage?
    private var blurImage: CGImage?
    private var isGeneratingEffects: Bool = false

    // UI subviews
    public let magnifier = MagnifierView()
    public let toolbar = ToolbarView()

    // Lifecycle & action callbacks (all coordinated cleanly by AppDelegate!)
    public var onCloseAll: (() -> Void)?
    public var onBecameActiveScreen: (() -> Void)?
    public var onSelectionStarted: (() -> Void)?
    public var onPinRequested: ((NSImage, CGPoint, ImageAnalysis?) -> Void)?
    public var onOCRRequested: ((CGImage) -> Void)?
    public var onSaveAsRequested: ((CGImage, CGFloat) -> Void)?

    // Debounced Live Text pre-analysis for instant Pin selection
    private var preloadedAnalysis: ImageAnalysis?
    private var preAnalysisTask: Task<Void, Never>?

    public override var acceptsFirstResponder: Bool { true }
    public override var isOpaque: Bool { false }

    public init(
        frame frameRect: NSRect,
        captured: ScreenCaptureManager.CapturedScreen,
        isInitialActiveScreen: Bool,
        autoOCRMode: Bool = false
    ) {
        self.capturedScreen = captured
        self.detectedWindows = captured.windows
        self.isActiveHoverScreen = isInitialActiveScreen
        self.autoOCRMode = autoOCRMode
        super.init(frame: frameRect)

        setupSubviews()

        if isInitialActiveScreen {
            let screenMouse = NSEvent.mouseLocation
            let localMouse = CGPoint(
                x: screenMouse.x - captured.screenFrame.origin.x,
                y: screenMouse.y - captured.screenFrame.origin.y
            )
            if bounds.contains(localMouse) {
                if AppSettings.shared.enableWindowDetection {
                    self.hoveredWindow = WindowDetector.shared.findWindow(at: localMouse, in: detectedWindows)
                }
                updateMagnifier(at: localMouse)
            } else {
                magnifier.isHidden = true
            }
        } else {
            magnifier.isHidden = true
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    required init?(coder: NSCoder) { fatalError() }

    public func cleanup() {
        preAnalysisTask?.cancel()
        preAnalysisTask = nil
        activeTextField?.removeFromSuperview()
        activeTextField = nil
        NSCursor.arrow.set()
    }

    public func deactivateHoverFromSiblingScreen() {
        guard state == .hovering else { return }
        isActiveHoverScreen = false
        hoveredWindow = nil
        magnifier.isHidden = true
        needsDisplay = true
    }

    private func setupSubviews() {
        addSubview(magnifier)
        addSubview(toolbar)
        addSubview(toolbar.subBar)
        toolbar.isHidden = true
        toolbar.subBar.isHidden = true

        toolbar.onToolSelected = { [weak self] tool in
            guard let self else { return }
            self.commitInlineText()
            if tool != .none {
                self.selectedAnnotationID = nil
            }
            if tool == .mosaic {
                self.ensureEffectImagesReady()
            }
            self.updateSubBarVisibility()
            self.positionToolbars()
            self.needsDisplay = true
        }

        toolbar.onColorSelected = { [weak self] color in
            guard let self else { return }
            if let field = self.activeTextField {
                field.updateStyle(color: color, fontSize: self.toolbar.activeSize.fontSize)
            }
            if let selID = self.selectedAnnotationID,
               let idx = self.annotations.firstIndex(where: { $0.id == selID }) {
                self.recordUndoSnapshot()
                self.annotations[idx].color = color
                self.invalidateAndReschedulePreAnalysis()
                self.needsDisplay = true
            }
        }

        toolbar.onSizeSelected = { [weak self] preset in
            guard let self else { return }
            if let field = self.activeTextField {
                field.updateStyle(color: self.toolbar.activeColor, fontSize: preset.fontSize)
            }
            if let selID = self.selectedAnnotationID,
               let idx = self.annotations.firstIndex(where: { $0.id == selID }) {
                self.recordUndoSnapshot()
                switch self.annotations[idx].type {
                case .text:
                    self.annotations[idx].fontSize = preset.fontSize
                case .highlighter:
                    self.annotations[idx].lineWidth = preset.highlighterWidth
                case .mosaic:
                    self.annotations[idx].lineWidth = preset.mosaicWidth
                case .counter:
                    self.annotations[idx].lineWidth = preset.counterRadius
                default:
                    self.annotations[idx].lineWidth = preset.strokeWidth
                }
                self.invalidateAndReschedulePreAnalysis()
                self.needsDisplay = true
            }
        }

        toolbar.onMosaicStyleChanged = { [weak self] style in
            guard let self else { return }
            self.ensureEffectImagesReady()
            if let selID = self.selectedAnnotationID,
               let idx = self.annotations.firstIndex(where: { $0.id == selID }),
               self.annotations[idx].type == .mosaic {
                self.recordUndoSnapshot()
                self.annotations[idx].mosaicStyle = style
                self.invalidateAndReschedulePreAnalysis()
                self.needsDisplay = true
            }
        }

        toolbar.onFillToggled = { [weak self] filled in
            guard let self else { return }
            if let selID = self.selectedAnnotationID,
               let idx = self.annotations.firstIndex(where: { $0.id == selID }),
               self.annotations[idx].type.isShapeTool {
                self.recordUndoSnapshot()
                self.annotations[idx].isFilled = filled
                self.invalidateAndReschedulePreAnalysis()
                self.needsDisplay = true
            }
        }

        toolbar.onRectCornerToggled = { [weak self] rounded in
            guard let self else { return }
            AppSettings.shared.rectAnnotationRounded = rounded
            let newRadius = rounded ? AppSettings.shared.rectAnnotationCornerRadius : 0.0
            if let selID = self.selectedAnnotationID,
               let idx = self.annotations.firstIndex(where: { $0.id == selID }),
               self.annotations[idx].type == .rect {
                self.recordUndoSnapshot()
                self.annotations[idx].cornerRadius = newRadius
                self.invalidateAndReschedulePreAnalysis()
                self.needsDisplay = true
            }
        }

        toolbar.onResetCounter = { [weak self] in
            guard let self else { return }
            self.nextCounterNumber = 1
            self.toolbar.subBar.updateCounterPreview(1)
            self.positionToolbars()
        }

        toolbar.onUndo = { [weak self] in self?.performUndo() }
        toolbar.onRedo = { [weak self] in self?.performRedo() }
        toolbar.onCopy = { [weak self] in self?.finishCopy() }
        toolbar.onPin = { [weak self] in self?.finishPin() }
        toolbar.onOCR = { [weak self] in self?.finishOCR() }
        toolbar.onSave = { [weak self] in self?.finishSaveAs() }
        toolbar.onCancel = { [weak self] in
            self?.cancelInlineText()
            self?.onCloseAll?()
        }
    }

    // MARK: - Lazy Mosaic & Gaussian Blur Generation

    private func ensureEffectImagesReady() {
        guard mosaicImage == nil || blurImage == nil else { return }
        guard !isGeneratingEffects else { return }
        isGeneratingEffects = true

        let cgImg = capturedScreen.image
        let scale = capturedScreen.scaleFactor

        Task.detached(priority: .userInitiated) { [weak self] in
            let ciImage = CIImage(cgImage: cgImg)
            let extent = ciImage.extent
            let ctx = OverlayView.sharedCIContext

            var outMosaic: CGImage?
            if let pix = CIFilter(name: "CIPixellate") {
                pix.setValue(ciImage.clampedToExtent(), forKey: kCIInputImageKey)
                pix.setValue(max(10.0, 11.0 * scale), forKey: kCIInputScaleKey)
                if let output = pix.outputImage?.cropped(to: extent) {
                    outMosaic = ctx.createCGImage(output, from: extent)
                }
            }

            var outBlur: CGImage?
            if let blur = CIFilter(name: "CIGaussianBlur") {
                blur.setValue(ciImage.clampedToExtent(), forKey: kCIInputImageKey)
                blur.setValue(max(8.0, 10.0 * scale), forKey: kCIInputRadiusKey)
                if let output = blur.outputImage?.cropped(to: extent) {
                    outBlur = ctx.createCGImage(output, from: extent)
                }
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.mosaicImage = outMosaic
                self.blurImage = outBlur
                self.isGeneratingEffects = false
                self.needsDisplay = true
            }
        }
    }

    /// Synchronous fallback if user exports immediately while effect is still building
    private func ensureEffectsSynchronouslyIfNeeded() {
        let needsMosaic = annotations.contains { $0.type == .mosaic && $0.mosaicStyle == .pixelate }
        let needsBlur = annotations.contains { $0.type == .mosaic && $0.mosaicStyle == .blur }
        guard (needsMosaic && mosaicImage == nil) || (needsBlur && blurImage == nil) else { return }

        let ciImage = CIImage(cgImage: capturedScreen.image)
        let extent = ciImage.extent
        let scale = capturedScreen.scaleFactor
        let ctx = OverlayView.sharedCIContext

        if needsMosaic && mosaicImage == nil, let pix = CIFilter(name: "CIPixellate") {
            pix.setValue(ciImage.clampedToExtent(), forKey: kCIInputImageKey)
            pix.setValue(max(10.0, 11.0 * scale), forKey: kCIInputScaleKey)
            if let out = pix.outputImage?.cropped(to: extent) {
                mosaicImage = ctx.createCGImage(out, from: extent)
            }
        }
        if needsBlur && blurImage == nil, let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(ciImage.clampedToExtent(), forKey: kCIInputImageKey)
            blur.setValue(max(8.0, 10.0 * scale), forKey: kCIInputRadiusKey)
            if let out = blur.outputImage?.cropped(to: extent) {
                blurImage = ctx.createCGImage(out, from: extent)
            }
        }
    }

    // MARK: - Undo / Redo

    private func recordUndoSnapshot() {
        undoStack.append(annotations)
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        syncUndoRedoButtons()
    }

    private func performUndo() {
        commitInlineText()
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = prev
        if let selID = selectedAnnotationID, !annotations.contains(where: { $0.id == selID }) {
            selectedAnnotationID = nil
            updateSubBarVisibility()
        }
        recomputeNextCounterNumber()
        syncUndoRedoButtons()
        invalidateAndReschedulePreAnalysis()
        needsDisplay = true
    }

    private func performRedo() {
        commitInlineText()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        recomputeNextCounterNumber()
        syncUndoRedoButtons()
        invalidateAndReschedulePreAnalysis()
        needsDisplay = true
    }

    private func syncUndoRedoButtons() {
        toolbar.setUndoRedoState(canUndo: !undoStack.isEmpty, canRedo: !redoStack.isEmpty)
    }

    private func recomputeNextCounterNumber() {
        let maxNum = annotations.filter { $0.type == .counter }.map(\.counterNumber).max() ?? 0
        nextCounterNumber = maxNum + 1
        toolbar.subBar.updateCounterPreview(nextCounterNumber)
    }

    // MARK: - Debounced Live Text Pre-Analysis

    private func invalidateAndReschedulePreAnalysis() {
        preloadedAnalysis = nil
        preAnalysisTask?.cancel()
        guard state == .selected, selectionRect.width >= 16, selectionRect.height >= 16, !autoOCRMode else { return }

        preAnalysisTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self, self.state == .selected else { return }
            guard let rendered = self.renderFinalOutput() else { return }
            let analyzer = ImageAnalyzer()
            var config = ImageAnalyzer.Configuration([.text])
            config.locales = ["zh-Hans", "zh-Hant", "en-US"]
            do {
                let analysis = try await analyzer.analyze(rendered.nsImage, orientation: .up, configuration: config)
                if !Task.isCancelled {
                    self.preloadedAnalysis = analysis
                }
            } catch {
                // Fallback handled lazily inside PinWindow
            }
        }
    }

    // MARK: - Mouse Events

    public override func mouseEntered(with event: NSEvent) {
        if state == .hovering && !isActiveHoverScreen {
            isActiveHoverScreen = true
            window?.makeKeyAndOrderFront(nil)
            onBecameActiveScreen?()
        }
    }

    public override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)

        switch state {
        case .hovering:
            if !isActiveHoverScreen {
                isActiveHoverScreen = true
                window?.makeKeyAndOrderFront(nil)
                onBecameActiveScreen?()
            }
            if AppSettings.shared.enableWindowDetection {
                hoveredWindow = WindowDetector.shared.findWindow(at: loc, in: detectedWindows)
            } else {
                hoveredWindow = nil
            }
            NSCursor.crosshair.set()
            updateMagnifier(at: loc)
            needsDisplay = true

        case .selected:
            if toolbar.frame.contains(loc) || (!toolbar.subBar.isHidden && toolbar.subBar.frame.contains(loc)) {
                NSCursor.arrow.set()
                return
            }
            if toolbar.activeTool == .none {
                let handle = hitTestHandles(at: loc)
                updateCursor(for: handle)
            } else if toolbar.activeTool == .text {
                NSCursor.iBeam.set()
            } else {
                NSCursor.crosshair.set()
            }

        case .selecting:
            NSCursor.crosshair.set()
        }
    }

    public override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        dragStartPoint = loc
        isMouseDown = true

        switch state {
        case .hovering:
            dragCandidateWindow = hoveredWindow

        case .selected:
            if let field = activeTextField {
                if field.frame.contains(loc) {
                    return
                } else {
                    commitInlineText()
                }
            }

            // Text tool
            if toolbar.activeTool == .text {
                if selectionRect.contains(loc) {
                    startInlineTextEditor(at: loc)
                }
                return
            }

            // Counter tool: instant click badge placement
            if toolbar.activeTool == .counter {
                if selectionRect.contains(loc) {
                    recordUndoSnapshot()
                    let badge = Annotation(
                        type: .counter,
                        color: toolbar.activeColor,
                        lineWidth: toolbar.activeSize.counterRadius,
                        startPoint: loc,
                        endPoint: loc,
                        counterNumber: nextCounterNumber
                    )
                    annotations.append(badge)
                    nextCounterNumber += 1
                    toolbar.subBar.updateCounterPreview(nextCounterNumber)
                    positionToolbars()
                    invalidateAndReschedulePreAnalysis()
                    needsDisplay = true
                }
                return
            }

            // Other drawing tools
            if toolbar.activeTool != .none {
                if selectionRect.contains(loc) {
                    if toolbar.activeTool == .mosaic {
                        ensureEffectImagesReady()
                    }
                    let lw: CGFloat
                    switch toolbar.activeTool {
                    case .highlighter: lw = toolbar.activeSize.highlighterWidth
                    case .mosaic: lw = toolbar.activeSize.mosaicWidth
                    default: lw = toolbar.activeSize.strokeWidth
                    }
                    let rectRadius: CGFloat = (toolbar.activeTool == .rect && toolbar.isRectRounded)
                        ? AppSettings.shared.rectAnnotationCornerRadius
                        : 0.0
                    currentAnnotation = Annotation(
                        type: toolbar.activeTool,
                        color: toolbar.activeColor,
                        lineWidth: lw,
                        startPoint: loc,
                        endPoint: loc,
                        points: [loc],
                        fontSize: toolbar.activeSize.fontSize,
                        isFilled: toolbar.isFilledShape,
                        cornerRadius: rectRadius,
                        mosaicStyle: toolbar.activeMosaicStyle
                    )
                    needsDisplay = true
                }
                return
            }

            // No drawing tool active -> interact with resize handles, existing annotations, or move selection
            let handle = hitTestHandles(at: loc)
            switch handle {
            case .moveAnnotation(let id):
                selectedAnnotationID = id
                activeHandle = .moveAnnotation(id)
                dragOriginalAnnotation = annotations.first { $0.id == id }
                didMoveAnnotationDuringDrag = false
                if let annot = dragOriginalAnnotation {
                    toolbar.subBar.configure(for: annot.type, nextCounter: nextCounterNumber)
                    toolbar.subBar.syncFromAnnotation(annot)
                }
                updateSubBarVisibility()
                positionToolbars()
                NSCursor.closedHand.set()

            case .some(let h):
                selectedAnnotationID = nil
                updateSubBarVisibility()
                activeHandle = h
                initialSelectionRect = selectionRect
                if h == .move {
                    NSCursor.closedHand.set()
                }

            case .none:
                if !selectionRect.contains(loc) {
                    resetToHover(at: loc)
                }
            }
            needsDisplay = true

        case .selecting:
            break
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let dist = hypot(loc.x - dragStartPoint.x, loc.y - dragStartPoint.y)

        switch state {
        case .hovering:
            if dist > 4 {
                state = .selecting
                hoveredWindow = nil
                dragCandidateWindow = nil
                onSelectionStarted?()
                updateSelectionBox(from: dragStartPoint, to: clampPoint(loc, to: bounds))
                updateMagnifier(at: clampPoint(loc, to: bounds))
                needsDisplay = true
            }

        case .selecting:
            let clamped = clampPoint(loc, to: bounds)
            updateSelectionBox(from: dragStartPoint, to: clamped)
            updateMagnifier(at: clamped)
            needsDisplay = true

        case .selected:
            if toolbar.activeTool == .text || toolbar.activeTool == .counter {
                return
            }

            if var current = currentAnnotation {
                var targetLoc = clampPoint(loc, to: selectionRect)
                if event.modifierFlags.contains(.shift) {
                    targetLoc = clampPoint(
                        Annotation.constrainEndPoint(from: current.startPoint, to: targetLoc, for: current.type),
                        to: selectionRect
                    )
                }

                current.endPoint = targetLoc
                if current.type == .pen || current.type == .mosaic {
                    if let last = current.points.last, hypot(targetLoc.x - last.x, targetLoc.y - last.y) >= 1.5 {
                        current.points.append(targetLoc)
                    }
                } else if current.type == .highlighter {
                    if event.modifierFlags.contains(.shift) {
                        current.points = [current.startPoint, targetLoc]
                    } else if let last = current.points.last, hypot(targetLoc.x - last.x, targetLoc.y - last.y) >= 2.0 {
                        current.points.append(targetLoc)
                    }
                }
                currentAnnotation = current
                needsDisplay = true
            } else if let handle = activeHandle {
                let dx = loc.x - dragStartPoint.x
                let dy = loc.y - dragStartPoint.y

                if case .moveAnnotation(let id) = handle,
                   let original = dragOriginalAnnotation,
                   let idx = annotations.firstIndex(where: { $0.id == id }) {
                    if !didMoveAnnotationDuringDrag && hypot(dx, dy) > 1.5 {
                        recordUndoSnapshot()
                        didMoveAnnotationDuringDrag = true
                    }
                    annotations[idx] = original.translated(by: dx, dy: dy)
                    needsDisplay = true
                } else {
                    selectionRect = resizeAndClampRect(initialSelectionRect, handle: handle, dx: dx, dy: dy)
                    positionToolbars()
                    needsDisplay = true
                }
            }
        }
    }

    public override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        isMouseDown = false

        switch state {
        case .hovering:
            if let hw = dragCandidateWindow {
                selectionRect = clampRectToBounds(hw.rect)
                hoveredWindow = nil
                dragCandidateWindow = nil
                enterSelectedState()
            }

        case .selecting:
            if selectionRect.width >= 6 && selectionRect.height >= 6 {
                enterSelectedState()
            } else {
                state = .hovering
                selectionRect = .zero
                needsDisplay = true
            }

        case .selected:
            if let annot = currentAnnotation {
                let isMeaningful: Bool
                switch annot.type {
                case .rect, .ellipse:
                    isMeaningful = annot.normalizedRect.width >= 2 || annot.normalizedRect.height >= 2
                case .arrow:
                    isMeaningful = hypot(annot.endPoint.x - annot.startPoint.x, annot.endPoint.y - annot.startPoint.y) >= 4
                default:
                    isMeaningful = true
                }
                if isMeaningful {
                    recordUndoSnapshot()
                    annotations.append(annot)
                    invalidateAndReschedulePreAnalysis()
                }
                currentAnnotation = nil
                needsDisplay = true
            }

            if let handle = activeHandle {
                if case .moveAnnotation = handle {
                    if didMoveAnnotationDuringDrag {
                        invalidateAndReschedulePreAnalysis()
                    }
                } else {
                    invalidateAndReschedulePreAnalysis()
                }
                activeHandle = nil
                dragOriginalAnnotation = nil
                didMoveAnnotationDuringDrag = false
                updateCursor(for: hitTestHandles(at: loc))
            }

            // Double-click finishes & copies ONLY when no drawing tool is active and not clicking on an annotation
            if event.clickCount == 2 &&
                toolbar.activeTool == .none &&
                selectedAnnotationID == nil &&
                selectionRect.contains(loc) &&
                !toolbar.frame.contains(loc) &&
                (toolbar.subBar.isHidden || !toolbar.subBar.frame.contains(loc)) {
                finishCopy()
            }
        }
    }

    public override func rightMouseDown(with event: NSEvent) {
        if activeTextField != nil {
            cancelInlineText()
            return
        }
        switch state {
        case .selected:
            if selectedAnnotationID != nil {
                selectedAnnotationID = nil
                updateSubBarVisibility()
                needsDisplay = true
            } else if toolbar.activeTool != .none {
                toolbar.setActiveTool(.none)
            } else {
                let loc = convert(event.locationInWindow, from: nil)
                resetToHover(at: loc)
            }
        case .hovering, .selecting:
            onCloseAll?()
        }
    }

    private func enterSelectedState() {
        state = .selected
        magnifier.isHidden = true
        onSelectionStarted?()
        if autoOCRMode {
            needsDisplay = true
            finishOCR()
            return
        }
        showToolbars()
        invalidateAndReschedulePreAnalysis()
        needsDisplay = true
    }

    private func resetToHover(at point: CGPoint) {
        commitInlineText()
        preAnalysisTask?.cancel()
        preloadedAnalysis = nil
        state = .hovering
        selectionRect = .zero
        annotations.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        selectedAnnotationID = nil
        nextCounterNumber = 1
        toolbar.setActiveTool(.none, notify: false)
        toolbar.subBar.updateCounterPreview(1)
        syncUndoRedoButtons()
        toolbar.isHidden = true
        toolbar.subBar.isHidden = true
        if AppSettings.shared.enableWindowDetection {
            hoveredWindow = WindowDetector.shared.findWindow(at: point, in: detectedWindows)
            dragCandidateWindow = hoveredWindow
        }
        updateMagnifier(at: point)
        NSCursor.crosshair.set()
        needsDisplay = true
    }

    private func updateSelectionBox(from p1: CGPoint, to p2: CGPoint) {
        let minX = min(p1.x, p2.x)
        let maxX = max(p1.x, p2.x)
        let minY = min(p1.y, p2.y)
        let maxY = max(p1.y, p2.y)
        selectionRect = clampRectToBounds(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    }

    // MARK: - Inline Text Editor

    private func startInlineTextEditor(at point: CGPoint) {
        commitInlineText()
        let field = InlineTextField(
            origin: point,
            color: toolbar.activeColor,
            fontSize: toolbar.activeSize.fontSize,
            maxBounds: selectionRect
        )
        field.onCommit = { [weak self] in self?.commitInlineText() }
        field.onCancel = { [weak self] in self?.cancelInlineText() }
        addSubview(field)
        self.activeTextField = field
        window?.makeFirstResponder(field)
    }

    private func commitInlineText() {
        guard let field = activeTextField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let fontSize = field.font?.pointSize ?? toolbar.activeSize.fontSize
        let color = field.textColor ?? toolbar.activeColor
        let textOrigin = CGPoint(x: field.frame.minX + 2, y: field.frame.minY + 4)

        field.removeFromSuperview()
        activeTextField = nil
        window?.makeFirstResponder(self)

        if !text.isEmpty {
            recordUndoSnapshot()
            annotations.append(Annotation(
                type: .text,
                color: color,
                startPoint: textOrigin,
                text: text,
                fontSize: fontSize
            ))
            invalidateAndReschedulePreAnalysis()
        }
        needsDisplay = true
    }

    private func cancelInlineText() {
        guard let field = activeTextField else { return }
        field.removeFromSuperview()
        activeTextField = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    // MARK: - Keyboard Events

    public override func keyDown(with event: NSEvent) {
        if activeTextField != nil {
            super.keyDown(with: event)
            return
        }

        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let char = event.charactersIgnoringModifiers?.lowercased()

        // Esc: layered back-out
        if event.keyCode == 53 {
            if selectedAnnotationID != nil {
                selectedAnnotationID = nil
                updateSubBarVisibility()
                needsDisplay = true
            } else if toolbar.activeTool != .none {
                toolbar.setActiveTool(.none)
            } else if state == .selected {
                let mouse = convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
                resetToHover(at: mouse)
            } else {
                onCloseAll?()
            }
            return
        }

        // Delete / Backspace -> remove selected annotation
        if (event.keyCode == 51 || event.keyCode == 117), let selID = selectedAnnotationID {
            if let idx = annotations.firstIndex(where: { $0.id == selID }) {
                recordUndoSnapshot()
                annotations.remove(at: idx)
                selectedAnnotationID = nil
                recomputeNextCounterNumber()
                updateSubBarVisibility()
                invalidateAndReschedulePreAnalysis()
                needsDisplay = true
            }
            return
        }

        // Enter -> Copy
        if event.keyCode == 36 || event.keyCode == 76 {
            if state == .selected {
                finishCopy()
            } else if state == .hovering, let hw = hoveredWindow {
                selectionRect = clampRectToBounds(hw.rect)
                enterSelectedState()
            }
            return
        }

        // Cmd + A -> Select Full Screen
        if mods == .command && char == "a" {
            selectionRect = bounds
            hoveredWindow = nil
            enterSelectedState()
            return
        }

        // Cmd + C -> Copy screenshot
        if mods == .command && char == "c" && state == .selected {
            finishCopy()
            return
        }

        // Cmd + Shift + S -> Save As
        if mods == [.command, .shift] && char == "s" && state == .selected {
            finishSaveAs()
            return
        }

        // Cmd + S -> Quick Save
        if mods == .command && char == "s" && state == .selected {
            finishQuickSave()
            return
        }

        // Cmd + P or bare T -> Pin
        if ((mods == .command && char == "p") || (mods.isEmpty && char == "t")) && state == .selected {
            finishPin()
            return
        }

        // Cmd + Shift + Z -> Redo
        if mods == [.command, .shift] && char == "z" {
            performRedo()
            return
        }

        // Cmd + Z -> Undo
        if mods == .command && char == "z" {
            performUndo()
            return
        }

        // Tab (while hovering/selecting) -> cycle color format HEX / RGB / HSL
        if event.keyCode == 48 && state != .selected && !magnifier.isHidden {
            let newFmt = magnifier.cycleColorFormat()
            ToastHUD.shared.show(
                "取色格式切换为 \(newFmt.displayName)",
                symbolName: "eyedropper",
                accentColor: .systemBlue,
                duration: 1.2
            )
            return
        }

        // Bare C (while hovering/selecting) -> copy pixel color & show toast!
        if mods.isEmpty && char == "c" && state != .selected {
            let colorStr = magnifier.currentColorString
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(colorStr, forType: .string)
            AppSettings.shared.playFeedbackSound()
            let swatch = NSColor(
                srgbRed: CGFloat(magnifier.currentRGB.r) / 255.0,
                green: CGFloat(magnifier.currentRGB.g) / 255.0,
                blue: CGFloat(magnifier.currentRGB.b) / 255.0,
                alpha: 1.0
            )
            ToastHUD.shared.show(
                "已复制色值 \(colorStr)",
                symbolName: "eyedropper.halffull",
                accentColor: swatch,
                duration: 1.5
            )
            return
        }

        // Bare R -> live toggle selection corner style (Sharp 90° vs Rounded)
        if mods.isEmpty && char == "r" {
            let newRounded = !AppSettings.shared.selectionUseRoundedCorners
            AppSettings.shared.selectionUseRoundedCorners = newRounded
            let radiusInt = Int(round(AppSettings.shared.selectionCornerRadius))
            ToastHUD.shared.show(
                newRounded ? "框选边角：圆角 (\(radiusInt)px)" : "框选边角：直角",
                symbolName: newRounded ? "app" : "square",
                accentColor: .systemBlue,
                duration: 1.3
            )
            needsDisplay = true
            return
        }

        // Number keys 1..8 -> quick switch annotation tools when selected
        if mods.isEmpty && state == .selected, let c = char, let num = Int(c), let tool = ToolType(rawValue: num), tool != .none {
            let nextTool: ToolType = (toolbar.activeTool == tool) ? .none : tool
            toolbar.setActiveTool(nextTool)
            return
        }

        // Arrow keys -> nudge selection (or resize with Option) ONLY when selected
        if state == .selected {
            let step: CGFloat = mods.contains(.shift) ? 10 : 1
            let resizeMode = mods.contains(.option)
            var adjusted = false
            switch event.keyCode {
            case 123: // Left
                if resizeMode { selectionRect.size.width = max(10, selectionRect.width - step) }
                else { selectionRect.origin.x -= step }
                adjusted = true
            case 124: // Right
                if resizeMode { selectionRect.size.width += step }
                else { selectionRect.origin.x += step }
                adjusted = true
            case 125: // Down
                if resizeMode { selectionRect.size.height = max(10, selectionRect.height - step) }
                else { selectionRect.origin.y -= step }
                adjusted = true
            case 126: // Up
                if resizeMode { selectionRect.size.height += step }
                else { selectionRect.origin.y += step }
                adjusted = true
            default:
                break
            }
            if adjusted {
                selectionRect = clampRectToBounds(selectionRect)
                positionToolbars()
                invalidateAndReschedulePreAnalysis()
                needsDisplay = true
                return
            }
        }

        super.keyDown(with: event)
    }

    // MARK: - Drawing (Lightweight vector overlay only — background image is GPU-composited!)

    private func selectionCornerPath(for rect: CGRect) -> CGPath {
        let desired = AppSettings.shared.effectiveSelectionCornerRadius
        let clamped = min(desired, min(rect.width, rect.height) * 0.5)
        if clamped > 0.5 {
            return CGPath(roundedRect: rect, cornerWidth: clamped, cornerHeight: clamped, transform: nil)
        }
        return CGPath(rect: rect, transform: nil)
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 1. Dimmed mask outside active cutout
        let activeRect: CGRect
        if state == .hovering, let hw = hoveredWindow, isActiveHoverScreen {
            activeRect = hw.rect
        } else {
            activeRect = selectionRect
        }

        ctx.saveGState()
        ctx.setFillColor(NSColor(white: 0.0, alpha: 0.42).cgColor)
        let maskPath = CGMutablePath()
        maskPath.addRect(bounds)
        if activeRect.width > 0 && activeRect.height > 0 {
            maskPath.addPath(selectionCornerPath(for: activeRect))
        }
        ctx.addPath(maskPath)
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()

        // 2. Hovered window highlight
        if state == .hovering, isActiveHoverScreen, let hw = hoveredWindow {
            ctx.saveGState()
            let r = hw.rect.insetBy(dx: 1, dy: 1)
            ctx.setStrokeColor(PixTheme.accent.cgColor)
            ctx.setLineWidth(2.0)
            ctx.addPath(selectionCornerPath(for: r))
            ctx.strokePath()
            ctx.restoreGState()

            let tag = "\(hw.appName)  \(Int(round(hw.rect.width))) × \(Int(round(hw.rect.height)))"
            drawClampedPillTag(tag, preferredOrigin: CGPoint(x: hw.rect.minX + 8, y: hw.rect.maxY - 28))
        }

        // 3. Annotations & selection chrome
        if (state == .selected || state == .selecting) && selectionRect.width > 0 && selectionRect.height > 0 {
            let selPath = selectionCornerPath(for: selectionRect)

            ctx.saveGState()
            ctx.addPath(selPath)
            ctx.clip()

            for annot in annotations {
                AnnotationRenderer.draw(
                    annot,
                    in: ctx,
                    canvasBounds: bounds,
                    mosaicImage: mosaicImage,
                    blurImage: blurImage
                )
            }
            if let draft = currentAnnotation {
                AnnotationRenderer.draw(
                    draft,
                    in: ctx,
                    canvasBounds: bounds,
                    mosaicImage: mosaicImage,
                    blurImage: blurImage
                )
            }

            // Highlight selected existing annotation with dashed frame
            if let selID = selectedAnnotationID,
               let selAnnot = annotations.first(where: { $0.id == selID }) {
                let box = selAnnot.boundingBox
                ctx.saveGState()
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
                ctx.setLineWidth(1.4)
                ctx.setLineDash(phase: 0, lengths: [4, 3])
                ctx.stroke(box)
                ctx.setStrokeColor(PixTheme.accent.cgColor)
                ctx.setLineDash(phase: 4, lengths: [4, 3])
                ctx.stroke(box)
                ctx.restoreGState()
            }

            ctx.restoreGState()

            // Crisp selection border (sharp 90° or user-configured rounded corners)
            ctx.saveGState()
            ctx.setStrokeColor(PixTheme.accent.cgColor)
            ctx.setLineWidth(1.6)
            ctx.addPath(selPath)
            ctx.strokePath()
            ctx.restoreGState()

            // Smart clamped size tag (never clips off top/right of screen!)
            let wPt = Int(round(selectionRect.width))
            let hPt = Int(round(selectionRect.height))
            let sizeTag = "\(wPt) × \(hPt)"
            let aboveY = selectionRect.maxY + 6
            let tagY = (aboveY + 24 <= bounds.maxY - 4) ? aboveY : max(bounds.minY + 6, selectionRect.maxY - 26)
            drawClampedPillTag(sizeTag, preferredOrigin: CGPoint(x: selectionRect.minX, y: tagY))

            // 8 circular resize handles
            if state == .selected {
                drawHandles(in: ctx)
            }
        }
    }

    private func drawClampedPillTag(_ text: String, preferredOrigin: CGPoint) {
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attr)
        let pillW = ceil(size.width) + 16
        let pillH = ceil(size.height) + 8

        let clampedX = min(max(bounds.minX + 6, preferredOrigin.x), bounds.maxX - pillW - 6)
        let clampedY = min(max(bounds.minY + 6, preferredOrigin.y), bounds.maxY - pillH - 6)
        let pillRect = CGRect(x: clampedX, y: clampedY, width: pillW, height: pillH)

        let path = NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6)
        PixTheme.hudSolid.setFill()
        path.fill()
        PixTheme.hudBorder.setStroke()
        path.lineWidth = 1
        path.stroke()

        (text as NSString).draw(at: CGPoint(x: pillRect.minX + 8, y: pillRect.minY + 4), withAttributes: attr)
    }

    private func drawHandles(in ctx: CGContext) {
        let radius: CGFloat = 4.5
        let handles = getHandleCenters()

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -0.5), blur: 2, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        for center in handles.values {
            let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: circle)
            ctx.setStrokeColor(PixTheme.accent.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: circle)
        }
        ctx.restoreGState()
    }

    private func getHandleCenters() -> [HandleType: CGPoint] {
        let r = selectionRect
        return [
            .topLeft: CGPoint(x: r.minX, y: r.maxY),
            .top: CGPoint(x: r.midX, y: r.maxY),
            .topRight: CGPoint(x: r.maxX, y: r.maxY),
            .right: CGPoint(x: r.maxX, y: r.midY),
            .bottomRight: CGPoint(x: r.maxX, y: r.minY),
            .bottom: CGPoint(x: r.midX, y: r.minY),
            .bottomLeft: CGPoint(x: r.minX, y: r.minY),
            .left: CGPoint(x: r.minX, y: r.midY)
        ]
    }

    private func hitTestHandles(at point: CGPoint) -> HandleType? {
        // 1. 8 circular corner/midpoint handles
        let handleRadius: CGFloat = 9
        for (type, center) in getHandleCenters() {
            if hypot(point.x - center.x, point.y - center.y) <= handleRadius {
                return type
            }
        }

        // 2. Full 4 edges (6pt hit band along each border!)
        let edgeBand: CGFloat = 6
        let r = selectionRect
        if point.x >= r.minX && point.x <= r.maxX {
            if abs(point.y - r.maxY) <= edgeBand { return .top }
            if abs(point.y - r.minY) <= edgeBand { return .bottom }
        }
        if point.y >= r.minY && point.y <= r.maxY {
            if abs(point.x - r.minX) <= edgeBand { return .left }
            if abs(point.x - r.maxX) <= edgeBand { return .right }
        }

        // 3. Existing annotation hit-test (topmost first)
        if toolbar.activeTool == .none {
            for annot in annotations.reversed() {
                if annot.hitTest(point: point) {
                    return .moveAnnotation(annot.id)
                }
            }
        }

        // 4. Inside selection -> move selection
        if r.contains(point) {
            return .move
        }
        return nil
    }

    private func updateCursor(for handle: HandleType?) {
        guard let h = handle else {
            NSCursor.crosshair.set()
            return
        }
        switch h {
        case .move, .moveAnnotation:
            NSCursor.openHand.set()
        case .top, .bottom:
            NSCursor.resizeUpDown.set()
        case .left, .right:
            NSCursor.resizeLeftRight.set()
        case .topLeft:
            if #available(macOS 15.0, *) {
                NSCursor.frameResize(position: .topLeft, directions: .all).set()
            } else {
                NSCursor.crosshair.set()
            }
        case .bottomRight:
            if #available(macOS 15.0, *) {
                NSCursor.frameResize(position: .bottomRight, directions: .all).set()
            } else {
                NSCursor.crosshair.set()
            }
        case .topRight:
            if #available(macOS 15.0, *) {
                NSCursor.frameResize(position: .topRight, directions: .all).set()
            } else {
                NSCursor.crosshair.set()
            }
        case .bottomLeft:
            if #available(macOS 15.0, *) {
                NSCursor.frameResize(position: .bottomLeft, directions: .all).set()
            } else {
                NSCursor.crosshair.set()
            }
        }
    }

    private func clampPoint(_ p: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: max(rect.minX, min(rect.maxX, p.x)),
            y: max(rect.minY, min(rect.maxY, p.y))
        )
    }

    private func clampRectToBounds(_ rect: CGRect) -> CGRect {
        let w = min(rect.width, bounds.width)
        let h = min(rect.height, bounds.height)
        let x = max(bounds.minX, min(bounds.maxX - w, rect.origin.x))
        let y = max(bounds.minY, min(bounds.maxY - h, rect.origin.y))
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func resizeAndClampRect(_ orig: CGRect, handle: HandleType, dx: CGFloat, dy: CGFloat) -> CGRect {
        if handle == .move {
            let moved = CGRect(x: orig.origin.x + dx, y: orig.origin.y + dy, width: orig.width, height: orig.height)
            return clampRectToBounds(moved)
        }

        var minX = orig.minX
        var maxX = orig.maxX
        var minY = orig.minY
        var maxY = orig.maxY

        switch handle {
        case .topLeft:     minX += dx; maxY += dy
        case .top:         maxY += dy
        case .topRight:    maxX += dx; maxY += dy
        case .right:       maxX += dx
        case .bottomRight: maxX += dx; minY += dy
        case .bottom:      minY += dy
        case .bottomLeft:  minX += dx; minY += dy
        case .left:        minX += dx
        default: break
        }

        let clampedMinX = max(bounds.minX, min(bounds.maxX, min(minX, maxX)))
        let clampedMaxX = max(bounds.minX, min(bounds.maxX, max(minX, maxX)))
        let clampedMinY = max(bounds.minY, min(bounds.maxY, min(minY, maxY)))
        let clampedMaxY = max(bounds.minY, min(bounds.maxY, max(minY, maxY)))

        return CGRect(
            x: clampedMinX,
            y: clampedMinY,
            width: max(8, clampedMaxX - clampedMinX),
            height: max(8, clampedMaxY - clampedMinY)
        )
    }

    // MARK: - Magnifier & Dual-Toolbar Positioning

    private func updateMagnifier(at point: CGPoint) {
        guard AppSettings.shared.showMagnifier else {
            magnifier.isHidden = true
            return
        }
        magnifier.isHidden = false
        magnifier.update(
            at: point,
            in: capturedScreen.image,
            viewSize: bounds.size,
            scaleFactor: capturedScreen.scaleFactor,
            selectionRect: state == .selecting ? selectionRect : nil
        )

        let magW = magnifier.bounds.width
        let magH = magnifier.bounds.height
        var magX = point.x + 22
        var magY = point.y - magH - 18

        if magX + magW > bounds.maxX - 8 {
            magX = point.x - magW - 22
        }
        if magY < bounds.minY + 8 {
            magY = point.y + 22
        }
        magX = max(bounds.minX + 8, min(bounds.maxX - magW - 8, magX))
        magY = max(bounds.minY + 8, min(bounds.maxY - magH - 8, magY))
        magnifier.frame.origin = CGPoint(x: round(magX), y: round(magY))
    }

    private func showToolbars() {
        toolbar.isHidden = false
        updateSubBarVisibility()
        positionToolbars()
    }

    private func updateSubBarVisibility() {
        guard !toolbar.isHidden else {
            toolbar.subBar.isHidden = true
            return
        }
        if toolbar.activeTool.hasStyleBar {
            toolbar.subBar.configure(for: toolbar.activeTool, nextCounter: nextCounterNumber)
            toolbar.subBar.isHidden = false
        } else if let selID = selectedAnnotationID,
                  let selAnnot = annotations.first(where: { $0.id == selID }) {
            toolbar.subBar.configure(for: selAnnot.type, nextCounter: nextCounterNumber)
            toolbar.subBar.syncFromAnnotation(selAnnot)
            toolbar.subBar.isHidden = false
        } else {
            toolbar.subBar.isHidden = true
        }
    }

    private func positionToolbars() {
        let margin: CGFloat = 8
        let gap: CGFloat = 6
        let tbW = toolbar.frame.width
        let tbH = toolbar.frame.height
        let subVisible = !toolbar.subBar.isHidden
        let subW = toolbar.subBar.frame.width
        let subH = subVisible ? toolbar.subBar.frame.height : 0
        let totalNeededH = tbH + (subVisible ? (gap + subH) : 0)

        var x = selectionRect.maxX - tbW
        x = max(bounds.minX + margin, min(bounds.maxX - tbW - margin, x))

        let tbY: CGFloat
        let subY: CGFloat

        // Prefer placing toolbar below selection
        if selectionRect.minY - margin - totalNeededH >= bounds.minY + margin {
            tbY = selectionRect.minY - tbH - margin
            subY = tbY - gap - subH
        } else if selectionRect.maxY + margin + totalNeededH <= bounds.maxY - margin {
            // Flip above selection
            tbY = selectionRect.maxY + margin
            subY = tbY + tbH + gap
        } else {
            // Fullscreen / tight vertical space -> neatly float inside bottom of selection
            let baseY = max(bounds.minY + margin, selectionRect.minY + margin)
            if subVisible {
                subY = baseY
                tbY = subY + subH + gap
            } else {
                tbY = baseY
                subY = baseY
            }
        }

        toolbar.frame.origin = CGPoint(x: round(x), y: round(tbY))

        if subVisible {
            var subX = toolbar.frame.minX
            subX = max(bounds.minX + margin, min(bounds.maxX - subW - margin, subX))
            toolbar.subBar.frame.origin = CGPoint(x: round(subX), y: round(subY))
        }
    }

    // MARK: - Final Export & Actions

    private func renderFinalOutput(applySelectionCornerClip: Bool = true) -> (cgImage: CGImage, nsImage: NSImage)? {
        commitInlineText()
        ensureEffectsSynchronouslyIfNeeded()
        let cornerRadius = applySelectionCornerClip ? AppSettings.shared.effectiveSelectionCornerRadius : 0.0
        return ImageExporter.renderCroppedImage(
            fullImage: capturedScreen.image,
            bounds: bounds,
            selectionRect: selectionRect,
            scaleFactor: capturedScreen.scaleFactor,
            annotations: annotations,
            mosaicImage: mosaicImage,
            blurImage: blurImage,
            selectionCornerRadius: cornerRadius
        )
    }

    private func finishCopy() {
        guard let output = renderFinalOutput(applySelectionCornerClip: true) else { return }
        ImageExporter.copyToPasteboard(
            cgImage: output.cgImage,
            logicalSize: output.nsImage.size,
            scaleFactor: capturedScreen.scaleFactor
        )
        AppSettings.shared.playFeedbackSound()
        onCloseAll?()
        ToastHUD.shared.show("已复制到剪贴板", symbolName: "doc.on.clipboard.fill", accentColor: .systemGreen)
    }

    private func finishPin() {
        // Keep unclipped source pixels for PinWindow so user can toggle sharp <-> rounded live anytime!
        guard let output = renderFinalOutput(applySelectionCornerClip: false) else { return }
        let globalOrigin = CGPoint(
            x: capturedScreen.screenFrame.origin.x + selectionRect.origin.x,
            y: capturedScreen.screenFrame.origin.y + selectionRect.origin.y
        )
        let analysis = preloadedAnalysis
        onCloseAll?()
        onPinRequested?(output.nsImage, globalOrigin, analysis)
    }

    private func finishOCR() {
        guard let output = renderFinalOutput(applySelectionCornerClip: false) else { return }
        onCloseAll?()
        onOCRRequested?(output.cgImage)
    }

    private func finishQuickSave() {
        guard let output = renderFinalOutput() else { return }
        let settings = AppSettings.shared
        let format = settings.saveFormat
        let filename = ImageExporter.defaultFilename(format: format)
        let targetURL = settings.saveDirectoryURL.appendingPathComponent(filename)

        guard let data = ImageExporter.encode(
            cgImage: output.cgImage,
            format: format,
            scaleFactor: capturedScreen.scaleFactor,
            jpegQuality: settings.jpegQuality
        ) else { return }

        do {
            try data.write(to: targetURL, options: .atomic)
            if settings.autoCopyOnSave {
                ImageExporter.copyToPasteboard(
                    cgImage: output.cgImage,
                    logicalSize: output.nsImage.size,
                    scaleFactor: capturedScreen.scaleFactor
                )
            }
            settings.playFeedbackSound()
            onCloseAll?()
            let folderName = settings.saveDirectoryURL.lastPathComponent
            ToastHUD.shared.show(
                "已保存到 \(folderName)/\(filename)",
                symbolName: "arrow.down.circle.fill",
                accentColor: .systemBlue,
                duration: 2.0
            )
        } catch {
            onCloseAll?()
            ToastHUD.shared.show(
                "保存失败: \(error.localizedDescription)",
                symbolName: "exclamationmark.triangle.fill",
                accentColor: .systemRed,
                duration: 2.5
            )
        }
    }

    private func finishSaveAs() {
        guard let output = renderFinalOutput() else { return }
        let scale = capturedScreen.scaleFactor
        onCloseAll?()
        onSaveAsRequested?(output.cgImage, scale)
    }
}
