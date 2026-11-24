import Testing
import Foundation
@testable import PixSnap

@MainActor
struct GlassOpacitySettingTests {
    @Test func opacityIsClampedPersistedAndBroadcast() {
        let s = AppSettings.shared
        let original = s.toolbarGlassOpacity
        defer { s.toolbarGlassOpacity = original }

        var notified = 0
        let token = NotificationCenter.default.addObserver(forName: AppSettings.toolbarGlassOpacityDidChange, object: nil, queue: nil) { _ in notified += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        s.toolbarGlassOpacity = 0.45
        #expect(abs(s.toolbarGlassOpacity - 0.45) < 0.0001)
        #expect(abs(PixTheme.glassOpacity - 0.45) < 0.0001)
        s.toolbarGlassOpacity = 0.0   // below range
        #expect(s.toolbarGlassOpacity == AppSettings.toolbarGlassOpacityRange.lowerBound)
        s.toolbarGlassOpacity = 5.0   // above range
        #expect(s.toolbarGlassOpacity == AppSettings.toolbarGlassOpacityRange.upperBound)
        #expect(notified == 3)
    }
}
