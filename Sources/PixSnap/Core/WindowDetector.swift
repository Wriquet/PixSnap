import ScreenCaptureKit
import Cocoa

public struct DetectedWindow: Sendable, Equatable {
    /// Local coordinates inside the target screen's OverlayView (bottom-left origin)
    public let rect: CGRect
    public let title: String
    public let appName: String
    public let pid: pid_t
    public let windowID: CGWindowID
    public let windowLayer: Int
    /// Semantic kind shown in the hover pill tag (e.g. "图片", "元素", nil for top-level window)
    public let elementRoleLabel: String?

    public init(
        rect: CGRect,
        title: String,
        appName: String,
        pid: pid_t = 0,
        windowID: CGWindowID = 0,
        windowLayer: Int = 0,
        elementRoleLabel: String? = nil
    ) {
        self.rect = rect
        self.title = title
        self.appName = appName
        self.pid = pid
        self.windowID = windowID
        self.windowLayer = windowLayer
        self.elementRoleLabel = elementRoleLabel
    }

    /// Label shown in the floating hover pill tag
    public var hoverTagPrefix: String {
        if let role = elementRoleLabel, !role.isEmpty {
            return "\(appName) · \(role)"
        }
        return appName
    }
}

public final class WindowDetector: @unchecked Sendable {
    public static let shared = WindowDetector()

    private static let ignoredOwnerNames: Set<String> = [
        "Window Server",
        "Dock",
        "WindowManager",
        "Control Center",
        "Notification Center",
        "SystemUIServer"
    ]

    private static let ignoredBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui"
    ]

    /// Convert CoreGraphics global top-left coordinates to Cocoa global bottom-left coordinates,
    /// then clip and localize to a target screen's frame.
    public static func convertAndLocalize(
        cgRect: CGRect,
        primaryScreenHeight: CGFloat,
        targetScreenFrame: CGRect,
        minSize: CGFloat = 36
    ) -> CGRect? {
        let cocoaGlobalY = primaryScreenHeight - (cgRect.origin.y + cgRect.height)
        let cocoaGlobalRect = CGRect(
            x: cgRect.origin.x,
            y: cocoaGlobalY,
            width: cgRect.width,
            height: cgRect.height
        )

        let intersection = cocoaGlobalRect.intersection(targetScreenFrame)
        guard !intersection.isNull, intersection.width >= minSize, intersection.height >= minSize else {
            return nil
        }

        return CGRect(
            x: intersection.origin.x - targetScreenFrame.origin.x,
            y: intersection.origin.y - targetScreenFrame.origin.y,
            width: intersection.width,
            height: intersection.height
        )
    }

    /// Query WindowServer directly via `CGWindowListCopyWindowInfo`, which is guaranteed to be sorted
    /// strictly front-to-back in visual Z-order and includes normal windows + floating panels/popovers.
    public func extractOrderedWindows(
        primaryScreenHeight: CGFloat,
        targetScreenFrame: CGRect,
        excludingPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> [DetectedWindow] {
        guard let rawList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var result: [DetectedWindow] = []
        result.reserveCapacity(rawList.count)

        for info in rawList {
            guard let pidNum = info[kCGWindowOwnerPID as String] as? Int32 else { continue }
            if pidNum == excludingPID { continue }

            let layer = (info[kCGWindowLayer as String] as? Int) ?? 0
            // Include standard windows (0) and floating palettes/popovers/menus (up to 101),
            // excluding desktop backing (< 0) and high-level overlays/cursors/screensavers (> 101).
            guard layer >= 0 && layer <= 101 else { continue }

            let alpha = (info[kCGWindowAlpha as String] as? Double) ?? 1.0
            guard alpha > 0.01 else { continue }

            let ownerName = (info[kCGWindowOwnerName as String] as? String) ?? "应用"
            if Self.ignoredOwnerNames.contains(ownerName) { continue }

            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            guard cgRect.width >= 36 && cgRect.height >= 36 else { continue }

            let rawTitle = (info[kCGWindowName as String] as? String) ?? ""

            // Skip Finder's invisible fullscreen desktop backing window
            if ownerName == "Finder" && rawTitle.isEmpty &&
                cgRect.width >= targetScreenFrame.width - 2 &&
                cgRect.height >= targetScreenFrame.height - 2 {
                continue
            }

            // Skip invisible full-screen click-catcher overlays from Spotlight / Wallpaper / etc.
            if layer > 0 && rawTitle.isEmpty &&
                cgRect.width >= targetScreenFrame.width - 4 &&
                cgRect.height >= targetScreenFrame.height - 4 {
                continue
            }

            guard let localRect = Self.convertAndLocalize(
                cgRect: cgRect,
                primaryScreenHeight: primaryScreenHeight,
                targetScreenFrame: targetScreenFrame
            ) else {
                continue
            }

            let windowID = (info[kCGWindowNumber as String] as? CGWindowID) ?? 0
            let title = rawTitle.isEmpty ? ownerName : rawTitle
            result.append(DetectedWindow(
                rect: localRect,
                title: title,
                appName: ownerName,
                pid: pidNum,
                windowID: windowID,
                windowLayer: layer
            ))
        }
        return result
    }

    /// Extract visible windows for a specific display from an already-fetched SCWindow array
    /// (retained as fallback / test API).
    public func extractVisibleWindows(
        from scWindows: [SCWindow],
        primaryScreenHeight: CGFloat,
        targetScreenFrame: CGRect,
        excludingPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> [DetectedWindow] {
        var result: [DetectedWindow] = []

        for window in scWindows {
            guard window.windowLayer == 0 else { continue }
            guard window.isOnScreen else { continue }

            var pid: pid_t = 0
            if let app = window.owningApplication {
                pid = app.processID
                if app.processID == excludingPID { continue }
                if Self.ignoredBundleIDs.contains(app.bundleIdentifier) { continue }
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
            ) else {
                continue
            }

            let appName = window.owningApplication?.applicationName ?? "应用"
            let title = (window.title?.isEmpty == false ? window.title! : appName)
            result.append(DetectedWindow(
                rect: localRect,
                title: title,
                appName: appName,
                pid: pid,
                windowID: window.windowID,
                windowLayer: window.windowLayer
            ))
        }
        return result
    }

    /// Returns the frontmost window containing `point`.
    public func findWindow(at point: CGPoint, in windows: [DetectedWindow]) -> DetectedWindow? {
        for window in windows {
            if window.rect.contains(point) {
                return window
            }
        }
        return nil
    }

    /// Returns all overlapping windows at `point`, strictly ordered front-to-back (Z-order).
    public func findAllWindows(at point: CGPoint, in windows: [DetectedWindow]) -> [DetectedWindow] {
        windows.filter { $0.rect.contains(point) }
    }

    /// Merges inner element/visual rects with Z-order windows into a clean, deduplicated
    /// innermost-to-outermost candidate stack for hover highlight & scroll-wheel level switching.
    public static func buildCandidateStack(
        axCandidates: [DetectedWindow],
        visualCandidates: [DetectedWindow],
        windowsAtPoint: [DetectedWindow]
    ) -> [DetectedWindow] {
        var combined: [DetectedWindow] = []

        // Collect all sub-window candidates (AX + Visual), preferring smaller/tighter areas first.
        // When an AX candidate and a Visual candidate overlap tightly, AX wins for richer semantic label.
        let subWindow = (axCandidates + visualCandidates).sorted { a, b in
            let areaA = a.rect.width * a.rect.height
            let areaB = b.rect.width * b.rect.height
            if abs(areaA - areaB) < 600 {
                // Prefer AX semantic roles ("图片", "按钮", etc.) over generic visual "区块"
                let aIsVisual = (a.elementRoleLabel == "识别区域")
                let bIsVisual = (b.elementRoleLabel == "识别区域")
                if aIsVisual != bIsVisual { return !aIsVisual }
            }
            return areaA < areaB
        }

        func appendIfDistinct(_ candidate: DetectedWindow) {
            let duplicate = combined.contains { existing in
                abs(existing.rect.minX - candidate.rect.minX) <= 6 &&
                abs(existing.rect.minY - candidate.rect.minY) <= 6 &&
                abs(existing.rect.maxX - candidate.rect.maxX) <= 6 &&
                abs(existing.rect.maxY - candidate.rect.maxY) <= 6
            }
            if !duplicate {
                combined.append(candidate)
            }
        }

        for item in subWindow {
            appendIfDistinct(item)
        }
        // Preserve front-to-back Z-order for top-level windows behind sub-elements
        for win in windowsAtPoint {
            appendIfDistinct(win)
        }
        return combined
    }
}
