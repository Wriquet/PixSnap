import Cocoa
import Carbon

// MARK: - Glass Styled Control Helpers

@MainActor
private func applyGlassButtonStyle(_ button: NSButton, capsule: Bool = true) {
    if #available(macOS 26.0, *) {
        button.bezelStyle = .glass
        if capsule {
            button.borderShape = .capsule
        }
    } else {
        button.bezelStyle = .rounded
    }
}

@MainActor
private func makeGlassButton(
    title: String,
    symbol: String? = nil,
    controlSize: NSControl.ControlSize = .regular,
    target: AnyObject?,
    action: Selector
) -> NSButton {
    let btn = NSButton(title: title, target: target, action: action)
    applyGlassButtonStyle(btn, capsule: true)
    btn.controlSize = controlSize
    btn.font = NSFont.systemFont(ofSize: controlSize == .small ? 11.5 : 12.5, weight: .medium)
    if let symbol {
        let pt: CGFloat = controlSize == .small ? 11 : 12
        let cfg = NSImage.SymbolConfiguration(pointSize: pt, weight: .medium)
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
            img.isTemplate = true
            btn.image = img
            btn.imagePosition = .imageLeading
        }
    }
    return btn
}

@MainActor
private func applyCapsuleSegmentStyle(_ seg: NSSegmentedControl) {
    seg.segmentStyle = .rounded
    if #available(macOS 26.0, *) {
        seg.borderShape = .capsule
    }
}

@MainActor
private func applyGlassPopupStyle(_ popup: NSPopUpButton) {
    if #available(macOS 26.0, *) {
        popup.bezelStyle = .glass
        popup.borderShape = .capsule
    }
    popup.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
}

// MARK: - Translucent Grouped Card

private final class SettingsCardView: NSView {
    let stack = NSStackView()

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layer?.backgroundColor = (isDark
            ? NSColor.white.withAlphaComponent(0.065)
            : NSColor.white.withAlphaComponent(0.62)).cgColor
        layer?.borderColor = (isDark
            ? NSColor.white.withAlphaComponent(0.11)
            : NSColor.black.withAlphaComponent(0.07)).cgColor
    }

    init(rows: [NSView]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        for (index, row) in rows.enumerated() {
            row.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

            if index < rows.count - 1 {
                let dividerWrap = NSView()
                dividerWrap.translatesAutoresizingMaskIntoConstraints = false
                let divider = CardDividerView()
                dividerWrap.addSubview(divider)
                NSLayoutConstraint.activate([
                    dividerWrap.heightAnchor.constraint(equalToConstant: 1),
                    divider.leadingAnchor.constraint(equalTo: dividerWrap.leadingAnchor, constant: 14),
                    divider.trailingAnchor.constraint(equalTo: dividerWrap.trailingAnchor, constant: -14),
                    divider.topAnchor.constraint(equalTo: dividerWrap.topAnchor),
                    divider.bottomAnchor.constraint(equalTo: dividerWrap.bottomAnchor)
                ])
                stack.addArrangedSubview(dividerWrap)
                dividerWrap.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

private final class CardDividerView: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layer?.backgroundColor = (isDark
            ? NSColor.white.withAlphaComponent(0.09)
            : NSColor.black.withAlphaComponent(0.07)).cgColor
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Liquid Glass Sliding Capsule Tab Bar

private final class GlassTabItemView: NSView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    var isHighlightedTab: Bool = false {
        didSet { if oldValue != isHighlightedTab { refresh() } }
    }
    var isHoveredTab: Bool = false {
        didSet { if oldValue != isHoveredTab { refresh() } }
    }

    override var mouseDownCanMoveWindow: Bool { false }

    init(title: String, symbol: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let cfg = NSImage.SymbolConfiguration(pointSize: 12.5, weight: .medium)
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?.withSymbolConfiguration(cfg) {
            img.isTemplate = true
            iconView.image = img
        }
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        label.stringValue = title
        label.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        label.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [iconView, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    // Pass mouse hit-testing through to parent GlassTabBar for unified click & drag scrubbing
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let textColor: NSColor
        let iconColor: NSColor

        if isHighlightedTab {
            textColor = isDark ? .white : NSColor(white: 0.08, alpha: 1.0)
            iconColor = isDark ? .white : PixTheme.accent
        } else if isHoveredTab {
            textColor = isDark ? NSColor.white.withAlphaComponent(0.92) : NSColor(white: 0.14, alpha: 1.0)
            iconColor = textColor
        } else {
            textColor = isDark ? NSColor.white.withAlphaComponent(0.68) : NSColor(white: 0.26, alpha: 0.86)
            iconColor = textColor
        }

        label.font = NSFont.systemFont(ofSize: 12.5, weight: isHighlightedTab ? .semibold : .medium)
        label.textColor = textColor
        iconView.contentTintColor = iconColor
    }
}

/// Elevated glass capsule thumb that slides smoothly between tabs (both on click and interactive press-drag).
private final class SlidingGlassThumbView: NSView {
    private let pillLayer = CALayer()
    private var isLifted = false

    override var mouseDownCanMoveWindow: Bool { false }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false

        pillLayer.cornerRadius = 15
        pillLayer.cornerCurve = .continuous
        pillLayer.borderWidth = 0.75
        layer?.addSublayer(pillLayer)
        refreshAppearance(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pillLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        pillLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        pillLayer.cornerRadius = bounds.height / 2
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance(animated: false)
    }

    func setLifted(_ lifted: Bool, animated: Bool) {
        guard isLifted != lifted else { return }
        isLifted = lifted
        refreshAppearance(animated: animated)

        let targetTransform = lifted
            ? CATransform3DMakeScale(1.045, 1.08, 1.0)
            : CATransform3DIdentity

        if animated {
            let spring = CASpringAnimation(keyPath: "transform")
            spring.fromValue = pillLayer.presentation()?.transform ?? pillLayer.transform
            spring.toValue = targetTransform
            spring.stiffness = 420
            spring.damping = 26
            spring.mass = 0.8
            spring.duration = spring.settlingDuration
            pillLayer.transform = targetTransform
            pillLayer.add(spring, forKey: "liftScale")
        } else {
            pillLayer.removeAnimation(forKey: "liftScale")
            pillLayer.transform = targetTransform
        }
    }

    private func refreshAppearance(animated: Bool) {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua

        let fill: NSColor
        let border: NSColor
        let shadowOpacity: Float
        let shadowRadius: CGFloat
        let shadowOffsetY: CGFloat

        if isLifted {
            // Slightly more translucent & luminous while scrubbing, like a lifted Liquid Glass lens
            fill = isDark
                ? NSColor.white.withAlphaComponent(0.28)
                : NSColor.white.withAlphaComponent(0.72)
            border = isDark
                ? NSColor.white.withAlphaComponent(0.45)
                : NSColor.white.withAlphaComponent(0.98)
            shadowOpacity = isDark ? 0.38 : 0.18
            shadowRadius = 9
            shadowOffsetY = -3
        } else {
            fill = isDark
                ? NSColor.white.withAlphaComponent(0.22)
                : NSColor.white.withAlphaComponent(0.90)
            border = isDark
                ? NSColor.white.withAlphaComponent(0.24)
                : NSColor.white.withAlphaComponent(0.95)
            shadowOpacity = isDark ? 0.24 : 0.12
            shadowRadius = 4
            shadowOffsetY = -1
        }

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.16)
        pillLayer.backgroundColor = fill.cgColor
        pillLayer.borderColor = border.cgColor
        pillLayer.shadowColor = NSColor.black.cgColor
        pillLayer.shadowOpacity = shadowOpacity
        pillLayer.shadowRadius = shadowRadius
        pillLayer.shadowOffset = CGSize(width: 0, height: shadowOffsetY)
        CATransaction.commit()
    }
}

final class GlassTabBar: NSView {
    var onSelect: ((Int) -> Void)?

    private let thumbView = SlidingGlassThumbView()
    private let itemsStack = NSStackView()
    private var itemViews: [GlassTabItemView] = []
    private var hostView: NSView!

    private(set) var selectedIndex: Int = 0
    private var hoveredIndex: Int?
    private var isDraggingThumb: Bool = false
    private var hasPlacedInitialThumb: Bool = false

    override var mouseDownCanMoveWindow: Bool { false }

    init(items: [(title: String, symbol: String)]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = false

        let height: CGFloat = 38
        let radius: CGFloat = height / 2

        let backdrop: NSView
        let host: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = radius
            if #available(macOS 27.0, *) {
                glass.effectIsInteractive = true
            }
            let content = NSView()
            content.translatesAutoresizingMaskIntoConstraints = false
            glass.contentView = content
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
                content.topAnchor.constraint(equalTo: glass.topAnchor),
                content.bottomAnchor.constraint(equalTo: glass.bottomAnchor)
            ])
            backdrop = glass
            host = content
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = radius
            effect.layer?.cornerCurve = .continuous
            effect.layer?.masksToBounds = true
            effect.layer?.borderWidth = 1
            effect.layer?.borderColor = NSColor.separatorColor.cgColor
            backdrop = effect
            host = self
        }
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)
        self.hostView = host

        // Sliding glass capsule sits directly behind the tab labels inside the glass bar
        host.addSubview(thumbView)

        itemsStack.orientation = .horizontal
        itemsStack.alignment = .centerY
        itemsStack.spacing = 4
        itemsStack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        itemsStack.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(itemsStack)

        for item in items {
            let v = GlassTabItemView(title: item.title, symbol: item.symbol)
            itemViews.append(v)
            itemsStack.addArrangedSubview(v)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: height),
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            itemsStack.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            itemsStack.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            itemsStack.centerYAnchor.constraint(equalTo: host.centerYAnchor)
        ])

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))

        updateHighlights(activeIndex: 0)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        if !isDraggingThumb, selectedIndex < itemViews.count {
            let target = itemFrame(at: selectedIndex)
            if target.width > 0 {
                if !hasPlacedInitialThumb {
                    thumbView.frame = target
                    hasPlacedInitialThumb = true
                } else if thumbView.layer?.animationKeys()?.isEmpty ?? true {
                    thumbView.frame = target
                }
            }
        }
    }

    func setSelected(index: Int, animated: Bool = false) {
        guard index >= 0 && index < itemViews.count else { return }
        selectedIndex = index
        updateHighlights(activeIndex: index)
        layoutSubtreeIfNeeded()
        let target = itemFrame(at: index)
        guard target.width > 0 else { return }
        hasPlacedInitialThumb = true
        moveThumb(to: target, animated: animated)
    }

    private func itemFrame(at index: Int) -> CGRect {
        let item = itemViews[index]
        return hostView.convert(item.bounds, from: item)
    }

    private func moveThumb(to target: CGRect, animated: Bool) {
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
                ctx.allowsImplicitAnimation = true
                thumbView.animator().frame = target
            }
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            thumbView.frame = target
            CATransaction.commit()
        }
    }

    private func updateHighlights(activeIndex: Int) {
        for (i, view) in itemViews.enumerated() {
            view.isHighlightedTab = (i == activeIndex)
            view.isHoveredTab = (!isDraggingThumb && hoveredIndex == i)
        }
    }

    private func tabIndex(at pointInHost: CGPoint) -> Int? {
        for i in itemViews.indices {
            if itemFrame(at: i).contains(pointInHost) {
                return i
            }
        }
        return nil
    }

    private func nearestTabIndex(forCenterX x: CGFloat) -> Int {
        var best = 0
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in itemViews.indices {
            let d = abs(itemFrame(at: i).midX - x)
            if d < bestDist {
                bestDist = d
                best = i
            }
        }
        return best
    }

    /// Interpolates the capsule width smoothly as its center scrubs between two neighboring tabs.
    private func interpolatedThumbFrame(forCenterX rawCenterX: CGFloat) -> CGRect {
        let frames = itemViews.indices.map { itemFrame(at: $0) }
        guard let first = frames.first, let last = frames.last else { return .zero }

        let minCenter = first.midX
        let maxCenter = last.midX

        // Subtle rubber-band resistance past the left/right edges
        let centerX: CGFloat
        if rawCenterX < minCenter {
            let over = minCenter - rawCenterX
            centerX = minCenter - min(5, over * 0.22)
        } else if rawCenterX > maxCenter {
            let over = rawCenterX - maxCenter
            centerX = maxCenter + min(5, over * 0.22)
        } else {
            centerX = rawCenterX
        }

        let clampedForWidth = max(minCenter, min(maxCenter, centerX))
        var width = first.width
        for i in 0..<(frames.count - 1) {
            let a = frames[i]
            let b = frames[i + 1]
            if clampedForWidth >= a.midX && clampedForWidth <= b.midX {
                let span = max(1, b.midX - a.midX)
                let t = (clampedForWidth - a.midX) / span
                width = a.width + (b.width - a.width) * t
                break
            } else if clampedForWidth >= b.midX {
                width = b.width
            }
        }

        return CGRect(x: centerX - width / 2, y: first.minY, width: width, height: first.height)
    }

    // MARK: Mouse Hover & Press-Drag Scrubbing

    override func mouseMoved(with event: NSEvent) {
        let loc = hostView.convert(event.locationInWindow, from: nil)
        let idx = tabIndex(at: loc)
        if idx != hoveredIndex {
            hoveredIndex = idx
            updateHighlights(activeIndex: selectedIndex)
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredIndex != nil {
            hoveredIndex = nil
            updateHighlights(activeIndex: selectedIndex)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        layoutSubtreeIfNeeded()
        let startLoc = hostView.convert(event.locationInWindow, from: nil)
        let downIndex = tabIndex(at: startLoc) ?? nearestTabIndex(forCenterX: startLoc.x)

        isDraggingThumb = true
        hoveredIndex = nil
        thumbView.setLifted(true, animated: true)
        CATransaction.flush()

        // If user grabbed the active capsule, anchor to grab point so it doesn't jump;
        // if user pressed another tab, center under pointer once dragging starts.
        let grabOffset: CGFloat = (downIndex == selectedIndex) ? (startLoc.x - thumbView.frame.midX) : 0
        var previewIndex = selectedIndex
        var didDrag = false
        var lastLoc = startLoc

        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            lastLoc = hostView.convert(next.locationInWindow, from: nil)

            if next.type == .leftMouseDragged {
                if !didDrag && hypot(lastLoc.x - startLoc.x, lastLoc.y - startLoc.y) >= 3 {
                    didDrag = true
                }
                if didDrag {
                    let targetFrame = interpolatedThumbFrame(forCenterX: lastLoc.x - grabOffset)
                    moveThumb(to: targetFrame, animated: false)

                    let nearest = nearestTabIndex(forCenterX: targetFrame.midX)
                    if nearest != previewIndex {
                        previewIndex = nearest
                        updateHighlights(activeIndex: nearest)
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                }
            } else if next.type == .leftMouseUp {
                break
            }
        }

        let finalIndex: Int
        if didDrag {
            finalIndex = previewIndex
        } else {
            finalIndex = tabIndex(at: lastLoc) ?? downIndex
        }

        isDraggingThumb = false
        thumbView.setLifted(false, animated: true)
        selectedIndex = finalIndex
        updateHighlights(activeIndex: finalIndex)
        moveThumb(to: itemFrame(at: finalIndex), animated: true)
        onSelect?(finalIndex)
    }
}

// MARK: - Shortcut Recorder Button

final class ShortcutRecordButton: NSButton {
    let actionType: HotKeyAction
    private(set) var isRecording: Bool = false {
        didSet {
            updateButtonTitle()
            needsDisplay = true
        }
    }

    var onWillStartRecording: ((ShortcutRecordButton) -> Void)?
    var onShortcutRecorded: ((HotKeyAction, UInt32, UInt32, String) -> Void)?
    var onInvalidShortcut: ((String) -> Void)?
    var onShortcutCleared: ((HotKeyAction) -> Void)?

    private var keyMonitor: Any?
    private var clickOutsideMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    init(action: HotKeyAction) {
        self.actionType = action
        super.init(frame: NSRect(x: 0, y: 0, width: 196, height: 28))
        applyGlassButtonStyle(self, capsule: true)
        self.wantsLayer = true
        self.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        updateButtonTitle()
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateButtonTitle() {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        if isRecording {
            bezelColor = .controlAccentColor
            attributedTitle = NSAttributedString(
                string: "按下快捷键 (Esc 取消)…",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: NSColor.white,
                    .paragraphStyle: para
                ]
            )
        } else {
            bezelColor = nil
            title = HotKeyManager.shared.displayString(for: actionType)
            contentTintColor = nil
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        onWillStartRecording?(self)

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)

        HotKeyManager.shared.suspendForRecording()
        isRecording = true

        // Local keyDown monitor captures ALL shortcuts (including ⌘ combos that AppKit
        // otherwise routes to performKeyEquivalent / menu bar instead of keyDown!)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }
            self.handleRecordedKeyEvent(event)
            return nil
        }

        clickOutsideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            if event.window === self.window {
                let loc = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(loc) {
                    return event
                }
            }
            self.stopRecording(resumeHotKeys: true)
            return event
        }
    }

    func stopRecording(resumeHotKeys: Bool = true) {
        let wasRecording = isRecording
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
        if let m = clickOutsideMonitor {
            NSEvent.removeMonitor(m)
            clickOutsideMonitor = nil
        }
        isRecording = false
        if wasRecording && resumeHotKeys {
            HotKeyManager.shared.resumeAfterRecording()
        }
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording(resumeHotKeys: true)
        } else {
            startRecording()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        handleRecordedKeyEvent(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        handleRecordedKeyEvent(event)
    }

    func handleRecordedKeyEvent(_ event: NSEvent) {
        guard isRecording else { return }

        let keyCode = event.keyCode
        if keyCode == 53 { // Esc cancels
            stopRecording(resumeHotKeys: true)
            return
        }

        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])

        // Backspace/Delete with no modifiers clears optional shortcuts
        if (keyCode == 51 || keyCode == 117) && flags.isEmpty && actionType != .capture {
            stopRecording(resumeHotKeys: false)
            onShortcutCleared?(actionType)
            HotKeyManager.shared.resumeAfterRecording()
            return
        }

        guard HotKeyManager.isValidGlobalShortcut(keyCode: keyCode, modifiers: flags) else {
            onInvalidShortcut?("请包含 ⌘ / ⌥ / ⌃ 修饰键，或使用 F1~F12 功能键，避免影响日常打字")
            return
        }

        var carbonMods: UInt32 = 0
        if flags.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        if flags.contains(.option) { carbonMods |= UInt32(optionKey) }
        if flags.contains(.control) { carbonMods |= UInt32(controlKey) }

        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }

        parts.append(Self.formatKeyName(keyCode: keyCode, characters: event.charactersIgnoringModifiers))
        let displayStr = parts.joined(separator: " + ")

        stopRecording(resumeHotKeys: false)
        onShortcutRecorded?(actionType, UInt32(keyCode), carbonMods, displayStr)
        HotKeyManager.shared.resumeAfterRecording()
    }

    static func formatKeyName(keyCode: UInt16, characters: String?) -> String {
        // Explicit ANSI virtual keyCode map works reliably even when Chinese Pinyin IME is active
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "Return"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            if let char = characters?.uppercased(), !char.isEmpty {
                return char
            }
            return "Key(\(keyCode))"
        }
    }
}

// MARK: - Preferences Window

public final class PreferencesWindow: NSWindow, NSWindowDelegate {
    public var onPinAppearanceSettingsChanged: (() -> Void)?

    private static let windowWidth: CGFloat = 560
    private static let headerHeight: CGFloat = 88

    private var tabBar: GlassTabBar!
    private let pageHost = NSView()
    private var pages: [NSView] = []
    private var selectedTabIndex: Int = 0

    private var recorderButtons: [HotKeyAction: ShortcutRecordButton] = [:]
    private let shortcutStatusRow = NSStackView()
    private let shortcutStatusIcon = NSImageView()
    private let shortcutStatusLabel = NSTextField(labelWithString: "")

    // General controls
    private let launchAtLoginSwitch = NSSwitch()
    private let soundSwitch = NSSwitch()
    private let autoCopyOnSaveSwitch = NSSwitch()
    private let saveDirLabel = NSTextField(labelWithString: "")
    private let formatPopup = NSPopUpButton()

    // Capture & Pin controls
    private let magnifierSwitch = NSSwitch()
    private let windowDetectSwitch = NSSwitch()
    private let colorFormatPopup = NSPopUpButton()
    private let pinAnchorPopup = NSPopUpButton()
    private let pinBorderSwitch = NSSwitch()
    private let pinSpacesSwitch = NSSwitch()

    // Corner customization controls (Selection, Rect Annotation, Pin Border)
    private let selectionCornerSeg = NSSegmentedControl(labels: ["直角", "圆角"], trackingMode: .selectOne, target: nil, action: nil)
    private let selectionRadiusSlider = NSSlider(value: 8, minValue: 2, maxValue: 24, target: nil, action: nil)
    private let selectionRadiusLabel = NSTextField(labelWithString: "直角")

    private let rectCornerSeg = NSSegmentedControl(labels: ["直角", "圆角"], trackingMode: .selectOne, target: nil, action: nil)
    private let rectRadiusSlider = NSSlider(value: 6, minValue: 2, maxValue: 20, target: nil, action: nil)
    private let rectRadiusLabel = NSTextField(labelWithString: "直角")

    private let pinCornerSeg = NSSegmentedControl(labels: ["直角", "圆角"], trackingMode: .selectOne, target: nil, action: nil)
    private let pinRadiusSlider = NSSlider(value: 8, minValue: 2, maxValue: 24, target: nil, action: nil)
    private let pinRadiusLabel = NSTextField(labelWithString: "直角")

    // Toolbar Liquid Glass opacity
    private let glassOpacitySlider = NSSlider(value: 60, minValue: 20, maxValue: 100, target: nil, action: nil)
    private let glassOpacityLabel = NSTextField(labelWithString: "60%")

    public init() {
        let frame = NSRect(x: 0, y: 0, width: Self.windowWidth, height: 420)
        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.title = "PixSnap 偏好设置"
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.isOpaque = false
        self.backgroundColor = .clear
        self.isReleasedWhenClosed = false
        self.level = .floating
        self.delegate = self

        setupUI()
        refreshControlStates()
        selectTab(index: 0, animated: false)
        self.center()
    }

    public func windowWillClose(_ notification: Notification) {
        stopAllShortcutRecording(resumeHotKeys: true)
    }

    public func windowDidResignKey(_ notification: Notification) {
        stopAllShortcutRecording(resumeHotKeys: true)
    }

    private func stopAllShortcutRecording(except active: ShortcutRecordButton? = nil, resumeHotKeys: Bool = true) {
        for btn in recorderButtons.values where btn !== active && btn.isRecording {
            btn.stopRecording(resumeHotKeys: resumeHotKeys)
        }
    }

    public func selectTab(index: Int, animated: Bool = true) {
        showTab(index: index, animated: animated, syncTabBar: true)
    }

    private func showTab(index: Int, animated: Bool, syncTabBar: Bool) {
        guard index >= 0 && index < pages.count else { return }
        if index != selectedTabIndex {
            stopAllShortcutRecording(resumeHotKeys: true)
        }
        selectedTabIndex = index
        if syncTabBar {
            tabBar.setSelected(index: index, animated: animated)
        }

        for (i, page) in pages.enumerated() {
            page.isHidden = (i != index)
        }

        let activePage = pages[index]
        activePage.layoutSubtreeIfNeeded()
        let contentHeight = ceil(activePage.fittingSize.height)
        let targetHeight = Self.headerHeight + contentHeight + 18

        var newFrame = frame
        let delta = targetHeight - newFrame.height
        newFrame.origin.y -= delta
        newFrame.size.height = targetHeight
        newFrame.size.width = Self.windowWidth
        setFrame(newFrame, display: true, animate: animated)
    }

    public func refreshControlStates() {
        let s = AppSettings.shared
        launchAtLoginSwitch.state = s.isLaunchAtLoginEnabled ? .on : .off
        soundSwitch.state = s.playCaptureSound ? .on : .off
        autoCopyOnSaveSwitch.state = s.autoCopyOnSave ? .on : .off
        saveDirLabel.stringValue = s.saveDirectoryURL.path
        formatPopup.selectItem(at: SaveImageFormat.allCases.firstIndex(of: s.saveFormat) ?? 0)

        magnifierSwitch.state = s.showMagnifier ? .on : .off
        windowDetectSwitch.state = s.enableWindowDetection ? .on : .off
        colorFormatPopup.selectItem(at: ColorCopyFormat.allCases.firstIndex(of: s.colorCopyFormat) ?? 0)
        pinAnchorPopup.selectItem(at: PinZoomAnchorMode.allCases.firstIndex(of: s.pinZoomAnchorMode) ?? 0)
        pinBorderSwitch.state = s.pinShowBorder ? .on : .off
        pinSpacesSwitch.state = s.pinStayAcrossSpaces ? .on : .off

        selectionCornerSeg.selectedSegment = s.selectionUseRoundedCorners ? 1 : 0
        selectionRadiusSlider.doubleValue = Double(s.selectionCornerRadius)
        selectionRadiusSlider.isEnabled = s.selectionUseRoundedCorners
        selectionRadiusLabel.stringValue = s.selectionUseRoundedCorners ? "\(Int(round(s.selectionCornerRadius))) px" : "直角"

        rectCornerSeg.selectedSegment = s.rectAnnotationRounded ? 1 : 0
        rectRadiusSlider.doubleValue = Double(s.rectAnnotationCornerRadius)
        rectRadiusSlider.isEnabled = s.rectAnnotationRounded
        rectRadiusLabel.stringValue = s.rectAnnotationRounded ? "\(Int(round(s.rectAnnotationCornerRadius))) px" : "直角"

        pinCornerSeg.selectedSegment = s.pinUseRoundedCorners ? 1 : 0
        pinRadiusSlider.doubleValue = Double(s.pinCornerRadius)
        pinRadiusSlider.isEnabled = s.pinUseRoundedCorners
        pinRadiusLabel.stringValue = s.pinUseRoundedCorners ? "\(Int(round(s.pinCornerRadius))) px" : "直角"

        let pct = Int(round(s.toolbarGlassOpacity * 100))
        glassOpacitySlider.doubleValue = Double(pct)
        glassOpacityLabel.stringValue = "\(pct)%"

        for btn in recorderButtons.values {
            btn.updateButtonTitle()
        }
    }

    private func setupUI() {
        let backdrop = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        backdrop.material = .underWindowBackground
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active

        tabBar = GlassTabBar(items: [
            ("通用与保存", "gearshape"),
            ("全局快捷键", "command"),
            ("截图与贴图", "camera.viewfinder")
        ])
        tabBar.onSelect = { [weak self] idx in
            self?.showTab(index: idx, animated: true, syncTabBar: false)
        }
        backdrop.addSubview(tabBar)

        pageHost.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(pageHost)

        NSLayoutConstraint.activate([
            tabBar.centerXAnchor.constraint(equalTo: backdrop.centerXAnchor),
            tabBar.topAnchor.constraint(equalTo: backdrop.topAnchor, constant: 38),

            pageHost.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            pageHost.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            pageHost.topAnchor.constraint(equalTo: tabBar.bottomAnchor, constant: 12),
            pageHost.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor)
        ])

        pages = [buildGeneralTab(), buildShortcutsTab(), buildCapturePinTab()]
        for page in pages {
            page.translatesAutoresizingMaskIntoConstraints = false
            pageHost.addSubview(page)
            NSLayoutConstraint.activate([
                page.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor),
                page.topAnchor.constraint(equalTo: pageHost.topAnchor)
            ])
        }

        self.contentView = backdrop
    }

    // MARK: - Tab 1: General

    private func buildGeneralTab() -> NSView {
        let stack = makePageStack()

        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(launchAtLoginToggled)
        soundSwitch.target = self
        soundSwitch.action = #selector(soundToggled)
        autoCopyOnSaveSwitch.target = self
        autoCopyOnSaveSwitch.action = #selector(autoCopyOnSaveToggled)

        stack.addArrangedSubview(makeSectionHeader("常规"))
        let generalCard = SettingsCardView(rows: [
            makeSwitchRow(title: "开机自动启动 PixSnap", subtitle: nil, toggle: launchAtLoginSwitch),
            makeSwitchRow(title: "完成提示音", subtitle: "复制或保存截图时播放轻提示音", toggle: soundSwitch),
            makeSwitchRow(title: "快速保存时同时复制到剪贴板", subtitle: nil, toggle: autoCopyOnSaveSwitch)
        ])
        stack.addArrangedSubview(generalCard)
        generalCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36).isActive = true

        stack.addArrangedSubview(makeSectionHeader("保存设置"))

        // Save folder row
        let dirRow = makeRowContainer()
        let dirLeft = NSStackView()
        dirLeft.orientation = .vertical
        dirLeft.alignment = .leading
        dirLeft.spacing = 3
        let dirTitle = NSTextField(labelWithString: "快速保存目录 (⌘S)")
        dirTitle.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        saveDirLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        saveDirLabel.textColor = .secondaryLabelColor
        saveDirLabel.lineBreakMode = .byTruncatingMiddle
        saveDirLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dirLeft.addArrangedSubview(dirTitle)
        dirLeft.addArrangedSubview(saveDirLabel)

        let chooseBtn = makeGlassButton(title: "选择…", symbol: "folder", controlSize: .small, target: self, action: #selector(chooseSaveDirectory))
        let revealBtn = makeGlassButton(title: "打开", symbol: "arrow.up.forward.square", controlSize: .small, target: self, action: #selector(revealSaveDirectory))

        dirRow.addArrangedSubview(dirLeft)
        dirRow.addArrangedSubview(makeSpacer())
        dirRow.addArrangedSubview(chooseBtn)
        dirRow.addArrangedSubview(revealBtn)

        // Format row
        for fmt in SaveImageFormat.allCases {
            formatPopup.addItem(withTitle: fmt.displayName)
        }
        applyGlassPopupStyle(formatPopup)
        formatPopup.target = self
        formatPopup.action = #selector(saveFormatChanged)
        let fmtRow = makeControlRow(title: "默认保存格式", control: formatPopup)

        let saveCard = SettingsCardView(rows: [dirRow, fmtRow])
        stack.addArrangedSubview(saveCard)
        saveCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36).isActive = true

        return stack
    }

    // MARK: - Tab 2: Shortcuts

    private func buildShortcutsTab() -> NSView {
        let stack = makePageStack()

        let intro = NSTextField(labelWithString: "点击右侧胶囊按钮后按下组合键，设置立即全局生效。")
        intro.font = NSFont.systemFont(ofSize: 11.5)
        intro.textColor = .secondaryLabelColor
        stack.addArrangedSubview(intro)

        var shortcutRows: [NSView] = []
        for action in HotKeyAction.allCases {
            let row = makeRowContainer()
            let titleLbl = NSTextField(labelWithString: action.title)
            titleLbl.font = NSFont.systemFont(ofSize: 13, weight: .regular)
            row.addArrangedSubview(titleLbl)
            row.addArrangedSubview(makeSpacer())

            let recBtn = ShortcutRecordButton(action: action)
            recBtn.translatesAutoresizingMaskIntoConstraints = false
            recBtn.widthAnchor.constraint(equalToConstant: 196).isActive = true
            recBtn.heightAnchor.constraint(equalToConstant: 28).isActive = true
            recBtn.onWillStartRecording = { [weak self] startingBtn in
                self?.stopAllShortcutRecording(except: startingBtn, resumeHotKeys: false)
            }
            recBtn.onShortcutRecorded = { [weak self] act, kc, mods, disp in
                self?.handleShortcutRecorded(action: act, keyCode: kc, modifiers: mods, display: disp)
            }
            recBtn.onInvalidShortcut = { [weak self] msg in
                self?.showShortcutStatus(msg, symbol: "exclamationmark.triangle.fill", color: .systemOrange)
            }
            recBtn.onShortcutCleared = { [weak self] act in
                HotKeyManager.shared.clearHotKey(action: act)
                self?.recorderButtons[act]?.updateButtonTitle()
                self?.showShortcutStatus("已清除「\(act.title)」快捷键", symbol: "checkmark.circle.fill", color: .systemGreen)
            }
            recorderButtons[action] = recBtn
            row.addArrangedSubview(recBtn)

            if action != .capture {
                let clearBtn = makeGlassButton(title: "清除", controlSize: .small, target: self, action: #selector(clearShortcutClicked(_:)))
                clearBtn.tag = Int(action.rawValue)
                clearBtn.widthAnchor.constraint(equalToConstant: 52).isActive = true
                row.addArrangedSubview(clearBtn)
            } else {
                let pad = NSView()
                pad.translatesAutoresizingMaskIntoConstraints = false
                pad.widthAnchor.constraint(equalToConstant: 52).isActive = true
                row.addArrangedSubview(pad)
            }

            shortcutRows.append(row)
        }

        let card = SettingsCardView(rows: shortcutRows)
        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36).isActive = true

        shortcutStatusRow.orientation = .horizontal
        shortcutStatusRow.alignment = .centerY
        shortcutStatusRow.spacing = 6
        shortcutStatusRow.isHidden = true
        shortcutStatusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        shortcutStatusLabel.lineBreakMode = .byWordWrapping
        shortcutStatusLabel.preferredMaxLayoutWidth = 480
        shortcutStatusRow.addArrangedSubview(shortcutStatusIcon)
        shortcutStatusRow.addArrangedSubview(shortcutStatusLabel)
        stack.addArrangedSubview(shortcutStatusRow)

        let footerRow = NSStackView()
        footerRow.orientation = .horizontal
        footerRow.alignment = .centerY
        footerRow.spacing = 12
        let resetBtn = makeGlassButton(title: "恢复全部默认快捷键", symbol: "arrow.counterclockwise", controlSize: .regular, target: self, action: #selector(resetAllShortcuts))
        footerRow.addArrangedSubview(resetBtn)
        stack.addArrangedSubview(footerRow)

        let tip = NSTextField(wrappingLabelWithString: "• 普通字母/数字键需搭配 ⌘ / ⌥ / ⌃ 之一，避免影响日常打字；F1 ~ F12 支持单键绑定。\n• 若快捷键已被系统或其他软件占用，将自动保留原设置并提示冲突。")
        tip.font = NSFont.systemFont(ofSize: 11)
        tip.textColor = .secondaryLabelColor
        tip.preferredMaxLayoutWidth = Self.windowWidth - 40
        stack.addArrangedSubview(tip)

        return stack
    }

    // MARK: - Tab 3: Capture & Pin

    private func buildCapturePinTab() -> NSView {
        let stack = makePageStack()

        // Section 1: Capture & Glass
        stack.addArrangedSubview(makeSectionHeader("截图与工具栏"))

        magnifierSwitch.target = self
        magnifierSwitch.action = #selector(magnifierToggled)
        windowDetectSwitch.target = self
        windowDetectSwitch.action = #selector(windowDetectToggled)

        for fmt in ColorCopyFormat.allCases {
            colorFormatPopup.addItem(withTitle: fmt.displayName)
        }
        applyGlassPopupStyle(colorFormatPopup)
        colorFormatPopup.target = self
        colorFormatPopup.action = #selector(colorFormatChanged)

        let captureCard = SettingsCardView(rows: [
            makeSwitchRow(title: "悬停显示 15×15 像素放大镜与取色器", subtitle: nil, toggle: magnifierSwitch),
            makeSwitchRow(title: "自动探测前台应用窗口边界吸附", subtitle: nil, toggle: windowDetectSwitch),
            makeControlRow(title: "默认取色格式 (C 复制 / Tab 切换)", control: colorFormatPopup),
            makeGlassOpacityRow()
        ])
        stack.addArrangedSubview(captureCard)
        captureCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36).isActive = true

        // Section 2: Corners
        stack.addArrangedSubview(makeSectionHeader("边角样式"))
        let cornersCard = SettingsCardView(rows: [
            makeCornerControlRow(
                title: "框选边角 (R)",
                segmented: selectionCornerSeg,
                segAction: #selector(selectionCornerStyleChanged),
                slider: selectionRadiusSlider,
                sliderAction: #selector(selectionRadiusChanged),
                valueLabel: selectionRadiusLabel
            ),
            makeCornerControlRow(
                title: "矩形标注边角",
                segmented: rectCornerSeg,
                segAction: #selector(rectCornerStyleChanged),
                slider: rectRadiusSlider,
                sliderAction: #selector(rectRadiusChanged),
                valueLabel: rectRadiusLabel
            ),
            makeCornerControlRow(
                title: "贴图边框边角",
                segmented: pinCornerSeg,
                segAction: #selector(pinCornerStyleChanged),
                slider: pinRadiusSlider,
                sliderAction: #selector(pinRadiusChanged),
                valueLabel: pinRadiusLabel
            )
        ])
        stack.addArrangedSubview(cornersCard)
        cornersCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36).isActive = true

        // Section 3: Pin
        stack.addArrangedSubview(makeSectionHeader("贴图行为"))

        for mode in PinZoomAnchorMode.allCases {
            pinAnchorPopup.addItem(withTitle: mode.displayName)
        }
        applyGlassPopupStyle(pinAnchorPopup)
        pinAnchorPopup.target = self
        pinAnchorPopup.action = #selector(pinAnchorChanged)

        pinBorderSwitch.target = self
        pinBorderSwitch.action = #selector(pinBorderToggled)
        pinSpacesSwitch.target = self
        pinSpacesSwitch.action = #selector(pinSpacesToggled)

        let pinCard = SettingsCardView(rows: [
            makeControlRow(title: "贴图滚轮缩放锚点", control: pinAnchorPopup),
            makeSwitchRow(title: "贴图显示细边框", subtitle: "浅色截图置顶时更易辨识边界", toggle: pinBorderSwitch),
            makeSwitchRow(title: "跨桌面空间与全屏应用持续置顶", subtitle: nil, toggle: pinSpacesSwitch)
        ])
        stack.addArrangedSubview(pinCard)
        pinCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36).isActive = true

        return stack
    }

    // MARK: - Layout Builders

    private func makePageStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 18, bottom: 10, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeSectionHeader(_ title: String) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let lbl = NSTextField(labelWithString: title)
        lbl.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        lbl.textColor = .secondaryLabelColor
        lbl.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 6),
            lbl.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            lbl.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 4),
            lbl.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -1)
        ])
        return wrap
    }

    private func makeRowContainer(verticalInset: CGFloat = 10) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: verticalInset, left: 14, bottom: verticalInset, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func makeSpacer() -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    private func makeSwitchRow(title: String, subtitle: String?, toggle: NSSwitch) -> NSView {
        toggle.controlSize = .small
        let row = makeRowContainer()
        if let subtitle {
            let left = NSStackView()
            left.orientation = .vertical
            left.alignment = .leading
            left.spacing = 2
            let t = NSTextField(labelWithString: title)
            t.font = NSFont.systemFont(ofSize: 13, weight: .regular)
            let sub = NSTextField(labelWithString: subtitle)
            sub.font = NSFont.systemFont(ofSize: 11)
            sub.textColor = .secondaryLabelColor
            left.addArrangedSubview(t)
            left.addArrangedSubview(sub)
            row.addArrangedSubview(left)
        } else {
            let t = NSTextField(labelWithString: title)
            t.font = NSFont.systemFont(ofSize: 13, weight: .regular)
            row.addArrangedSubview(t)
        }
        row.addArrangedSubview(makeSpacer())
        row.addArrangedSubview(toggle)
        return row
    }

    private func makeControlRow(title: String, control: NSView) -> NSView {
        let row = makeRowContainer()
        let lbl = NSTextField(labelWithString: title)
        lbl.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        row.addArrangedSubview(lbl)
        row.addArrangedSubview(makeSpacer())
        row.addArrangedSubview(control)
        return row
    }

    private func makeCornerControlRow(
        title: String,
        segmented: NSSegmentedControl,
        segAction: Selector,
        slider: NSSlider,
        sliderAction: Selector,
        valueLabel: NSTextField
    ) -> NSView {
        let row = makeRowContainer(verticalInset: 9)

        let lbl = NSTextField(labelWithString: title)
        lbl.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        lbl.widthAnchor.constraint(equalToConstant: 112).isActive = true
        row.addArrangedSubview(lbl)

        applyCapsuleSegmentStyle(segmented)
        segmented.target = self
        segmented.action = segAction
        segmented.controlSize = .small
        segmented.widthAnchor.constraint(equalToConstant: 108).isActive = true
        row.addArrangedSubview(segmented)

        slider.target = self
        slider.action = sliderAction
        slider.isContinuous = true
        slider.controlSize = .small
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(slider)

        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 42).isActive = true
        row.addArrangedSubview(valueLabel)

        return row
    }

    private func makeGlassOpacityRow() -> NSView {
        let col = NSStackView()
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 4
        col.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        col.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false

        let lbl = NSTextField(labelWithString: "工具栏玻璃")
        lbl.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        lbl.widthAnchor.constraint(equalToConstant: 96).isActive = true
        row.addArrangedSubview(lbl)

        let moreClear = NSTextField(labelWithString: "透")
        moreClear.font = NSFont.systemFont(ofSize: 11)
        moreClear.textColor = .secondaryLabelColor
        row.addArrangedSubview(moreClear)

        glassOpacitySlider.target = self
        glassOpacitySlider.action = #selector(glassOpacityChanged)
        glassOpacitySlider.isContinuous = true
        glassOpacitySlider.controlSize = .small
        glassOpacitySlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(glassOpacitySlider)

        let moreSolid = NSTextField(labelWithString: "实")
        moreSolid.font = NSFont.systemFont(ofSize: 11)
        moreSolid.textColor = .secondaryLabelColor
        row.addArrangedSubview(moreSolid)

        glassOpacityLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        glassOpacityLabel.textColor = .secondaryLabelColor
        glassOpacityLabel.alignment = .right
        glassOpacityLabel.widthAnchor.constraint(equalToConstant: 38).isActive = true
        row.addArrangedSubview(glassOpacityLabel)

        let resetBtn = makeGlassButton(title: "默认", controlSize: .small, target: self, action: #selector(resetGlassOpacity))
        row.addArrangedSubview(resetBtn)

        col.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: col.widthAnchor, constant: -28).isActive = true

        let hint = NSTextField(labelWithString: PixTheme.supportsLiquidGlass
            ? "拖动实时生效；越往左越透明，100% 为系统原生液态玻璃。"
            : "需要 macOS 26 及以上（液态玻璃）才会生效。")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        col.addArrangedSubview(hint)

        glassOpacitySlider.isEnabled = PixTheme.supportsLiquidGlass
        return col
    }

    // MARK: - Actions

    @objc private func launchAtLoginToggled() {
        let desired = (launchAtLoginSwitch.state == .on)
        let ok = AppSettings.shared.setLaunchAtLogin(desired)
        if !ok {
            launchAtLoginSwitch.state = AppSettings.shared.isLaunchAtLoginEnabled ? .on : .off
            ToastHUD.shared.show(
                "请在「系统设置 -> 通用 -> 登录项」中允许 PixSnap",
                symbolName: "gearshape.fill",
                accentColor: .systemOrange,
                duration: 2.5
            )
        }
    }

    @objc private func soundToggled() {
        AppSettings.shared.playCaptureSound = (soundSwitch.state == .on)
    }

    @objc private func autoCopyOnSaveToggled() {
        AppSettings.shared.autoCopyOnSave = (autoCopyOnSaveSwitch.state == .on)
    }

    @objc private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = AppSettings.shared.saveDirectoryURL
        panel.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            AppSettings.shared.saveDirectoryURL = url
            self?.saveDirLabel.stringValue = url.path
        }
    }

    @objc private func revealSaveDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([AppSettings.shared.saveDirectoryURL])
    }

    @objc private func saveFormatChanged() {
        let idx = formatPopup.indexOfSelectedItem
        if idx >= 0 && idx < SaveImageFormat.allCases.count {
            AppSettings.shared.saveFormat = SaveImageFormat.allCases[idx]
        }
    }

    private func handleShortcutRecorded(action: HotKeyAction, keyCode: UInt32, modifiers: UInt32, display: String) {
        let success = HotKeyManager.shared.updateHotKey(
            action: action,
            keyCode: keyCode,
            modifiers: modifiers,
            displayString: display
        )
        recorderButtons[action]?.updateButtonTitle()
        if success {
            showShortcutStatus("「\(action.title)」已生效：\(display)", symbol: "checkmark.circle.fill", color: .systemGreen)
        } else {
            showShortcutStatus("注册失败：\(display) 可能与系统或其他快捷键冲突，已保留原设置", symbol: "xmark.circle.fill", color: .systemRed)
        }
    }

    @objc private func clearShortcutClicked(_ sender: NSButton) {
        stopAllShortcutRecording(resumeHotKeys: true)
        guard let action = HotKeyAction(rawValue: UInt32(sender.tag)) else { return }
        HotKeyManager.shared.clearHotKey(action: action)
        recorderButtons[action]?.updateButtonTitle()
        showShortcutStatus("已清除「\(action.title)」快捷键", symbol: "checkmark.circle.fill", color: .systemGreen)
    }

    @objc private func resetAllShortcuts() {
        stopAllShortcutRecording(resumeHotKeys: true)
        HotKeyManager.shared.resetAllToDefault()
        for btn in recorderButtons.values {
            btn.updateButtonTitle()
        }
        showShortcutStatus("已恢复全部默认快捷键", symbol: "checkmark.circle.fill", color: .systemGreen)
    }

    private func showShortcutStatus(_ text: String, symbol: String, color: NSColor) {
        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
            img.isTemplate = true
            shortcutStatusIcon.image = img
            shortcutStatusIcon.contentTintColor = color
        }
        shortcutStatusLabel.stringValue = text
        shortcutStatusLabel.textColor = color
        shortcutStatusRow.isHidden = false
        selectTab(index: selectedTabIndex, animated: false)
    }

    @objc private func magnifierToggled() {
        AppSettings.shared.showMagnifier = (magnifierSwitch.state == .on)
    }

    @objc private func windowDetectToggled() {
        AppSettings.shared.enableWindowDetection = (windowDetectSwitch.state == .on)
    }

    @objc private func colorFormatChanged() {
        let idx = colorFormatPopup.indexOfSelectedItem
        if idx >= 0 && idx < ColorCopyFormat.allCases.count {
            AppSettings.shared.colorCopyFormat = ColorCopyFormat.allCases[idx]
        }
    }

    @objc private func pinAnchorChanged() {
        let idx = pinAnchorPopup.indexOfSelectedItem
        if idx >= 0 && idx < PinZoomAnchorMode.allCases.count {
            AppSettings.shared.pinZoomAnchorMode = PinZoomAnchorMode.allCases[idx]
        }
    }

    @objc private func pinBorderToggled() {
        AppSettings.shared.pinShowBorder = (pinBorderSwitch.state == .on)
        onPinAppearanceSettingsChanged?()
    }

    @objc private func pinSpacesToggled() {
        AppSettings.shared.pinStayAcrossSpaces = (pinSpacesSwitch.state == .on)
        onPinAppearanceSettingsChanged?()
    }

    @objc private func selectionCornerStyleChanged() {
        let rounded = (selectionCornerSeg.selectedSegment == 1)
        AppSettings.shared.selectionUseRoundedCorners = rounded
        selectionRadiusSlider.isEnabled = rounded
        selectionRadiusLabel.stringValue = rounded ? "\(Int(round(AppSettings.shared.selectionCornerRadius))) px" : "直角"
    }

    @objc private func selectionRadiusChanged() {
        let val = round(selectionRadiusSlider.doubleValue)
        AppSettings.shared.selectionCornerRadius = CGFloat(val)
        selectionRadiusLabel.stringValue = "\(Int(val)) px"
    }

    @objc private func rectCornerStyleChanged() {
        let rounded = (rectCornerSeg.selectedSegment == 1)
        AppSettings.shared.rectAnnotationRounded = rounded
        rectRadiusSlider.isEnabled = rounded
        rectRadiusLabel.stringValue = rounded ? "\(Int(round(AppSettings.shared.rectAnnotationCornerRadius))) px" : "直角"
    }

    @objc private func rectRadiusChanged() {
        let val = round(rectRadiusSlider.doubleValue)
        AppSettings.shared.rectAnnotationCornerRadius = CGFloat(val)
        rectRadiusLabel.stringValue = "\(Int(val)) px"
    }

    @objc private func pinCornerStyleChanged() {
        let rounded = (pinCornerSeg.selectedSegment == 1)
        AppSettings.shared.pinUseRoundedCorners = rounded
        pinRadiusSlider.isEnabled = rounded
        pinRadiusLabel.stringValue = rounded ? "\(Int(round(AppSettings.shared.pinCornerRadius))) px" : "直角"
        onPinAppearanceSettingsChanged?()
    }

    @objc private func glassOpacityChanged() {
        let pct = round(glassOpacitySlider.doubleValue)
        AppSettings.shared.toolbarGlassOpacity = CGFloat(pct / 100)
        glassOpacityLabel.stringValue = "\(Int(pct))%"
    }

    @objc private func resetGlassOpacity() {
        AppSettings.shared.toolbarGlassOpacity = AppSettings.toolbarGlassOpacityDefault
        let pct = round(AppSettings.toolbarGlassOpacityDefault * 100)
        glassOpacitySlider.doubleValue = Double(pct)
        glassOpacityLabel.stringValue = "\(Int(pct))%"
    }

    @objc private func pinRadiusChanged() {
        let val = round(pinRadiusSlider.doubleValue)
        AppSettings.shared.pinCornerRadius = CGFloat(val)
        pinRadiusLabel.stringValue = "\(Int(val)) px"
        onPinAppearanceSettingsChanged?()
    }
}
