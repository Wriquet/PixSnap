import Testing
import CoreGraphics
@testable import PixSnap

struct GlassToneGateTests {
    @Test func firstDecisionSnapsWithoutAnimation() {
        var gate = GlassToneGate()
        #expect(gate.evaluate(luminance: 0.9, now: 0) == .apply(dark: false, animated: false))
    }

    @Test func noiseInsideDeadZoneNeverFlips() {
        var gate = GlassToneGate()
        _ = gate.evaluate(luminance: 0.2, now: 0) // dark
        // Jitter around the old single 0.5 threshold: must stay dark the whole time
        for (i, l) in [0.49, 0.51, 0.48, 0.55, 0.50, 0.57, 0.45].enumerated() {
            #expect(gate.evaluate(luminance: CGFloat(l), now: Double(i + 1)) == .keep)
        }
        #expect(gate.isDark == true)
    }

    @Test func clearCrossingFlipsWithCrossfade() {
        var gate = GlassToneGate()
        _ = gate.evaluate(luminance: 0.2, now: 0)
        #expect(gate.evaluate(luminance: 0.7, now: 1) == .apply(dark: false, animated: true))
        #expect(gate.evaluate(luminance: 0.45, now: 2) == .keep)
        #expect(gate.evaluate(luminance: 0.3, now: 3) == .apply(dark: true, animated: true))
    }

    @Test func rapidAlternationIsLockedOutThenSettles() {
        var gate = GlassToneGate(cooldown: 0.45)
        _ = gate.evaluate(luminance: 0.2, now: 0)
        #expect(gate.evaluate(luminance: 0.9, now: 1.0) == .apply(dark: false, animated: true))
        // Dragging fast across a dark stripe 0.1 s later: deferred, not applied
        #expect(gate.evaluate(luminance: 0.1, now: 1.1) == .retry(at: 1.45))
        #expect(gate.isDark == false)
        // Trailing re-evaluation after the lock-out applies the final state
        #expect(gate.evaluate(luminance: 0.1, now: 1.47) == .apply(dark: true, animated: true))
    }
}
