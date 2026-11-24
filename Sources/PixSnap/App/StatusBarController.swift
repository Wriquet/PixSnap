import Cocoa

@MainActor
public final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var captureMenuItem: NSMenuItem!
    private var ocrMenuItem: NSMenuItem!
    private var pinClipboardMenuItem: NSMenuItem!
    private var restoreLatestPinMenuItem: NSMenuItem!
    private var recentPinsMenuItem: NSMenuItem!
    private var recentPinsSubmenu: NSMenu!
    private var closePinsMenuItem: NSMenuItem!
    private var restoreClickThroughMenuItem: NSMenuItem!

    public var onCaptureRequested: (() -> Void)?
    public var onOCRCaptureRequested: (() -> Void)?
    public var onPinClipboardRequested: (() -> Void)?
    public var onRestoreLatestPinRequested: (() -> Void)?
    public var onRestoreSpecificPinRequested: ((UUID) -> Void)?
    public var onClearPinHistoryRequested: (() -> Void)?
    public var onCloseAllPinsRequested: (() -> Void)?
    public var onRestoreClickThroughRequested: (() -> Void)?
    public var onPreferencesRequested: (() -> Void)?

    public override init() {
        super.init()
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = Self.makeCropStatusIcon()
            button.image?.accessibilityDescription = "PixSnap"
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        captureMenuItem = NSMenuItem(title: "", action: #selector(captureClicked), keyEquivalent: "")
        captureMenuItem.target = self
        captureMenuItem.image = menuIcon("crop")
        menu.addItem(captureMenuItem)

        ocrMenuItem = NSMenuItem(title: "", action: #selector(ocrCaptureClicked), keyEquivalent: "")
        ocrMenuItem.target = self
        ocrMenuItem.image = menuIcon("text.viewfinder")
        menu.addItem(ocrMenuItem)

        pinClipboardMenuItem = NSMenuItem(title: "", action: #selector(pinClipboardClicked), keyEquivalent: "")
        pinClipboardMenuItem.target = self
        pinClipboardMenuItem.image = menuIcon("clipboard")
        menu.addItem(pinClipboardMenuItem)

        menu.addItem(NSMenuItem.separator())

        restoreLatestPinMenuItem = NSMenuItem(title: "", action: #selector(restoreLatestPinClicked), keyEquivalent: "")
        restoreLatestPinMenuItem.target = self
        restoreLatestPinMenuItem.image = menuIcon("arrow.uturn.backward")
        restoreLatestPinMenuItem.isEnabled = false
        menu.addItem(restoreLatestPinMenuItem)

        recentPinsSubmenu = NSMenu(title: "最近关闭的贴图")
        recentPinsSubmenu.autoenablesItems = false
        recentPinsMenuItem = NSMenuItem(title: "最近关闭的贴图", action: nil, keyEquivalent: "")
        recentPinsMenuItem.image = menuIcon("clock.arrow.circlepath")
        recentPinsMenuItem.submenu = recentPinsSubmenu
        recentPinsMenuItem.isEnabled = false
        menu.addItem(recentPinsMenuItem)

        closePinsMenuItem = NSMenuItem(title: "关闭所有贴图", action: #selector(closePinsClicked), keyEquivalent: "")
        closePinsMenuItem.target = self
        closePinsMenuItem.image = menuIcon("pin.slash")
        closePinsMenuItem.isEnabled = false
        menu.addItem(closePinsMenuItem)

        restoreClickThroughMenuItem = NSMenuItem(title: "恢复鼠标穿透贴图", action: #selector(restoreClickThroughClicked), keyEquivalent: "")
        restoreClickThroughMenuItem.target = self
        restoreClickThroughMenuItem.image = menuIcon("cursorarrow.click")
        restoreClickThroughMenuItem.isHidden = true
        menu.addItem(restoreClickThroughMenuItem)

        menu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(title: "偏好设置...", action: #selector(preferencesClicked), keyEquivalent: ",")
        prefsItem.target = self
        prefsItem.image = menuIcon("gearshape")
        menu.addItem(prefsItem)

        let aboutItem = NSMenuItem(title: "关于 PixSnap", action: #selector(aboutClicked), keyEquivalent: "")
        aboutItem.target = self
        aboutItem.image = menuIcon("info.circle")
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 PixSnap", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        refreshShortcutTitles()
        updatePinHistory([])
    }

    /// 极简裁切框矢量菜单栏图标（18×18pt template，自动适配深/浅色菜单栏与 Retina 屏）
    private static func makeCropStatusIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.75)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            // Left & bottom-extending L
            let p1 = CGMutablePath()
            p1.move(to: CGPoint(x: 5.0, y: 15.8))
            p1.addLine(to: CGPoint(x: 5.0, y: 6.2))
            p1.addArc(tangent1End: CGPoint(x: 5.0, y: 5.0), tangent2End: CGPoint(x: 6.2, y: 5.0), radius: 1.2)
            p1.addLine(to: CGPoint(x: 15.8, y: 5.0))
            ctx.addPath(p1)
            ctx.strokePath()

            // Top & right-extending L with crisp gap at intersections
            let p2 = CGMutablePath()
            p2.move(to: CGPoint(x: 2.2, y: 13.0))
            p2.addLine(to: CGPoint(x: 3.0, y: 13.0))
            p2.move(to: CGPoint(x: 7.4, y: 13.0))
            p2.addLine(to: CGPoint(x: 11.8, y: 13.0))
            p2.addArc(tangent1End: CGPoint(x: 13.0, y: 13.0), tangent2End: CGPoint(x: 13.0, y: 11.8), radius: 1.2)
            p2.addLine(to: CGPoint(x: 13.0, y: 7.4))
            p2.move(to: CGPoint(x: 13.0, y: 3.0))
            p2.addLine(to: CGPoint(x: 13.0, y: 2.2))
            ctx.addPath(p2)
            ctx.strokePath()

            return true
        }
        img.isTemplate = true
        return img
    }

    private func menuIcon(_ symbolName: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        img?.isTemplate = true
        return img
    }

    public func refreshShortcutTitles() {
        let capKey = HotKeyManager.shared.displayString(for: .capture)
        let ocrKey = HotKeyManager.shared.displayString(for: .ocrCapture)
        let pinKey = HotKeyManager.shared.displayString(for: .pinClipboard)
        let restoreKey = HotKeyManager.shared.displayString(for: .restorePin)

        captureMenuItem?.title = "区域截图 (\(capKey))"
        ocrMenuItem?.title = "截图识别文字 OCR (\(ocrKey))"
        pinClipboardMenuItem?.title = "贴剪贴板图片 / 文字 (\(pinKey))"
        restoreLatestPinMenuItem?.title = "恢复上一张贴图 (\(restoreKey))"
        statusItem.button?.toolTip = "PixSnap 截图与贴图 (\(capKey))"
    }

    public func updatePinCounts(total: Int, clickThroughCount: Int) {
        if total > 0 {
            closePinsMenuItem.title = "关闭所有贴图 (\(total))"
            closePinsMenuItem.isEnabled = true
        } else {
            closePinsMenuItem.title = "关闭所有贴图"
            closePinsMenuItem.isEnabled = false
        }

        if clickThroughCount > 0 {
            restoreClickThroughMenuItem.title = "恢复鼠标穿透贴图 (\(clickThroughCount))"
            restoreClickThroughMenuItem.isHidden = false
            restoreClickThroughMenuItem.isEnabled = true
        } else {
            restoreClickThroughMenuItem.isHidden = true
        }
    }

    public func updatePinHistory(_ records: [ClosedPinRecord]) {
        let hasHistory = !records.isEmpty
        restoreLatestPinMenuItem.isEnabled = hasHistory
        recentPinsMenuItem.isEnabled = hasHistory
        recentPinsMenuItem.title = hasHistory ? "最近关闭的贴图 (\(records.count))" : "最近关闭的贴图"

        recentPinsSubmenu.removeAllItems()
        if records.isEmpty {
            let emptyItem = NSMenuItem(title: "暂无关闭记录", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            recentPinsSubmenu.addItem(emptyItem)
            return
        }

        for (index, record) in records.enumerated() {
            let prefix = index == 0 ? "最新 · " : "#\(index + 1) · "
            let item = NSMenuItem(
                title: "\(prefix)\(record.menuTitle)",
                action: #selector(restoreSpecificPinClicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.image = record.thumbnail
            item.representedObject = record.id
            recentPinsSubmenu.addItem(item)
        }

        recentPinsSubmenu.addItem(NSMenuItem.separator())
        let clearItem = NSMenuItem(title: "清空贴图历史", action: #selector(clearHistoryClicked), keyEquivalent: "")
        clearItem.target = self
        clearItem.image = menuIcon("trash")
        recentPinsSubmenu.addItem(clearItem)
    }

    @objc private func captureClicked() { onCaptureRequested?() }
    @objc private func ocrCaptureClicked() { onOCRCaptureRequested?() }
    @objc private func pinClipboardClicked() { onPinClipboardRequested?() }
    @objc private func restoreLatestPinClicked() { onRestoreLatestPinRequested?() }
    @objc private func restoreSpecificPinClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onRestoreSpecificPinRequested?(id)
    }
    @objc private func clearHistoryClicked() { onClearPinHistoryRequested?() }
    @objc private func closePinsClicked() { onCloseAllPinsRequested?() }
    @objc private func restoreClickThroughClicked() { onRestoreClickThroughRequested?() }
    @objc private func preferencesClicked() { onPreferencesRequested?() }

    @objc private func aboutClicked() {
        let capKey = HotKeyManager.shared.displayString(for: .capture)
        let pinKey = HotKeyManager.shared.displayString(for: .pinClipboard)
        let ocrKey = HotKeyManager.shared.displayString(for: .ocrCapture)
        let restoreKey = HotKeyManager.shared.displayString(for: .restorePin)

        let alert = NSAlert()
        alert.messageText = "PixSnap 2.0"
        alert.informativeText = """
        原生 macOS 高性能截图、多屏智能吸附、丰富标注、置顶贴图与离线 OCR / 二维码识别工具。

        当前全局快捷键：
        • 区域截图：\(capKey)
        • 贴剪贴板：\(pinKey)
        • 快速 OCR：\(ocrKey)
        • 恢复关闭的贴图：\(restoreKey)
        """
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    @objc private func quitClicked() {
        NSApplication.shared.terminate(nil)
    }
}
