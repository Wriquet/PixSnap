import ScreenCaptureKit
import Cocoa

public struct DetectedWindow: Sendable, Equatable {
    /// Local coordinates inside the target screen's OverlayView (bottom-left origin)
    public let rect: CGRect
    public let title: String
    public let appName: String

    public init(rect: CGRect, title: String, appName: String) {
        self.rect = rect
        self.title = title
        self.appName = appName
    }
}

public final class WindowDetector: @unchecked Sendable {
    public static let shared = WindowDetector()

    /// Convert CoreGraphics global top-left coordinates to Cocoa global bottom-left coordinates,
    /// then clip and localize to a target screen's frame.
    public static func convertAndLocalize(
        cgRect: CGRect,
        primaryScreenHeight: CGFloat,
        targetScreenFrame: CGRect
    ) -> CGRect? {
        let cocoaGlobalY = primaryScreenHeight - (cgRect.origin.y + cgRect.height)
        let cocoaGlobalRect = CGRect(
            x: cgRect.origin.x,
            y: cocoaGlobalY,
            width: cgRect.width,
            height: cgRect.height
        )

        let intersection = cocoaGlobalRect.intersection(targetScreenFrame)
        guard !intersection.isNull, intersection.width >= 36, intersection.height >= 36 else {
            return nil
        }

        return CGRect(
            x: intersection.origin.x - targetScreenFrame.origin.x,
            y: intersection.origin.y - targetScreenFrame.origin.y,
            width: intersection.width,
            height: intersection.height
        )
    }

    /// Extract visible windows for a specific display from an already-fetched SCWindow array
    /// (zero extra SCShareableContent IPC!).
    public func extractVisibleWindows(
        from scWindows: [SCWindow],
        primaryScreenHeight: CGFloat,
        targetScreenFrame: CGRect,
        excludingPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> [DetectedWindow] {
        var result: [DetectedWindow] = []
        let ignoredBundleIDs: Set<String> = [
            "com.apple.dock",
            "com.apple.WindowManager",
            "com.apple.controlcenter",
            "com.apple.notificationcenterui"
        ]

        for window in scWindows {
            guard window.windowLayer == 0 else { continue }
            guard window.isOnScreen else { continue }

            if let app = window.owningApplication {
                if app.processID == excludingPID { continue }
                if ignoredBundleIDs.contains(app.bundleIdentifier) { continue }
                // Skip Finder's invisible fullscreen desktop backing window
                if app.bundleIdentifier == "com.apple.finder" && (window.title ?? "").isEmpty &&
                    window.frame.width >= targetScreenFrame.width - 2 &&
                    window.frame.height >= targetScreenFrame.height - 2 {
                    continue
                }
            }

            let frame = window.frame
            guard frame.width >= 40 && frame.height >= 40 else { continue }

            guard let localRect = Self.convertAndLocalize(
                cgRect: frame,
                primaryScreenHeight: primaryScreenHeight,
                targetScreenFrame: targetScreenFrame
            ) else { continue }

            let appName = window.owningApplication?.applicationName ?? "应用"
            let title = (window.title?.isEmpty == false ? window.title! : appName)
            result.append(DetectedWindow(rect: localRect, title: title, appName: appName))
        }
        return result
    }

    public func findWindow(at point: CGPoint, in windows: [DetectedWindow]) -> DetectedWindow? {
        for window in windows {
            if window.rect.contains(point) {
                return window
            }
        }
        return nil
    }
}
