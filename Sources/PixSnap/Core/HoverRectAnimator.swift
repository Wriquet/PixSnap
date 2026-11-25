import CoreGraphics
import Foundation

/// Critically damped spring interpolator for smooth, zero-overshoot hover region transitions.
///
/// Animates the 4 edges (`minX`, `minY`, `maxX`, `maxY`) independently so shared edges between
/// nested hierarchy levels (e.g., an image anchored to a card or window edge) remain rock-solid
/// while the other edges glide smoothly at native display refresh rate (60Hz / 120Hz ProMotion).
public struct HoverRectAnimator: Sendable {
    private struct SpringAxis: Sendable {
        var value: CGFloat = 0
        var velocity: CGFloat = 0
        var target: CGFloat = 0

        mutating func snap(to v: CGFloat) {
            value = v
            target = v
            velocity = 0
        }

        /// Analytical critically damped spring step (`ζ = 1`, zero overshoot, unconditionally stable).
        mutating func step(dt: CGFloat, omega: CGFloat) -> Bool {
            let d = value - target
            let e = exp(-omega * dt)
            let c2 = velocity + omega * d
            value = target + (d + c2 * dt) * e
            velocity = (velocity - omega * c2 * dt) * e

            if abs(value - target) < 0.35 && abs(velocity) < 4.0 {
                value = target
                velocity = 0
                return false
            }
            return true
        }
    }

    private var minX = SpringAxis()
    private var minY = SpringAxis()
    private var maxX = SpringAxis()
    private var maxY = SpringAxis()

    /// Visual opacity `[0, 1]` for smooth fade-in / fade-out when entering or leaving all targets
    public private(set) var currentAlpha: CGFloat = 0
    public private(set) var targetAlpha: CGFloat = 0
    public private(set) var targetRect: CGRect?
    private var hasVisualRect: Bool = false

    /// Natural angular frequency (rad/s). `34` settles 97% in ~155ms with crisp initial response and zero overshoot.
    public let omega: CGFloat
    /// Opacity fade speed (units/sec). `10.0` completes a full fade in ~100ms.
    public let alphaRate: CGFloat

    public init(omega: CGFloat = 34.0, alphaRate: CGFloat = 10.0) {
        self.omega = omega
        self.alphaRate = alphaRate
    }

    /// Current interpolated rectangle for rendering.
    public var currentRect: CGRect {
        guard hasVisualRect else { return .zero }
        let w = max(0, maxX.value - minX.value)
        let h = max(0, maxY.value - minY.value)
        return CGRect(x: minX.value, y: minY.value, width: w, height: h)
    }

    /// Whether the animator still needs display-link ticks to settle.
    public var isAnimating: Bool {
        if abs(currentAlpha - targetAlpha) > 0.005 { return true }
        guard hasVisualRect, targetAlpha > 0 else { return false }
        return minX.value != minX.target || minX.velocity != 0 ||
               minY.value != minY.target || minY.velocity != 0 ||
               maxX.value != maxX.target || maxX.velocity != 0 ||
               maxY.value != maxY.target || maxY.velocity != 0
    }

    /// Update the logical target rectangle.
    /// - Parameters:
    ///   - rect: New hover target, or `nil` when hovering over empty desktop / no window.
    ///   - immediate: Pass `true` to snap instantaneously (e.g. initial capture open).
    public mutating func setTarget(_ rect: CGRect?, immediate: Bool = false) {
        targetRect = rect

        guard let rect, rect.width > 0, rect.height > 0 else {
            targetAlpha = 0
            if immediate {
                currentAlpha = 0
                hasVisualRect = false
                minX.snap(to: 0)
                minY.snap(to: 0)
                maxX.snap(to: 0)
                maxY.snap(to: 0)
            }
            return
        }

        targetAlpha = 1

        // Snap edges on very first appearance (or after completely fading out) so the box never
        // flies in from (0, 0); fade alpha in smoothly unless `immediate == true`.
        if immediate || !hasVisualRect || currentAlpha <= 0.02 {
            minX.snap(to: rect.minX)
            minY.snap(to: rect.minY)
            maxX.snap(to: rect.maxX)
            maxY.snap(to: rect.maxY)
            hasVisualRect = true
            if immediate {
                currentAlpha = 1
            }
            return
        }

        // Preserve velocity across consecutive target changes (e.g. rapid scroll-wheel stepping)
        minX.target = rect.minX
        minY.target = rect.minY
        maxX.target = rect.maxX
        maxY.target = rect.maxY
    }

    /// Reset completely (e.g. leaving hover state or switching active monitor).
    public mutating func reset() {
        targetRect = nil
        targetAlpha = 0
        currentAlpha = 0
        hasVisualRect = false
        minX.snap(to: 0)
        minY.snap(to: 0)
        maxX.snap(to: 0)
        maxY.snap(to: 0)
    }

    /// Advance the spring & opacity simulation by `dt` seconds.
    /// Returns `true` if another frame is needed, or `false` once completely settled.
    @discardableResult
    public mutating func step(dt rawDt: CFTimeInterval) -> Bool {
        let dt = CGFloat(min(max(rawDt, 1.0 / 240.0), 1.0 / 20.0))

        var moving = false
        if hasVisualRect {
            let m1 = minX.step(dt: dt, omega: omega)
            let m2 = minY.step(dt: dt, omega: omega)
            let m3 = maxX.step(dt: dt, omega: omega)
            let m4 = maxY.step(dt: dt, omega: omega)
            moving = m1 || m2 || m3 || m4
        }

        let alphaDelta = targetAlpha - currentAlpha
        if abs(alphaDelta) > 0.005 {
            let stepAlpha = min(abs(alphaDelta), alphaRate * dt)
            currentAlpha += (alphaDelta > 0 ? stepAlpha : -stepAlpha)
            if abs(targetAlpha - currentAlpha) <= 0.005 {
                currentAlpha = targetAlpha
            } else {
                moving = true
            }
        } else {
            currentAlpha = targetAlpha
        }

        if currentAlpha <= 0.001 && targetAlpha == 0 {
            hasVisualRect = false
            moving = false
        }

        return moving
    }
}
