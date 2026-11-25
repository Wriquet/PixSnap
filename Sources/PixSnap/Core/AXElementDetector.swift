import Cocoa
import ApplicationServices

/// Layer 3 smart border detector: queries macOS Accessibility (`AXUIElement`) directly on the
/// target window's PID (bypassing our own fullscreen OverlayWindow!) to extract nested UI controls,
/// webpage images (`AXImage`), cards, toolbars, sidebars, and panels.
public final class AXElementDetector: @unchecked Sendable {
    public static let shared = AXElementDetector()

    private let queue = DispatchQueue(label: "com.wangqi.pixsnap.axdetector", qos: .userInteractive)
    private let lock = NSLock()

    private struct CacheKey: Hashable {
        let pid: pid_t
        let gx: Int
        let gy: Int
    }

    private var enhancedPIDs: Set<pid_t> = []
    private var cache: [CacheKey: [DetectedWindow]] = [:]

    private init() {}

    /// Non-prompting check of whether PixSnap currently holds Accessibility permission.
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Triggers macOS's native Accessibility permission dialog (only call from explicit user action in Preferences).
    @MainActor
    public static func requestPermissionPrompt() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    @MainActor
    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Clear per-capture caches when a screenshot session ends.
    public func resetSession() {
        lock.lock()
        cache.removeAll()
        enhancedPIDs.removeAll()
        lock.unlock()
    }

    /// Synchronous cache lookup for a 6×6pt grid cell so moving inside an already-sampled
    /// region never flashes back to Layer 1+2 while waiting for an async dispatch.
    public func cachedElements(at localPoint: CGPoint, pid: pid_t) -> [DetectedWindow]? {
        guard Self.isTrusted, pid > 0 else { return nil }
        let key = CacheKey(
            pid: pid,
            gx: Int(floor(localPoint.x / 6.0)),
            gy: Int(floor(localPoint.y / 6.0))
        )
        lock.lock()
        let hit = cache[key]
        lock.unlock()
        return hit
    }

    /// Asynchronously query nested AX elements enclosing `localPoint` inside `owningWindow`.
    /// Completion is invoked on the main actor.
    public func queryElements(
        at localPoint: CGPoint,
        owningWindow: DetectedWindow,
        screenFrame: CGRect,
        primaryScreenHeight: CGFloat,
        completion: @escaping @MainActor @Sendable ([DetectedWindow]) -> Void
    ) {
        guard Self.isTrusted, owningWindow.pid > 0 else {
            Task { @MainActor in completion([]) }
            return
        }

        let key = CacheKey(
            pid: owningWindow.pid,
            gx: Int(floor(localPoint.x / 6.0)),
            gy: Int(floor(localPoint.y / 6.0))
        )

        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            Task { @MainActor in completion(cached) }
            return
        }
        lock.unlock()

        let cgX = Float(screenFrame.origin.x + localPoint.x)
        let cgY = Float(primaryScreenHeight - (screenFrame.origin.y + localPoint.y))

        queue.async { [weak self] in
            guard let self else { return }
            let elements = self.fetchHierarchySync(
                pid: owningWindow.pid,
                cgX: cgX,
                cgY: cgY,
                owningWindow: owningWindow,
                screenFrame: screenFrame,
                primaryScreenHeight: primaryScreenHeight
            )

            self.lock.lock()
            if self.cache.count > 256 {
                self.cache.removeAll(keepingCapacity: true)
            }
            self.cache[key] = elements
            self.lock.unlock()

            Task { @MainActor in
                completion(elements)
            }
        }
    }

    // MARK: - Background AX Traversal

    private func fetchHierarchySync(
        pid: pid_t,
        cgX: Float,
        cgY: Float,
        owningWindow: DetectedWindow,
        screenFrame: CGRect,
        primaryScreenHeight: CGFloat
    ) -> [DetectedWindow] {
        let appElem = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElem, 0.08)

        // Enable full web / Electron accessibility trees once per PID per capture session
        lock.lock()
        let needsEnhance = !enhancedPIDs.contains(pid)
        if needsEnhance { enhancedPIDs.insert(pid) }
        lock.unlock()

        if needsEnhance {
            AXUIElementSetAttributeValue(appElem, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(appElem, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }

        var hitElement: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(appElem, cgX, cgY, &hitElement)
        guard status == .success, let startElem = hitElement else {
            return []
        }

        let winArea = max(1, owningWindow.rect.width * owningWindow.rect.height)
        var candidates: [DetectedWindow] = []
        var current: AXUIElement? = startElem

        for _ in 0..<18 {
            guard let elem = current else { break }
            let role = copyStringAttribute(elem, attribute: kAXRoleAttribute as CFString) ?? ""

            // Stop once we reach the window or application root (already handled by Layer 1 Z-order)
            if role == (kAXApplicationRole as String) || role == (kAXWindowRole as String) {
                break
            }

            if let cgRect = copyFrame(elem),
               let localRect = WindowDetector.convertAndLocalize(
                   cgRect: cgRect,
                   primaryScreenHeight: primaryScreenHeight,
                   targetScreenFrame: screenFrame,
                   minSize: 18
               ) {
                let clipped = localRect.intersection(owningWindow.rect)
                if !clipped.isNull, clipped.width >= 18, clipped.height >= 18 {
                    let ratio = (clipped.width * clipped.height) / winArea
                    if ratio < 0.96 {
                        let roleLabel = Self.localizedRoleLabel(role)
                        let duplicate = candidates.contains { existing in
                            abs(existing.rect.minX - clipped.minX) <= 5 &&
                            abs(existing.rect.minY - clipped.minY) <= 5 &&
                            abs(existing.rect.maxX - clipped.maxX) <= 5 &&
                            abs(existing.rect.maxY - clipped.maxY) <= 5
                        }
                        if !duplicate {
                            candidates.append(DetectedWindow(
                                rect: clipped,
                                title: owningWindow.title,
                                appName: owningWindow.appName,
                                pid: owningWindow.pid,
                                windowID: owningWindow.windowID,
                                windowLayer: owningWindow.windowLayer,
                                elementRoleLabel: roleLabel
                            ))
                        }
                    }
                }
            }

            current = copyElementAttribute(elem, attribute: kAXParentAttribute as CFString)
        }

        return candidates
    }

    private func copyFrame(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef,
              let sizeVal = sizeRef,
              CFGetTypeID(posVal) == AXValueGetTypeID(),
              CFGetTypeID(sizeVal) == AXValueGetTypeID() else {
            return nil
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size),
              size.width.isFinite, size.height.isFinite,
              origin.x.isFinite, origin.y.isFinite,
              size.width > 0, size.height > 0 else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    private func copyStringAttribute(_ element: AXUIElement, attribute: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success else { return nil }
        return ref as? String
    }

    private func copyElementAttribute(_ element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let val = ref,
              CFGetTypeID(val) == AXUIElementGetTypeID() else {
            return nil
        }
        return (val as! AXUIElement)
    }

    public static func localizedRoleLabel(_ role: String) -> String {
        switch role {
        case "AXImage": return "图片"
        case "AXButton", "AXPopUpButton", "AXMenuButton", "AXRadioButton", "AXCheckBox": return "按钮"
        case "AXToolbar": return "工具栏"
        case "AXTabGroup": return "标签栏"
        case "AXWebArea", "AXScrollArea": return "内容区"
        case "AXTable", "AXList", "AXOutline": return "列表"
        case "AXTextArea", "AXTextField": return "文本框"
        case "AXSheet", "AXPopover", "AXDialog": return "弹窗"
        case "AXSplitGroup": return "分栏"
        case "AXLink": return "链接"
        case "AXStaticText": return "文本"
        default: return "元素"
        }
    }
}
