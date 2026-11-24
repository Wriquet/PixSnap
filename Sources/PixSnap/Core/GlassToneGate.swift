import Foundation
import CoreGraphics

/// Decides when adaptive Liquid Glass should flip between its light and dark rendition.
///
/// Combines the two standard anti-flicker techniques for luminance-adaptive UI:
/// 1. **Hysteresis (Schmitt trigger)** – two thresholds with a dead-zone between them; inside the
///    dead-zone the current tone is kept, so hovering on a light/dark boundary can never strobe.
/// 2. **Lock-out cool-down** – after a flip, another flip is postponed until `cooldown` elapses;
///    the caller re-evaluates at `retryAt` (trailing evaluation) so the final state is still correct.
public struct GlassToneGate: Sendable {
    public enum Decision: Equatable, Sendable {
        /// Keep the current tone.
        case keep
        /// Switch tone. `animated` is false for the very first decision (no cross-fade on appear).
        case apply(dark: Bool, animated: Bool)
        /// A flip is wanted but locked out; re-evaluate at the given time.
        case retry(at: TimeInterval)
    }

    public let toLightThreshold: CGFloat
    public let toDarkThreshold: CGFloat
    public let cooldown: TimeInterval

    public private(set) var isDark: Bool?
    private var lastFlip: TimeInterval = -.infinity

    public init(toLightThreshold: CGFloat = 0.58, toDarkThreshold: CGFloat = 0.40, cooldown: TimeInterval = 0.45) {
        precondition(toLightThreshold > toDarkThreshold, "hysteresis band must be non-empty")
        self.toLightThreshold = toLightThreshold
        self.toDarkThreshold = toDarkThreshold
        self.cooldown = cooldown
    }

    public mutating func evaluate(luminance: CGFloat, now: TimeInterval) -> Decision {
        let wantDark: Bool
        switch isDark {
        case .some(true):  wantDark = luminance < toLightThreshold
        case .some(false): wantDark = luminance <= toDarkThreshold
        case .none:        wantDark = luminance < (toLightThreshold + toDarkThreshold) / 2
        }
        guard wantDark != isDark else { return .keep }

        let first = (isDark == nil)
        if !first, now - lastFlip < cooldown {
            return .retry(at: lastFlip + cooldown)
        }
        isDark = wantDark
        lastFlip = now
        return .apply(dark: wantDark, animated: !first)
    }
}
