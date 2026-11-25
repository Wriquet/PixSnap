import Cocoa
import Carbon
import VisionKit
import UniformTypeIdentifiers

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var activeOverlays: [OverlayWindow] = []
    private var activePins: [PinWindow] = []
    private lazy var pinHistory = PinHistoryStore(
        directoryURL: AppSettings.shared.pinHistoryDirectoryURL,
        maxCount: AppSettings.shared.pinHistoryLimit.rawValue
    )
    private var pinHistoryConfigObserver: NSObjectProtocol?
    private var preferencesWindow: PreferencesWindow?
    private var isStartingCapture: Bool = false

    public func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
        statusBarController.onCaptureRequested = { [weak self] in
            self?.startCapture(autoOCR: false)
        }
        statusBarController.onOCRCaptureRequested = { [weak self] in
            self?.startCapture(autoOCR: true)
        }
        statusBarController.onPinClipboardRequested = { [weak self] in
            self?.pinFromClipboard()
        }
        statusBarController.onRestoreLatestPinRequested = { [weak self] in
            self?.restoreLatestClosedPin()
        }
        statusBarController.onRestoreSpecificPinRequested = { [weak self] id in
            self?.restoreClosedPin(id: id)
        }
        statusBarController.onOpenPinHistoryFolderRequested = { [weak self] in
            self?.openPinHistoryFolder()
        }
        statusBarController.onChoosePinHistoryFolderRequested = { [weak self] in
            self?.choosePinHistoryFolderFromMenu()
        }
        statusBarController.onMenuWillOpen = { [weak self] in
            guard let self else { return }
            self.pinHistory.reloadFromDisk()
            self.syncStatusBarPinState()
        }
        statusBarController.thumbnailProvider = { [weak self] record in
            self?.pinHistory.thumbnail(for: record)
        }
        statusBarController.onClearPinHistoryRequested = { [weak self] in
            self?.clearPinHistory()
        }
        statusBarController.onCloseAllPinsRequested = { [weak self] in
            self?.closeAllPins()
        }
        statusBarController.onRestoreClickThroughRequested = { [weak self] in
            self?.restoreAllClickThroughPins()
        }
        statusBarController.onPreferencesRequested = { [weak self] in
            self?.showPreferences()
        }

        HotKeyManager.shared.onHotKeysChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.statusBarController.refreshShortcutTitles()
            }
        }

        HotKeyManager.shared.onActionTriggered = { action in
            DispatchQueue.main.async {
                guard let delegate = NSApp.delegate as? AppDelegate else { return }
                switch action {
                case .capture:
                    delegate.startCapture(autoOCR: false)
                case .pinClipboard:
                    delegate.pinFromClipboard()
                case .ocrCapture:
                    delegate.startCapture(autoOCR: true)
                case .restorePin:
                    delegate.restoreLatestClosedPin()
                }
            }
        }
        HotKeyManager.shared.registerAll()

        pinHistoryConfigObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.pinHistoryConfigDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pinHistory.setDirectory(AppSettings.shared.pinHistoryDirectoryURL)
                self.pinHistory.setMaxCount(AppSettings.shared.pinHistoryLimit.rawValue)
                self.syncStatusBarPinState()
            }
        }
        syncStatusBarPinState()

        print("🚀 PixSnap 2.0 已成功启动并常驻菜单栏！")
        print("💡 区域截图：\(HotKeyManager.shared.displayString(for: .capture))")
        print("💡 贴剪贴板：\(HotKeyManager.shared.displayString(for: .pinClipboard))")
        print("💡 快速 OCR：\(HotKeyManager.shared.displayString(for: .ocrCapture))")
        print("💡 恢复贴图：\(HotKeyManager.shared.displayString(for: .restorePin))")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // Persist any still-open pins to the disk history folder so restarting never loses them
        if !activePins.isEmpty {
            for pin in activePins {
                if let extURL = pin.sourceExternalFileURL {
                    pinHistory.markExternalPinClosed(fileURL: extURL)
                } else {
                    pinHistory.push(pin.makeHistoryRecord())
                }
            }
        }
        pinHistory.flushPendingWrites()
        HotKeyManager.shared.unregisterAll()
    }

    // MARK: - Multi-Monitor Capture Flow

    public func startCapture(autoOCR: Bool = false) {
        guard activeOverlays.isEmpty, !isStartingCapture else { return }
        isStartingCapture = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isStartingCapture = false }

            do {
                let mouseLoc = NSEvent.mouseLocation
                let capturedScreens = try await ScreenCaptureManager.shared.captureAllScreens(
                    includeWindowDetection: AppSettings.shared.enableWindowDetection
                )

                var overlays: [OverlayWindow] = []
                var keyOverlay: OverlayWindow?

                for captured in capturedScreens {
                    let isMouseHere = captured.screenFrame.contains(mouseLoc)
                    let overlay = OverlayWindow(
                        captured: captured,
                        isInitialActiveScreen: isMouseHere,
                        autoOCRMode: autoOCR
                    )
                    wireOverlayCallbacks(overlay)
                    overlays.append(overlay)
                    if isMouseHere {
                        keyOverlay = overlay
                    }
                }

                // Fallback if mouse wasn't matched to any rect
                if keyOverlay == nil, let first = overlays.first {
                    keyOverlay = first
                }

                self.activeOverlays = overlays

                NSApp.activate(ignoringOtherApps: true)
                for overlay in overlays {
                    overlay.orderFrontRegardless()
                }
                keyOverlay?.makeKeyAndOrderFront(nil)
                keyOverlay?.makeFirstResponder(keyOverlay?.overlayView)
            } catch {
                presentScreenPermissionAlert(error: error)
            }
        }
    }

    private func wireOverlayCallbacks(_ overlay: OverlayWindow) {
        let view = overlay.overlayView

        view.onCloseAll = { [weak self] in
            self?.closeAllOverlays()
        }

        view.onBecameActiveScreen = { [weak self, weak overlay] in
            guard let self, let overlay else { return }
            for other in self.activeOverlays where other !== overlay {
                other.overlayView.deactivateHoverFromSiblingScreen()
            }
        }

        view.onSelectionStarted = { [weak self, weak overlay] in
            guard let self, let overlay else { return }
            for other in self.activeOverlays where other !== overlay {
                other.overlayView.deactivateHoverFromSiblingScreen()
            }
        }

        view.onPinRequested = { [weak self] image, globalOrigin, preAnalysis in
            self?.createPin(image: image, origin: globalOrigin, preAnalysis: preAnalysis)
        }

        view.onOCRRequested = { [weak self] cgImage in
            self?.runStandaloneOCR(on: cgImage)
        }

        view.onSaveAsRequested = { [weak self] cgImage, scale in
            self?.presentSaveAsPanel(cgImage: cgImage, scaleFactor: scale)
        }
    }

    private func closeAllOverlays() {
        let overlays = activeOverlays
        activeOverlays.removeAll()
        for overlay in overlays {
            overlay.closeOverlay()
        }
    }

    // MARK: - Save As & OCR (Always presented AFTER overlays close so nothing is buried!)

    private func presentSaveAsPanel(cgImage: CGImage, scaleFactor: CGFloat) {
        let settings = AppSettings.shared
        let format = settings.saveFormat
        let panel = NSSavePanel()
        panel.directoryURL = settings.saveDirectoryURL
        panel.allowedContentTypes = format == .jpeg ? [.jpeg, .png] : [.png, .jpeg]
        panel.nameFieldStringValue = ImageExporter.defaultFilename(format: format)

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let ext = url.pathExtension.lowercased()
            let actualFormat: SaveImageFormat = (ext == "jpg" || ext == "jpeg") ? .jpeg : .png
            guard let data = ImageExporter.encode(
                cgImage: cgImage,
                format: actualFormat,
                scaleFactor: scaleFactor,
                jpegQuality: settings.jpegQuality
            ) else { return }

            do {
                try data.write(to: url, options: .atomic)
                if settings.autoCopyOnSave {
                    let logicalSize = CGSize(
                        width: CGFloat(cgImage.width) / scaleFactor,
                        height: CGFloat(cgImage.height) / scaleFactor
                    )
                    ImageExporter.copyToPasteboard(cgImage: cgImage, logicalSize: logicalSize, scaleFactor: scaleFactor)
                }
                settings.playFeedbackSound()
                ToastHUD.shared.show(
                    "已保存 \(url.lastPathComponent)",
                    symbolName: "arrow.down.circle.fill",
                    accentColor: .systemBlue,
                    duration: 2.0
                )
            } catch {
                ToastHUD.shared.show(
                    "保存失败: \(error.localizedDescription)",
                    symbolName: "exclamationmark.triangle.fill",
                    accentColor: .systemRed,
                    duration: 2.5
                )
            }
        }
    }

    private func runStandaloneOCR(on cgImage: CGImage) {
        ToastHUD.shared.show("正在识别文字与二维码...", symbolName: "text.viewfinder", accentColor: .systemBlue, duration: 1.2)
        Task { @MainActor in
            do {
                let result = try await OCREngine.shared.recognizeText(from: cgImage)
                if result.fullText.isEmpty && result.qrCodes.isEmpty {
                    ToastHUD.shared.show("未检测到可识别的文字或二维码", symbolName: "exclamationmark.circle", accentColor: .systemOrange)
                } else {
                    AppSettings.shared.playFeedbackSound()
                    OCRWindowManager.shared.present(result: result)
                }
            } catch {
                ToastHUD.shared.show("文字识别失败: \(error.localizedDescription)", symbolName: "exclamationmark.triangle.fill", accentColor: .systemRed)
            }
        }
    }

    // MARK: - Pin Management (Leak-Free!)

    public func pinFromClipboard() {
        let targetScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let scale = targetScreen?.backingScaleFactor ?? 2.0

        guard let item = ImageExporter.readImageOrTextFromPasteboard(scaleFactor: scale) else {
            ToastHUD.shared.show("剪贴板暂无可贴图的图片或文字", symbolName: "clipboard", accentColor: .systemOrange)
            return
        }

        let mouse = NSEvent.mouseLocation
        var origin = CGPoint(
            x: round(mouse.x - item.image.size.width / 2.0),
            y: round(mouse.y - item.image.size.height / 2.0)
        )
        if let vis = targetScreen?.visibleFrame {
            origin.x = max(vis.minX + 16, min(vis.maxX - item.image.size.width - 16, origin.x))
            origin.y = max(vis.minY + 16, min(vis.maxY - item.image.size.height - 16, origin.y))
        }

        createPin(image: item.image, origin: origin, preAnalysis: nil)
        ToastHUD.shared.show(
            item.isTextCard ? "已将剪贴板文字置顶贴图" : "已将剪贴板图片置顶贴图",
            symbolName: "pin.fill",
            accentColor: .systemBlue,
            duration: 1.4
        )
    }

    private func createPin(image: NSImage, origin: CGPoint, preAnalysis: ImageAnalysis? = nil) {
        let pin = PinWindow(image: image, origin: origin, preAnalysis: preAnalysis)
        registerAndShowPin(pin)
    }

    private func registerAndShowPin(_ pin: PinWindow) {
        pin.onClosed = { [weak self] closedPin in
            guard let self else { return }
            if let extURL = closedPin.sourceExternalFileURL {
                self.pinHistory.markExternalPinClosed(fileURL: extURL)
            } else {
                self.pinHistory.push(closedPin.makeHistoryRecord())
            }
            self.activePins.removeAll { $0 === closedPin }
            self.syncStatusBarPinState()
        }
        pin.onClickThroughChanged = { [weak self] in
            self?.syncStatusBarPinState()
        }
        pin.onAppearanceChanged = { [weak self] in
            guard let self else { return }
            self.activePins.forEach { $0.applySettings() }
            self.preferencesWindow?.refreshControlStates()
        }
        pin.onRestorePreviousPinRequested = { [weak self] in
            self?.restoreLatestClosedPin()
        }
        activePins.append(pin)
        syncStatusBarPinState()

        DispatchQueue.main.async { [weak pin] in
            guard let pin, !pin.isClosed else { return }
            NSApp.activate(ignoringOtherApps: true)
            pin.makeKeyAndOrderFront(nil)
        }
    }

    public func restoreLatestClosedPin() {
        if pinHistory.isEmpty {
            pinHistory.reloadFromDisk()
        }
        guard let record = pinHistory.popLatest(),
              let loadedImage = pinHistory.loadImage(for: record) else {
            syncStatusBarPinState()
            ToastHUD.shared.show("历史文件夹中暂无可恢复的贴图", symbolName: "clock.arrow.circlepath", accentColor: .systemOrange, duration: 1.5)
            return
        }
        let pin = PinWindow(restoring: record, image: loadedImage)
        registerAndShowPin(pin)
        let remaining = pinHistory.count
        let msg = remaining > 0 ? "已恢复贴图（目录中还有 \(remaining) 张）" : "已恢复贴图"
        ToastHUD.shared.show(msg, symbolName: "arrow.uturn.backward.circle.fill", accentColor: .systemBlue, duration: 1.5)
    }

    public func restoreClosedPin(id: UUID) {
        guard let record = pinHistory.take(id: id),
              let loadedImage = pinHistory.loadImage(for: record) else {
            pinHistory.reloadFromDisk()
            syncStatusBarPinState()
            ToastHUD.shared.show("该贴图文件已不存在", symbolName: "exclamationmark.circle", accentColor: .systemOrange, duration: 1.4)
            return
        }
        let pin = PinWindow(restoring: record, image: loadedImage)
        registerAndShowPin(pin)
        ToastHUD.shared.show("已从历史目录恢复贴图", symbolName: "arrow.uturn.backward.circle.fill", accentColor: .systemBlue, duration: 1.4)
    }

    public func openPinHistoryFolder() {
        let dir = AppSettings.shared.pinHistoryDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    public func choosePinHistoryFolderFromMenu() {
        let panel = NSOpenPanel()
        panel.title = "选择贴图历史文件夹"
        panel.message = "关闭的贴图会自动保存至此文件夹（不占内存），也会读取目录中已有图片供随时恢复。"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = AppSettings.shared.pinHistoryDirectoryURL

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            AppSettings.shared.pinHistoryDirectoryURL = url
            pinHistory.setDirectory(url)
            syncStatusBarPinState()
            preferencesWindow?.refreshControlStates()
            let count = pinHistory.count
            let msg = count > 0 ? "已切换贴图目录，发现 \(count) 张可恢复图片" : "已切换贴图历史文件夹"
            ToastHUD.shared.show(msg, symbolName: "folder.fill", accentColor: .systemBlue, duration: 2.0)
        }
    }

    public func clearPinHistory() {
        pinHistory.clear()
        syncStatusBarPinState()
        ToastHUD.shared.show("已清空 PixSnap 贴图缓存（外部原图不受影响）", symbolName: "trash", accentColor: .systemGray, duration: 1.6)
    }

    public func closeAllPins() {
        let pins = activePins
        activePins.removeAll()
        for pin in pins {
            if let extURL = pin.sourceExternalFileURL {
                pinHistory.markExternalPinClosed(fileURL: extURL)
            } else {
                pinHistory.push(pin.makeHistoryRecord())
            }
            pin.onClosed = nil
            pin.closePin()
        }
        syncStatusBarPinState()
    }

    public func restoreAllClickThroughPins() {
        var restored = 0
        for pin in activePins where pin.isClickThrough {
            pin.disableClickThrough()
            restored += 1
        }
        syncStatusBarPinState()
        if restored > 0 {
            ToastHUD.shared.show("已恢复 \(restored) 个贴图的鼠标交互", symbolName: "hand.tap.fill", accentColor: .systemGreen)
        }
    }

    private func syncStatusBarPinState() {
        let clickThroughCount = activePins.filter(\.isClickThrough).count
        statusBarController.updatePinCounts(total: activePins.count, clickThroughCount: clickThroughCount)
        statusBarController.updatePinHistory(pinHistory.recentFirst, managedCount: pinHistory.managedCount)
    }

    // MARK: - Preferences & Permissions

    public func showPreferences() {
        if preferencesWindow == nil {
            let win = PreferencesWindow()
            win.onPinAppearanceSettingsChanged = { [weak self] in
                self?.activePins.forEach { $0.applySettings() }
            }
            preferencesWindow = win
        }
        preferencesWindow?.refreshControlStates()
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentScreenPermissionAlert(error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法捕获屏幕"
        alert.informativeText = "请确认已在「系统设置 -> 隐私与安全性 -> 屏幕录制与系统录音」中勾选允许 PixSnap。\n\n详细信息：\(error.localizedDescription)"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")

        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
