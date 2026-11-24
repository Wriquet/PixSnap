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
            if let img = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "PixSnap") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "PixSnap"
            }
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        captureMenuItem = NSMenuItem(title: "", action: #selector(captureClicked), keyEquivalent: "")
        captureMenuItem.target = self
        captureMenuItem.image = menuIcon("camera.viewfinder")
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
