import Cocoa

// MARK: - HUD Button

/// Visual role of a toolbar button. Every role shares the same size / radius / icon metrics,
/// only the "selected" treatment differs, so the whole bar reads as one coherent family.
enum HUDButtonStyle {
    /// Main annotation tool: selected = solid accent pill + white glyph.
    case tool
    /// Option inside a segmented track (sizes, fill, corner, mosaic): selected = soft white pill.
    case segment
    /// Plain action (undo, pin, save, cancel…): hover only.
    case plain
    /// The single primary action (Done / Copy): always accent-filled.
    case primary
}

final class HUDButton: NSButton {
    let style: HUDButtonStyle

    var isOn: Bool = false {
        didSet { if oldValue != isOn { refresh(animated: true) } }
    }

    /// Optional hover accent for plain buttons (e.g. red for Cancel).
    var hoverAccent: NSColor? {
        didSet { refresh(animated: false) }
    }

    override var isEnabled: Bool {
        didSet { refresh(animated: true) }
    }

    private var isHovered = false
    private var isPressed = false
    private let cornerRadius: CGFloat

    init(
        image: NSImage?,
        toolTip: String,
        style: HUDButtonStyle,
        size: CGFloat = PixTheme.buttonSize,
        cornerRadius: CGFloat? = nil
    ) {
        self.style = style
        self.cornerRadius = cornerRadius ?? size / 2
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        bezelStyle = .regularSquare
        isBordered = false
        title = ""
        self.toolTip = toolTip
        self.image = image
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        if let cell = cell as? NSButtonCell {
            cell.highlightsBy = []
            cell.showsStateBy = []
        }
        setAccessibilityLabel(toolTip)

        wantsLayer = true
        layer?.cornerRadius = self.cornerRadius
        layer?.cornerCurve = .continuous

        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        refresh(animated: false)
    }

    convenience init(
        symbol: String,
        toolTip: String,
        style: HUDButtonStyle,
        size: CGFloat = PixTheme.buttonSize,
        pointSize: CGFloat = PixTheme.iconPointSize,
        weight: NSFont.Weight = .regular,
        cornerRadius: CGFloat? = nil
    ) {
        self.init(
            image: PixTheme.symbol(symbol, pointSize: pointSize, weight: weight),
            toolTip: toolTip,
            style: style,
            size: size,
            cornerRadius: cornerRadius
        )
    }

    required init?(coder: NSCoder) { fatalError() }

    /// NSButton bezels report non-zero alignment insets, which makes the real frame taller than the
    /// 30×30 constraint (non-square highlight). Zero them so the visible pill is a true square.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        refresh(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refresh(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isPressed = true
        refresh(animated: false)
        super.mouseDown(with: event) // runs the tracking loop until mouse-up
        isPressed = false
        refresh(animated: true)
    }

    override func viewDidHide() {
        super.viewDidHide()
        isHovered = false
        isPressed = false
        refresh(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh(animated: false)
    }

    private func refresh(animated: Bool) {
        let (bg, tint) = resolveColors()
        contentTintColor = tint

        guard let layer else { return }
        var newColor = bg.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { newColor = bg.cgColor }
        if animated {
            let old = layer.presentation()?.backgroundColor ?? layer.backgroundColor
            layer.backgroundColor = newColor
            let anim = CABasicAnimation(keyPath: "backgroundColor")
            anim.fromValue = old
            anim.toValue = newColor
            anim.duration = 0.12
            layer.add(anim, forKey: "bg")
        } else {
            layer.removeAnimation(forKey: "bg")
            layer.backgroundColor = newColor
        }
    }

    private func resolveColors() -> (NSColor, NSColor) {
        guard isEnabled else { return (.clear, PixTheme.iconDisabled) }

        let neutralBg: NSColor = isPressed ? PixTheme.pressedFill : (isHovered ? PixTheme.hoverFill : .clear)

        switch style {
        case .tool:
            if isOn {
                let bg = isPressed ? PixTheme.accent.blended(withFraction: 0.18, of: .black) ?? PixTheme.accent : PixTheme.accent
                return (bg, .white)
            }
            return (neutralBg, PixTheme.icon)

        case .segment:
            if isOn { return (PixTheme.segmentSelected, PixTheme.icon) }
            return (neutralBg, isHovered ? PixTheme.icon : PixTheme.iconSecondary)

        case .plain:
            if let accent = hoverAccent, isHovered {
                return (accent.withAlphaComponent(isPressed ? 0.30 : 0.20), accent)
            }
            return (neutralBg, PixTheme.icon)

        case .primary:
            let bg: NSColor
            if isPressed {
                bg = PixTheme.accent.blended(withFraction: 0.18, of: .black) ?? PixTheme.accent
            } else {
                bg = isHovered ? PixTheme.accentHover : PixTheme.accent
            }
            return (bg, .white)
        }
    }
}

// MARK: - Segmented Track

/// Recessed rounded "track" grouping mutually-exclusive options (like a native segmented control).
final class SegmentTrackView: NSView {
    let stack = NSStackView()

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = PixTheme.segmentTrack.cgColor }

    init(_ buttons: [NSView]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = (PixTheme.segmentSize + 4) / 2   // capsule track
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .horizontal
        stack.spacing = 2
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        stack.translatesAutoresizingMaskIntoConstraints = false
        buttons.forEach { stack.addArrangedSubview($0) }
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Color Swatch

final class ColorSwatchButton: NSButton {
    let swatchColor: NSColor
    var isSelectedColor: Bool = false {
        didSet { needsDisplay = true }
    }
    private var isHovered = false

    init(color: NSColor, name: String) {
        self.swatchColor = color
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        isBordered = false
        title = ""
        toolTip = name
        setAccessibilityLabel(name)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
    override func viewDidHide() { super.viewDidHide(); isHovered = false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let inset: CGFloat = isSelectedColor ? 5.0 : (isHovered ? 3.5 : 4.5)
        let dot = bounds.insetBy(dx: inset, dy: inset)
        ctx.setFillColor(swatchColor.cgColor)
        ctx.fillEllipse(in: dot)

        // Hairline so white / dark-gray swatches stay visible on light *and* dark glass
        ctx.setStrokeColor(PixTheme.swatchHairline.cgColor)
        ctx.setLineWidth(0.75)
        ctx.strokeEllipse(in: dot.insetBy(dx: 0.375, dy: 0.375))

        if isSelectedColor {
            ctx.setStrokeColor(PixTheme.swatchRing.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: bounds.insetBy(dx: 1.75, dy: 1.75))
        }
    }
}

// MARK: - Counter Badge

/// Live preview of the next counter number, drawn in the currently selected color.
final class CounterBadgeView: NSView {
    var number: Int = 1 { didSet { needsDisplay = true } }
    var color: NSColor = .systemRed { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 22))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 26).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let text = "\(number)" as NSString
        let font = NSFont.monospacedDigitSystemFont(ofSize: number >= 100 ? 9 : 11, weight: .bold)
        let textColor: NSColor = (color.usingColorSpace(.sRGB).map { $0.brightnessComponent > 0.85 && $0.saturationComponent < 0.2 } ?? false) ? .black : .white
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let size = text.size(withAttributes: attrs)

        let h: CGFloat = 20
        let w = max(h, ceil(size.width) + 10)
        let pill = CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
        let path = NSBezierPath(roundedRect: pill, xRadius: h / 2, yRadius: h / 2)
        color.setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 1.2
        path.stroke()

        text.draw(at: CGPoint(x: pill.midX - size.width / 2, y: pill.midY - size.height / 2), withAttributes: attrs)
    }
}

// MARK: - Glyph factory

private enum ToolbarGlyphs {
    /// Filled dot used by the stroke-size segments.
    static func dot(diameter: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: CGRect(
                x: (rect.width - diameter) / 2,
                y: (rect.height - diameter) / 2,
                width: diameter,
                height: diameter
            )).fill()
            return true
        }
        img.isTemplate = true
        return img
    }

    /// "A" of growing size used by the text-size segments.
    static func letter(pointSize: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: pointSize, weight: .semibold),
                .foregroundColor: NSColor.black
            ]
            let s = "A" as NSString
            let size = s.size(withAttributes: attrs)
            s.draw(at: CGPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2), withAttributes: attrs)
            return true
        }
        img.isTemplate = true
        return img
    }

    /// Top-left corner outline: sharp (radius 0) or rounded.
    static func corner(rounded: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            let path = NSBezierPath()
            let left: CGFloat = 3.5, bottom: CGFloat = 2.5, top: CGFloat = 12.5, right: CGFloat = 13.5
            path.move(to: CGPoint(x: left, y: bottom))
            if rounded {
                let r: CGFloat = 6
                path.line(to: CGPoint(x: left, y: top - r))
                path.curve(
                    to: CGPoint(x: left + r, y: top),
                    controlPoint1: CGPoint(x: left, y: top - r * 0.45),
                    controlPoint2: CGPoint(x: left + r * 0.45, y: top)
                )
            } else {
                path.line(to: CGPoint(x: left, y: top))
            }
            path.line(to: CGPoint(x: right, y: top))
            path.lineWidth = 1.6
            path.lineCapStyle = .round
            path.lineJoinStyle = .miter
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }
}

/// Hairline divider whose color follows the glass' light / dark rendition.
private final class SeparatorView: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = PixTheme.separator.cgColor }
}

@MainActor
private func makeSeparator(height: CGFloat) -> NSView {
    let sep = SeparatorView()
    sep.wantsLayer = true
    sep.layer?.cornerRadius = 0.5
    sep.translatesAutoresizingMaskIntoConstraints = false
    sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
    sep.heightAnchor.constraint(equalToConstant: height).isActive = true
    return sep
}

// MARK: - Style Sub-Bar

/// Secondary contextual style bar (stroke size, shape fill / corner, mosaic style, counter, colors).
public final class ToolbarSubBar: NSView {
    public var onSizeSelected: ((StrokeSizePreset) -> Void)?
    public var onColorSelected: ((NSColor) -> Void)?
    public var onMosaicStyleChanged: ((MosaicStyle) -> Void)?
    public var onFillToggled: ((Bool) -> Void)?
    public var onRectCornerToggled: ((Bool) -> Void)?
    public var onResetCounter: (() -> Void)?

    public private(set) var activeSize: StrokeSizePreset = .medium
    public private(set) var activeColor: NSColor = .systemRed
    public private(set) var activeMosaicStyle: MosaicStyle = .pixelate
    public private(set) var isFilledShape: Bool = false
    public private(set) var isRectRounded: Bool = false

    private let capsule = GlassCapsuleView(height: PixTheme.subBarHeight, inset: 3, spacing: PixTheme.groupSpacing)
    private var stack: NSStackView { capsule.stack }

    private var sizeButtons: [StrokeSizePreset: HUDButton] = [:]
    private var sizeTrack: SegmentTrackView!

    private var mosaicTrack: SegmentTrackView!
    private var pixelateBtn: HUDButton!
    private var blurBtn: HUDButton!

    private var fillTrack: SegmentTrackView!
    private var strokeOnlyBtn: HUDButton!
    private var filledBtn: HUDButton!

    private var cornerTrack: SegmentTrackView!
    private var sharpCornerBtn: HUDButton!
    private var roundCornerBtn: HUDButton!

    private let counterStack = NSStackView()
    private let counterBadge = CounterBadgeView()

    private let colorStack = NSStackView()
    private var colorButtons: [ColorSwatchButton] = []

    private var optionSeparator = NSView()
    private var colorSeparator = NSView()

    private var currentTool: ToolType = .rect

    private let palette: [(NSColor, String)] = [
        (NSColor(srgbRed: 1.0, green: 0.27, blue: 0.23, alpha: 1.0), "红色"),
        (NSColor(srgbRed: 1.0, green: 0.62, blue: 0.04, alpha: 1.0), "橙色"),
        (NSColor(srgbRed: 1.0, green: 0.84, blue: 0.04, alpha: 1.0), "黄色"),
        (NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1.0), "绿色"),
        (NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1.0), "蓝色"),
        (.white, "白色"),
        (NSColor(white: 0.14, alpha: 1.0), "深灰")
    ]

    public override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: PixTheme.subBarHeight))
        activeColor = palette[0].0
        isRectRounded = AppSettings.shared.rectAnnotationRounded
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    public override func viewDidUnhide() {
        super.viewDidUnhide()
        PixTheme.animateAppear(self)
    }

    private func setupUI() {
        wantsLayer = true
        layer?.masksToBounds = false
        addSubview(capsule)
        NSLayoutConstraint.activate([
            capsule.leadingAnchor.constraint(equalTo: leadingAnchor),
            capsule.topAnchor.constraint(equalTo: topAnchor)
        ])

        // 1. Stroke size segments
        var sizeViews: [HUDButton] = []
        for preset in StrokeSizePreset.allCases {
            let btn = makeSegment(image: nil, tip: sizeTooltip(preset), action: #selector(sizeClicked(_:)))
            btn.tag = preset.rawValue
            btn.isOn = (preset == activeSize)
            sizeButtons[preset] = btn
            sizeViews.append(btn)
        }
        sizeTrack = SegmentTrackView(sizeViews)
        stack.addArrangedSubview(sizeTrack)

        optionSeparator = makeSeparator(height: 16)
        stack.addArrangedSubview(optionSeparator)

        // 2a. Mosaic: pixelate vs gaussian blur
        pixelateBtn = makeSegment(symbol: "mosaic", tip: "像素马赛克", action: #selector(selectPixelate))
        blurBtn = makeSegment(symbol: "drop.halffull", tip: "高斯模糊", action: #selector(selectBlur))
        pixelateBtn.isOn = true
        mosaicTrack = SegmentTrackView([pixelateBtn, blurBtn])
        stack.addArrangedSubview(mosaicTrack)

        // 2b. Shape: outline vs semi-transparent fill
        strokeOnlyBtn = makeSegment(symbol: "square", tip: "仅描边", action: #selector(selectStrokeOnly))
        filledBtn = makeSegment(symbol: "square.fill", tip: "半透明填充", action: #selector(selectFilled))
        strokeOnlyBtn.isOn = true
        fillTrack = SegmentTrackView([strokeOnlyBtn, filledBtn])
        stack.addArrangedSubview(fillTrack)

        // 2c. Rect: sharp vs rounded corners
        sharpCornerBtn = makeSegment(image: ToolbarGlyphs.corner(rounded: false), tip: "矩形边角：直角", action: #selector(selectSharpCorner))
        roundCornerBtn = makeSegment(image: ToolbarGlyphs.corner(rounded: true), tip: "矩形边角：圆角", action: #selector(selectRoundCorner))
        cornerTrack = SegmentTrackView([sharpCornerBtn, roundCornerBtn])
        stack.addArrangedSubview(cornerTrack)
        syncCornerButtons()

        // 2d. Counter: next-number badge + reset
        let counterLabel = NSTextField(labelWithString: "下一个")
        counterLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        counterLabel.textColor = PixTheme.textSecondary
        counterBadge.color = activeColor
        counterBadge.toolTip = "下一个序号"
        let resetCounterBtn = HUDButton(
            symbol: "arrow.counterclockwise",
            toolTip: "序号重置为 1",
            style: .plain,
            size: PixTheme.segmentSize,
            pointSize: 12
        )
        resetCounterBtn.target = self
        resetCounterBtn.action = #selector(resetCounterClicked)
        counterStack.orientation = .horizontal
        counterStack.alignment = .centerY
        counterStack.spacing = 4
        counterStack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
        counterStack.addArrangedSubview(counterLabel)
        counterStack.addArrangedSubview(counterBadge)
        counterStack.addArrangedSubview(resetCounterBtn)
        stack.addArrangedSubview(counterStack)

        // 3. Colors
        colorSeparator = makeSeparator(height: 16)
        stack.addArrangedSubview(colorSeparator)

        colorStack.orientation = .horizontal
        colorStack.alignment = .centerY
        colorStack.spacing = 1
        for (index, (color, name)) in palette.enumerated() {
            let btn = ColorSwatchButton(color: color, name: name)
            btn.isSelectedColor = (index == 0)
            btn.target = self
            btn.action = #selector(colorClicked(_:))
            colorButtons.append(btn)
            colorStack.addArrangedSubview(btn)
        }
        stack.addArrangedSubview(colorStack)

        configure(for: .rect, nextCounter: 1)
    }

    private func makeSegment(symbol: String, tip: String, action: Selector) -> HUDButton {
        makeSegment(image: PixTheme.symbol(symbol, pointSize: 13), tip: tip, action: action)
    }

    private func makeSegment(image: NSImage?, tip: String, action: Selector) -> HUDButton {
        let btn = HUDButton(image: image, toolTip: tip, style: .segment, size: PixTheme.segmentSize)
        btn.target = self
        btn.action = action
        return btn
    }

    private func sizeTooltip(_ preset: StrokeSizePreset) -> String {
        switch preset {
        case .small: return "细 / 小"
        case .medium: return "中"
        case .large: return "粗 / 大"
        }
    }

    private func applySizeGlyphs(for tool: ToolType) {
        for (preset, btn) in sizeButtons {
            if tool == .text {
                let pt: CGFloat = preset == .small ? 9.5 : (preset == .medium ? 12.5 : 15.5)
                btn.image = ToolbarGlyphs.letter(pointSize: pt)
            } else {
                let d: CGFloat = preset == .small ? 4.0 : (preset == .medium ? 7.0 : 10.5)
                btn.image = ToolbarGlyphs.dot(diameter: d)
            }
        }
    }

    private func refitWidth() {
        layoutSubtreeIfNeeded()
        let fit = capsule.fittingSize
        setFrameSize(NSSize(width: ceil(fit.width), height: PixTheme.subBarHeight))
    }

    public func configure(for tool: ToolType, nextCounter: Int) {
        currentTool = tool
        let showMosaic = (tool == .mosaic)
        let showFill = tool.isShapeTool
        let showRectCorner = (tool == .rect)
        let showCounter = (tool == .counter)
        let showColor = tool.hasColorPicker

        applySizeGlyphs(for: tool)

        mosaicTrack.isHidden = !showMosaic
        fillTrack.isHidden = !showFill
        cornerTrack.isHidden = !showRectCorner
        counterStack.isHidden = !showCounter
        optionSeparator.isHidden = true // capsule tracks already read as separate groups

        if showFill {
            let isEllipse = (tool == .ellipse)
            strokeOnlyBtn.image = PixTheme.symbol(isEllipse ? "circle" : "square", pointSize: 13)
            filledBtn.image = PixTheme.symbol(isEllipse ? "circle.fill" : "square.fill", pointSize: 13)
            strokeOnlyBtn.isOn = !isFilledShape
            filledBtn.isOn = isFilledShape
        }

        if showRectCorner {
            isRectRounded = AppSettings.shared.rectAnnotationRounded
            syncCornerButtons()
        }

        counterBadge.number = nextCounter
        counterBadge.color = activeColor

        colorSeparator.isHidden = !showColor
        colorStack.isHidden = !showColor

        // Balanced trailing padding: swatches need a little more breathing room than a segmented track
        let trailing: CGFloat = showColor ? 8 : 3
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 3, bottom: 3, right: trailing)

        refitWidth()
    }

    public func updateCounterPreview(_ nextNumber: Int) {
        counterBadge.number = nextNumber
    }

    public func syncFromAnnotation(_ annot: Annotation) {
        if let idx = colorButtons.firstIndex(where: { colorsClose($0.swatchColor, annot.color) }) {
            activeColor = colorButtons[idx].swatchColor
            for (i, b) in colorButtons.enumerated() { b.isSelectedColor = (i == idx) }
            counterBadge.color = activeColor
        }

        if let preset = nearestPreset(for: annot) {
            activeSize = preset
            for (p, b) in sizeButtons { b.isOn = (p == preset) }
        }

        isFilledShape = annot.isFilled
        strokeOnlyBtn.isOn = !isFilledShape
        filledBtn.isOn = isFilledShape

        isRectRounded = annot.cornerRadius > 0.5
        syncCornerButtons()

        activeMosaicStyle = annot.mosaicStyle
        pixelateBtn.isOn = (activeMosaicStyle == .pixelate)
        blurBtn.isOn = (activeMosaicStyle == .blur)
    }

    private func nearestPreset(for annot: Annotation) -> StrokeSizePreset? {
        let value: (StrokeSizePreset) -> CGFloat
        let current: CGFloat
        switch annot.type {
        case .text: value = { $0.fontSize }; current = annot.fontSize
        case .highlighter: value = { $0.highlighterWidth }; current = annot.lineWidth
        case .mosaic: value = { $0.mosaicWidth }; current = annot.lineWidth
        case .counter: value = { $0.counterRadius }; current = annot.lineWidth
        case .none: return nil
        default: value = { $0.strokeWidth }; current = annot.lineWidth
        }
        return StrokeSizePreset.allCases.min(by: { abs(value($0) - current) < abs(value($1) - current) })
    }

    private func syncCornerButtons() {
        sharpCornerBtn.isOn = !isRectRounded
        roundCornerBtn.isOn = isRectRounded
    }

    private func colorsClose(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let c1 = a.usingColorSpace(.sRGB), let c2 = b.usingColorSpace(.sRGB) else { return a == b }
        return abs(c1.redComponent - c2.redComponent) < 0.08 &&
            abs(c1.greenComponent - c2.greenComponent) < 0.08 &&
            abs(c1.blueComponent - c2.blueComponent) < 0.08
    }

    // MARK: Actions

    @objc private func sizeClicked(_ sender: HUDButton) {
        guard let preset = StrokeSizePreset(rawValue: sender.tag) else { return }
        activeSize = preset
        for (p, b) in sizeButtons { b.isOn = (p == preset) }
        onSizeSelected?(activeSize)
    }

    @objc private func colorClicked(_ sender: ColorSwatchButton) {
        activeColor = sender.swatchColor
        for btn in colorButtons { btn.isSelectedColor = (btn === sender) }
        counterBadge.color = activeColor
        onColorSelected?(activeColor)
    }

    @objc private func selectPixelate() {
        activeMosaicStyle = .pixelate
        pixelateBtn.isOn = true
        blurBtn.isOn = false
        onMosaicStyleChanged?(.pixelate)
    }

    @objc private func selectBlur() {
        activeMosaicStyle = .blur
        pixelateBtn.isOn = false
        blurBtn.isOn = true
        onMosaicStyleChanged?(.blur)
    }

    @objc private func selectStrokeOnly() { setFilled(false) }
    @objc private func selectFilled() { setFilled(true) }

    private func setFilled(_ filled: Bool) {
        isFilledShape = filled
        strokeOnlyBtn.isOn = !filled
        filledBtn.isOn = filled
        onFillToggled?(filled)
    }

    @objc private func selectSharpCorner() { setRectRounded(false) }
    @objc private func selectRoundCorner() { setRectRounded(true) }

    private func setRectRounded(_ rounded: Bool) {
        isRectRounded = rounded
        syncCornerButtons()
        onRectCornerToggled?(rounded)
    }

    @objc private func resetCounterClicked() {
        onResetCounter?()
    }
}

// MARK: - Main Toolbar

public final class ToolbarView: NSView {
    public var onToolSelected: ((ToolType) -> Void)?
    public var onColorSelected: ((NSColor) -> Void)?
    public var onSizeSelected: ((StrokeSizePreset) -> Void)?
    public var onMosaicStyleChanged: ((MosaicStyle) -> Void)?
    public var onFillToggled: ((Bool) -> Void)?
    public var onRectCornerToggled: ((Bool) -> Void)?
    public var onResetCounter: (() -> Void)?
    public var onUndo: (() -> Void)?
    public var onRedo: (() -> Void)?
    public var onPin: (() -> Void)?
    public var onOCR: (() -> Void)?
    public var onSave: (() -> Void)?
    public var onCopy: (() -> Void)?
    public var onCancel: (() -> Void)?

    public private(set) var activeTool: ToolType = .none
    public let subBar = ToolbarSubBar()

    public var activeColor: NSColor { subBar.activeColor }
    public var activeSize: StrokeSizePreset { subBar.activeSize }
    public var activeMosaicStyle: MosaicStyle { subBar.activeMosaicStyle }
    public var isFilledShape: Bool { subBar.isFilledShape }
    public var isRectRounded: Bool { subBar.isRectRounded }

    private let row = NSStackView()
    private var toolButtons: [ToolType: HUDButton] = [:]
    private var undoBtn: HUDButton!
    private var redoBtn: HUDButton!

    public override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 520, height: PixTheme.barHeight))
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    public override func viewDidUnhide() {
        super.viewDidUnhide()
        PixTheme.animateAppear(self)
    }

    private func makeCapsule() -> GlassCapsuleView {
        GlassCapsuleView(height: PixTheme.barHeight, inset: PixTheme.barInset, spacing: 2)
    }

    private func setupUI() {
        wantsLayer = true
        layer?.masksToBounds = false

        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = PixTheme.capsuleGap
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // 1. Annotation tools capsule
        let toolsCapsule = makeCapsule()
        let tools: [(ToolType, String, String)] = [
            (.rect, "square", "矩形 (1 · 按住 Shift 正方形)"),
            (.ellipse, "circle", "椭圆 (2 · 按住 Shift 正圆)"),
            (.arrow, "arrow.up.right", "箭头 (3 · 按住 Shift 45° 对齐)"),
            (.pen, "scribble", "画笔 (4)"),
            (.highlighter, "highlighter", "荧光笔 (5 · 按住 Shift 画直线)"),
            (.mosaic, "mosaic", "马赛克 / 高斯模糊 (6)"),
            (.text, "textformat", "文字 (7)"),
            (.counter, "1.circle", "序号 ①②③ (8)")
        ]
        for (tool, icon, tip) in tools {
            let btn = HUDButton(symbol: icon, toolTip: tip, style: .tool)
            btn.target = self
            btn.action = #selector(toolClicked(_:))
            toolButtons[tool] = btn
            toolsCapsule.stack.addArrangedSubview(btn)
        }
        row.addArrangedSubview(toolsCapsule)

        // 2. History capsule
        let historyCapsule = makeCapsule()
        undoBtn = addPlainButton("arrow.uturn.backward", "撤销 (⌘Z)", #selector(undoClicked), to: historyCapsule)
        redoBtn = addPlainButton("arrow.uturn.forward", "重做 (⌘⇧Z)", #selector(redoClicked), to: historyCapsule)
        undoBtn.isEnabled = false
        redoBtn.isEnabled = false
        row.addArrangedSubview(historyCapsule)

        // 3. Output capsule
        let outputCapsule = makeCapsule()
        addPlainButton("pin", "贴图置顶 (T / ⌘P)", #selector(pinClicked), to: outputCapsule)
        addPlainButton("text.viewfinder", "识别文字 / 二维码 (OCR)", #selector(ocrClicked), to: outputCapsule)
        addPlainButton("square.and.arrow.down", "另存为 (⌘⇧S) · ⌘S 快速保存", #selector(saveClicked), to: outputCapsule)
        row.addArrangedSubview(outputCapsule)

        // 4. Exit capsule: cancel + primary Done
        let exitCapsule = makeCapsule()
        let cancelBtn = addPlainButton("xmark", "取消 (Esc)", #selector(cancelClicked), to: exitCapsule)
        cancelBtn.hoverAccent = PixTheme.destructive
        let doneBtn = HUDButton(
            symbol: "checkmark",
            toolTip: "完成并复制 (↵ / ⌘C / 双击)",
            style: .primary,
            size: PixTheme.buttonSize,
            pointSize: PixTheme.iconPointSize,
            weight: .semibold
        )
        doneBtn.target = self
        doneBtn.action = #selector(copyClicked)
        exitCapsule.stack.addArrangedSubview(doneBtn)
        row.addArrangedSubview(exitCapsule)

        // Wire subBar callbacks
        subBar.onSizeSelected = { [weak self] preset in self?.onSizeSelected?(preset) }
        subBar.onColorSelected = { [weak self] color in self?.onColorSelected?(color) }
        subBar.onMosaicStyleChanged = { [weak self] style in self?.onMosaicStyleChanged?(style) }
        subBar.onFillToggled = { [weak self] filled in self?.onFillToggled?(filled) }
        subBar.onRectCornerToggled = { [weak self] rounded in self?.onRectCornerToggled?(rounded) }
        subBar.onResetCounter = { [weak self] in self?.onResetCounter?() }

        layoutSubtreeIfNeeded()
        let fit = row.fittingSize
        setFrameSize(NSSize(width: ceil(fit.width), height: PixTheme.barHeight))
    }

    @discardableResult
    private func addPlainButton(_ symbol: String, _ tip: String, _ action: Selector, to capsule: GlassCapsuleView) -> HUDButton {
        let btn = HUDButton(symbol: symbol, toolTip: tip, style: .plain)
        btn.target = self
        btn.action = action
        capsule.stack.addArrangedSubview(btn)
        return btn
    }

    public func setActiveTool(_ tool: ToolType, notify: Bool = true) {
        activeTool = tool
        for (t, b) in toolButtons {
            b.isOn = (t == tool)
        }
        if notify {
            onToolSelected?(activeTool)
        }
    }

    public func setUndoRedoState(canUndo: Bool, canRedo: Bool) {
        undoBtn.isEnabled = canUndo
        redoBtn.isEnabled = canRedo
    }

    @objc private func toolClicked(_ sender: HUDButton) {
        for (tool, btn) in toolButtons where btn === sender {
            setActiveTool(activeTool == tool ? .none : tool, notify: true)
            break
        }
    }

    @objc private func undoClicked() { onUndo?() }
    @objc private func redoClicked() { onRedo?() }
    @objc private func pinClicked() { onPin?() }
    @objc private func ocrClicked() { onOCR?() }
    @objc private func saveClicked() { onSave?() }
    @objc private func copyClicked() { onCopy?() }
    @objc private func cancelClicked() { onCancel?() }
}
