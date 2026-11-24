import Cocoa

/// Centralized visual design tokens shared by every capture-time HUD
/// (toolbar, style sub-bar, magnifier, size tags, selection chrome).
/// Keeping every color / radius / metric here is what makes the pieces look like one family.
@MainActor
enum PixTheme {
    // MARK: Colors (fixed sRGB so CALayer colors never drift with appearance changes)

    /// The single brand accent used for active tool, primary action, selection border & handles.
    static let accent = NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1.0)
    static let accentHover = NSColor(srgbRed: 0.20, green: 0.60, blue: 1.0, alpha: 1.0)
    static let destructive = NSColor(srgbRed: 1.0, green: 0.36, blue: 0.33, alpha: 1.0)

    /// Dark tint laid over the blur so the HUD keeps the same contrast on white or black screenshots.
    static let hudTint = NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 0.72)
    static let hudSolid = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 0.94)
    static let hudBorder = NSColor(white: 1.0, alpha: 0.12)

    static let icon = NSColor(white: 1.0, alpha: 0.88)
    static let iconSecondary = NSColor(white: 1.0, alpha: 0.55)
    static let iconDisabled = NSColor(white: 1.0, alpha: 0.24)
    static let textSecondary = NSColor(white: 1.0, alpha: 0.55)

    static let hoverFill = NSColor(white: 1.0, alpha: 0.10)
    static let pressedFill = NSColor(white: 1.0, alpha: 0.16)
    static let segmentTrack = NSColor(white: 1.0, alpha: 0.06)
    static let segmentSelected = NSColor(white: 1.0, alpha: 0.20)
    static let separator = NSColor(white: 1.0, alpha: 0.12)

    // MARK: Metrics

    static let barHeight: CGFloat = 40
    static let subBarHeight: CGFloat = 36
    static let barRadius: CGFloat = 10
    static let buttonSize: CGFloat = 30
    static let segmentSize: CGFloat = 26
    static let buttonRadius: CGFloat = 7
    static let iconPointSize: CGFloat = 14
    static let groupSpacing: CGFloat = 6

    // MARK: Helpers

    static func symbol(_ name: String, pointSize: CGFloat = iconPointSize, weight: NSFont.Weight = .regular) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight, scale: .medium)
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        img?.isTemplate = true
        return img
    }

    /// Applies the shared floating-HUD drop shadow to a layer-backed container.
    static func applyHUDShadow(to view: NSView) {
        view.wantsLayer = true
        view.layer?.masksToBounds = false
        view.layer?.shadowColor = NSColor.black.cgColor
        view.layer?.shadowOpacity = 0.38
        view.layer?.shadowRadius = 12
        view.layer?.shadowOffset = CGSize(width: 0, height: -3)
    }

    static func updateShadowPath(of view: NSView, radius: CGFloat = barRadius) {
        view.layer?.shadowPath = CGPath(
            roundedRect: view.bounds,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
    }

    /// Fades a freshly un-hidden HUD in with a tiny upward drift.
    static func animateAppear(_ view: NSView) {
        guard let layer = view.layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.0
        fade.toValue = 1.0
        let drift = CABasicAnimation(keyPath: "transform.translation.y")
        drift.fromValue = -4.0
        drift.toValue = 0.0
        let group = CAAnimationGroup()
        group.animations = [fade, drift]
        group.duration = 0.16
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(group, forKey: "pixAppear")
    }
}

/// Rounded blurred HUD background shared by the main toolbar and the style sub-bar.
final class HUDBackgroundView: NSView {
    private let effectView = NSVisualEffectView()
    private let tintView = NSView()

    init(cornerRadius: CGFloat = PixTheme.barRadius) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.appearance = NSAppearance(named: .darkAqua)
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = cornerRadius
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)

        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = PixTheme.hudTint.cgColor
        tintView.layer?.cornerRadius = cornerRadius
        tintView.layer?.cornerCurve = .continuous
        tintView.layer?.borderWidth = 1
        tintView.layer?.borderColor = PixTheme.hudBorder.cgColor
        tintView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tintView)

        for v in [effectView, tintView] {
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: leadingAnchor),
                v.trailingAnchor.constraint(equalTo: trailingAnchor),
                v.topAnchor.constraint(equalTo: topAnchor),
                v.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}
