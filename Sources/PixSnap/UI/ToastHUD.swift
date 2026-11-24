import Cocoa

@MainActor
public final class ToastHUD {
    public static let shared = ToastHUD()

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    public func show(
        _ message: String,
        symbolName: String = "checkmark.circle.fill",
        accentColor: NSColor = .systemGreen,
        duration: TimeInterval = 1.6,
        on screen: NSScreen? = nil
    ) {
        dismissWorkItem?.cancel()

        let targetScreen = screen ?? screenAtMouse() ?? NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen else { return }

        let paddingH: CGFloat = 16
        let height: CGFloat = 38
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let textSize = (message as NSString).size(withAttributes: [.font: font])
        let width = max(140, min(460, ceil(textSize.width) + 26 + paddingH * 2))

        let screenFrame = targetScreen.visibleFrame
        let x = round(screenFrame.midX - width / 2.0)
        let y = round(screenFrame.minY + 64)
        let frame = NSRect(x: x, y: y, width: width, height: height)

        let hudPanel: NSPanel
        if let existing = panel {
            hudPanel = existing
            hudPanel.setFrame(frame, display: false)
        } else {
            hudPanel = NSPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            hudPanel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 2)
            hudPanel.isOpaque = false
            hudPanel.backgroundColor = .clear
            hudPanel.hasShadow = true
            hudPanel.ignoresMouseEvents = true
            hudPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            hudPanel.isReleasedWhenClosed = false
            panel = hudPanel
        }

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        effect.wantsLayer = true
        effect.layer?.cornerRadius = height / 2.0
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)

        let iconView = NSImageView()
        let symCfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(symCfg) {
            img.isTemplate = true
            iconView.image = img
            iconView.contentTintColor = accentColor
        }
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        stack.addArrangedSubview(iconView)

        let label = NSTextField(labelWithString: message)
        label.font = font
        label.textColor = .white
        label.lineBreakMode = .byTruncatingMiddle
        stack.addArrangedSubview(label)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: effect.leadingAnchor, constant: paddingH),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: effect.trailingAnchor, constant: -paddingH)
        ])

        hudPanel.contentView = effect
        hudPanel.alphaValue = 0.0
        hudPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            hudPanel.animator().alphaValue = 1.0
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, let hudPanel = self.panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                hudPanel.animator().alphaValue = 0.0
            }, completionHandler: {
                Task { @MainActor in
                    if hudPanel.alphaValue <= 0.01 {
                        hudPanel.orderOut(nil)
                    }
                }
            })
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func screenAtMouse() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(loc) }
    }
}
