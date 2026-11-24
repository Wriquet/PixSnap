import Cocoa
import Carbon

final class ShortcutRecordButton: NSButton {
    let actionType: HotKeyAction
    var isRecording: Bool = false {
        didSet {
            updateButtonTitle()
            needsDisplay = true
        }
    }

    var onShortcutRecorded: ((HotKeyAction, UInt32, UInt32, String) -> Void)?
    var onInvalidShortcut: ((String) -> Void)?
    var onShortcutCleared: ((HotKeyAction) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    init(action: HotKeyAction) {
        self.actionType = action
        super.init(frame: NSRect(x: 0, y: 0, width: 190, height: 28))
        self.bezelStyle = .rounded
        self.wantsLayer = true
        self.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        updateButtonTitle()
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateButtonTitle() {
        if isRecording {
            title = "按下快捷键 (Esc 取消)..."
            contentTintColor = .systemBlue
        } else {
            title = HotKeyManager.shared.displayString(for: actionType)
            contentTintColor = nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        if !isRecording {
            isRecording = true
            window?.makeFirstResponder(self)
        } else {
            isRecording = false
        }
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        let keyCode = event.keyCode
        if keyCode == 53 { // Esc cancels
            isRecording = false
            return
        }

        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])

        // Backspace/Delete with no modifiers clears optional shortcuts
        if (keyCode == 51 || keyCode == 117) && flags.isEmpty && actionType != .capture {
            isRecording = false
            onShortcutCleared?(actionType)
            return
        }

        guard HotKeyManager.isValidGlobalShortcut(keyCode: keyCode, modifiers: flags) else {
            onInvalidShortcut?("请包含 ⌘ / ⌥ / ⌃ 修饰键，或使用 F1~F12 功能键，避免影响日常打字")
            return
        }

        var carbonMods: UInt32 = 0
        if flags.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        if flags.contains(.option) { carbonMods |= UInt32(optionKey) }
        if flags.contains(.control) { carbonMods |= UInt32(controlKey) }

        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }

        parts.append(formatKeyName(keyCode: keyCode, characters: event.charactersIgnoringModifiers))
        let displayStr = parts.joined(separator: " + ")

        isRecording = false
        onShortcutRecorded?(actionType, UInt32(keyCode), carbonMods, displayStr)
    }

    private func formatKeyName(keyCode: UInt16, characters: String?) -> String {
        switch keyCode {
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            if let char = characters?.uppercased(), !char.isEmpty {
                return char
            }
            return "Key(\(keyCode))"
        }
    }
}

public final class PreferencesWindow: NSWindow {
    public var onPinAppearanceSettingsChanged: (() -> Void)?

    private let tabView = NSTabView()
    private var recorderButtons: [HotKeyAction: ShortcutRecordButton] = [:]
    private let shortcutStatusLabel = NSTextField(labelWithString: "")

    // General controls
    private let launchAtLoginCheck = NSButton(checkboxWithTitle: "开机自动启动 PixSnap", target: nil, action: nil)
    private let soundCheck = NSButton(checkboxWithTitle: "复制 / 保存完成时播放轻提示音", target: nil, action: nil)
    private let autoCopyOnSaveCheck = NSButton(checkboxWithTitle: "快速保存时同时复制到剪贴板", target: nil, action: nil)
    private let saveDirLabel = NSTextField(labelWithString: "")
    private let formatPopup = NSPopUpButton()

    // Capture & Pin controls
    private let magnifierCheck = NSButton(checkboxWithTitle: "截图悬停时显示 15×15 像素放大镜与取色器", target: nil, action: nil)
    private let windowDetectCheck = NSButton(checkboxWithTitle: "自动探测前台应用窗口边界吸附", target: nil, action: nil)
    private let colorFormatPopup = NSPopUpButton()
    private let pinAnchorPopup = NSPopUpButton()
    private let pinBorderCheck = NSButton(checkboxWithTitle: "贴图显示细边框（浅色截图置顶时更易辨识）", target: nil, action: nil)
    private let pinSpacesCheck = NSButton(checkboxWithTitle: "贴图跨桌面空间与全屏应用持续置顶", target: nil, action: nil)

    // Corner customization controls (Selection, Rect Annotation, Pin Border)
    private let selectionCornerSeg = NSSegmentedControl(labels: ["直角", "圆角"], trackingMode: .selectOne, target: nil, action: nil)
    private let selectionRadiusSlider = NSSlider(value: 8, minValue: 2, maxValue: 24, target: nil, action: nil)
    private let selectionRadiusLabel = NSTextField(labelWithString: "0 px")

    private let rectCornerSeg = NSSegmentedControl(labels: ["直角", "圆角"], trackingMode: .selectOne, target: nil, action: nil)
    private let rectRadiusSlider = NSSlider(value: 6, minValue: 2, maxValue: 20, target: nil, action: nil)
    private let rectRadiusLabel = NSTextField(labelWithString: "0 px")

    private let pinCornerSeg = NSSegmentedControl(labels: ["直角", "圆角"], trackingMode: .selectOne, target: nil, action: nil)
    private let pinRadiusSlider = NSSlider(value: 8, minValue: 2, maxValue: 24, target: nil, action: nil)
    private let pinRadiusLabel = NSTextField(labelWithString: "0 px")

    public init() {
        let frame = NSRect(x: 0, y: 0, width: 540, height: 450)
        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.title = "PixSnap 偏好设置"
        self.isReleasedWhenClosed = false
        self.level = .floating
        self.center()

        setupUI()
        refreshControlStates()
    }

    public func refreshControlStates() {
        let s = AppSettings.shared
        launchAtLoginCheck.state = s.isLaunchAtLoginEnabled ? .on : .off
        soundCheck.state = s.playCaptureSound ? .on : .off
        autoCopyOnSaveCheck.state = s.autoCopyOnSave ? .on : .off
        saveDirLabel.stringValue = s.saveDirectoryURL.path
        formatPopup.selectItem(at: SaveImageFormat.allCases.firstIndex(of: s.saveFormat) ?? 0)

        magnifierCheck.state = s.showMagnifier ? .on : .off
        windowDetectCheck.state = s.enableWindowDetection ? .on : .off
        colorFormatPopup.selectItem(at: ColorCopyFormat.allCases.firstIndex(of: s.colorCopyFormat) ?? 0)
        pinAnchorPopup.selectItem(at: PinZoomAnchorMode.allCases.firstIndex(of: s.pinZoomAnchorMode) ?? 0)
        pinBorderCheck.state = s.pinShowBorder ? .on : .off
        pinSpacesCheck.state = s.pinStayAcrossSpaces ? .on : .off

        selectionCornerSeg.selectedSegment = s.selectionUseRoundedCorners ? 1 : 0
        selectionRadiusSlider.doubleValue = Double(s.selectionCornerRadius)
        selectionRadiusSlider.isEnabled = s.selectionUseRoundedCorners
        selectionRadiusLabel.stringValue = s.selectionUseRoundedCorners ? "\(Int(round(s.selectionCornerRadius))) px" : "直角"

        rectCornerSeg.selectedSegment = s.rectAnnotationRounded ? 1 : 0
        rectRadiusSlider.doubleValue = Double(s.rectAnnotationCornerRadius)
        rectRadiusSlider.isEnabled = s.rectAnnotationRounded
        rectRadiusLabel.stringValue = s.rectAnnotationRounded ? "\(Int(round(s.rectAnnotationCornerRadius))) px" : "直角"

        pinCornerSeg.selectedSegment = s.pinUseRoundedCorners ? 1 : 0
        pinRadiusSlider.doubleValue = Double(s.pinCornerRadius)
        pinRadiusSlider.isEnabled = s.pinUseRoundedCorners
        pinRadiusLabel.stringValue = s.pinUseRoundedCorners ? "\(Int(round(s.pinCornerRadius))) px" : "直角"

        for btn in recorderButtons.values {
            btn.updateButtonTitle()
        }
    }

    private func setupUI() {
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))

        tabView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            tabView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            tabView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            tabView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])

        let generalItem = NSTabViewItem(identifier: "general")
        generalItem.label = "通用与保存"
        generalItem.view = buildGeneralTab()
        tabView.addTabViewItem(generalItem)

        let shortcutItem = NSTabViewItem(identifier: "shortcuts")
        shortcutItem.label = "全局快捷键"
        shortcutItem.view = buildShortcutsTab()
        tabView.addTabViewItem(shortcutItem)

        let capturePinItem = NSTabViewItem(identifier: "capturePin")
        capturePinItem.label = "截图与贴图"
        capturePinItem.view = buildCapturePinTab()
        tabView.addTabViewItem(capturePinItem)

        self.contentView = container
    }

    // MARK: - Tab 1: General

    private func buildGeneralTab() -> NSView {
        let stack = makeTabStack()

        launchAtLoginCheck.target = self
        launchAtLoginCheck.action = #selector(launchAtLoginToggled)
        stack.addArrangedSubview(launchAtLoginCheck)

        soundCheck.target = self
        soundCheck.action = #selector(soundToggled)
        stack.addArrangedSubview(soundCheck)

        autoCopyOnSaveCheck.target = self
        autoCopyOnSaveCheck.action = #selector(autoCopyOnSaveToggled)
        stack.addArrangedSubview(autoCopyOnSaveCheck)

        stack.addArrangedSubview(makeDivider())

        // Save folder row
        let dirHeader = NSTextField(labelWithString: "快速保存默认目录 (⌘S)：")
        dirHeader.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        stack.addArrangedSubview(dirHeader)

        let dirRow = NSStackView()
        dirRow.orientation = .horizontal
        dirRow.spacing = 8
        dirRow.alignment = .centerY

        saveDirLabel.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        saveDirLabel.textColor = .secondaryLabelColor
        saveDirLabel.lineBreakMode = .byTruncatingMiddle
        saveDirLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dirRow.addArrangedSubview(saveDirLabel)

        let chooseBtn = NSButton(title: "选择...", target: self, action: #selector(chooseSaveDirectory))
        chooseBtn.bezelStyle = .rounded
        dirRow.addArrangedSubview(chooseBtn)

        let revealBtn = NSButton(title: "打开", target: self, action: #selector(revealSaveDirectory))
        revealBtn.bezelStyle = .rounded
        dirRow.addArrangedSubview(revealBtn)

        stack.addArrangedSubview(dirRow)
        dirRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36).isActive = true

        // Save format row
        let fmtRow = NSStackView()
        fmtRow.orientation = .horizontal
        fmtRow.spacing = 10
        fmtRow.alignment = .centerY

        let fmtLabel = NSTextField(labelWithString: "默认保存格式：")
        fmtLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        fmtRow.addArrangedSubview(fmtLabel)

        for fmt in SaveImageFormat.allCases {
            formatPopup.addItem(withTitle: fmt.displayName)
        }
        formatPopup.target = self
        formatPopup.action = #selector(saveFormatChanged)
        fmtRow.addArrangedSubview(formatPopup)
        stack.addArrangedSubview(fmtRow)

        return wrapInContainer(stack)
    }

    // MARK: - Tab 2: Shortcuts

    private func buildShortcutsTab() -> NSView {
        let stack = makeTabStack()

        let intro = NSTextField(labelWithString: "点击右侧录制框并按下组合键，设置后系统全局立即生效。")
        intro.font = NSFont.systemFont(ofSize: 12)
        intro.textColor = .secondaryLabelColor
        stack.addArrangedSubview(intro)

        for action in HotKeyAction.allCases {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 10
            row.alignment = .centerY

            let titleLbl = NSTextField(labelWithString: "\(action.title)：")
            titleLbl.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            titleLbl.alignment = .right
            titleLbl.widthAnchor.constraint(equalToConstant: 145).isActive = true
            row.addArrangedSubview(titleLbl)

            let recBtn = ShortcutRecordButton(action: action)
            recBtn.widthAnchor.constraint(equalToConstant: 195).isActive = true
            recBtn.heightAnchor.constraint(equalToConstant: 28).isActive = true
            recBtn.onShortcutRecorded = { [weak self] act, kc, mods, disp in
                self?.handleShortcutRecorded(action: act, keyCode: kc, modifiers: mods, display: disp)
            }
            recBtn.onInvalidShortcut = { [weak self] msg in
                self?.showShortcutStatus("⚠️ \(msg)", isError: true)
            }
            recBtn.onShortcutCleared = { [weak self] act in
                HotKeyManager.shared.clearHotKey(action: act)
                self?.recorderButtons[act]?.updateButtonTitle()
                self?.showShortcutStatus("已清除「\(act.title)」快捷键", isError: false)
            }
            recorderButtons[action] = recBtn
            row.addArrangedSubview(recBtn)

            if action != .capture {
                let clearBtn = NSButton(title: "清除", target: self, action: #selector(clearShortcutClicked(_:)))
                clearBtn.tag = Int(action.rawValue)
                clearBtn.bezelStyle = .rounded
                clearBtn.controlSize = .small
                row.addArrangedSubview(clearBtn)
            }

            stack.addArrangedSubview(row)
        }

        shortcutStatusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        shortcutStatusLabel.lineBreakMode = .byWordWrapping
        shortcutStatusLabel.preferredMaxLayoutWidth = 440
        stack.addArrangedSubview(shortcutStatusLabel)

        let footerRow = NSStackView()
        footerRow.orientation = .horizontal
        footerRow.spacing = 10
        let resetBtn = NSButton(title: "恢复全部默认快捷键", target: self, action: #selector(resetAllShortcuts))
        resetBtn.bezelStyle = .rounded
        footerRow.addArrangedSubview(resetBtn)
        stack.addArrangedSubview(footerRow)

        let tip = NSTextField(wrappingLabelWithString: "• 为避免影响日常输入，普通字母/数字键必须搭配 ⌘ / ⌥ / ⌃ 之一；F1 ~ F12 可单键绑定。\n• 若快捷键已被系统或其他软件占用，将自动保留原设置并提示冲突。")
        tip.font = NSFont.systemFont(ofSize: 11)
        tip.textColor = .secondaryLabelColor
        tip.preferredMaxLayoutWidth = 440
        stack.addArrangedSubview(tip)

        return wrapInContainer(stack)
    }

    // MARK: - Tab 3: Capture & Pin

    private func buildCapturePinTab() -> NSView {
        let stack = makeTabStack()

        magnifierCheck.target = self
        magnifierCheck.action = #selector(magnifierToggled)
        stack.addArrangedSubview(magnifierCheck)

        windowDetectCheck.target = self
        windowDetectCheck.action = #selector(windowDetectToggled)
        stack.addArrangedSubview(windowDetectCheck)

        let colorRow = NSStackView()
        colorRow.orientation = .horizontal
        colorRow.spacing = 10
        colorRow.alignment = .centerY
        let colorLbl = NSTextField(labelWithString: "默认取色格式 (C 复制 / Tab 切换)：")
        colorLbl.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        colorRow.addArrangedSubview(colorLbl)
        for fmt in ColorCopyFormat.allCases {
            colorFormatPopup.addItem(withTitle: fmt.displayName)
        }
        colorFormatPopup.target = self
        colorFormatPopup.action = #selector(colorFormatChanged)
        colorRow.addArrangedSubview(colorFormatPopup)
        stack.addArrangedSubview(colorRow)

        stack.addArrangedSubview(makeDivider())

        // Corner customization rows (Selection, Rect Annotation, Pin Window)
        stack.addArrangedSubview(makeCornerControlRow(
            title: "框选边角 (按 R 切换)：",
            segmented: selectionCornerSeg,
            segAction: #selector(selectionCornerStyleChanged),
            slider: selectionRadiusSlider,
            sliderAction: #selector(selectionRadiusChanged),
            valueLabel: selectionRadiusLabel
        ))

        stack.addArrangedSubview(makeCornerControlRow(
            title: "矩形标注边角：",
            segmented: rectCornerSeg,
            segAction: #selector(rectCornerStyleChanged),
            slider: rectRadiusSlider,
            sliderAction: #selector(rectRadiusChanged),
            valueLabel: rectRadiusLabel
        ))

        stack.addArrangedSubview(makeCornerControlRow(
            title: "贴图边框边角：",
            segmented: pinCornerSeg,
            segAction: #selector(pinCornerStyleChanged),
            slider: pinRadiusSlider,
            sliderAction: #selector(pinRadiusChanged),
            valueLabel: pinRadiusLabel
        ))

        stack.addArrangedSubview(makeDivider())

        let pinAnchorRow = NSStackView()
        pinAnchorRow.orientation = .horizontal
        pinAnchorRow.spacing = 10
        pinAnchorRow.alignment = .centerY
        let anchorLbl = NSTextField(labelWithString: "贴图滚轮缩放锚点：")
        anchorLbl.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        pinAnchorRow.addArrangedSubview(anchorLbl)
        for mode in PinZoomAnchorMode.allCases {
            pinAnchorPopup.addItem(withTitle: mode.displayName)
        }
        pinAnchorPopup.target = self
        pinAnchorPopup.action = #selector(pinAnchorChanged)
        pinAnchorRow.addArrangedSubview(pinAnchorPopup)
        stack.addArrangedSubview(pinAnchorRow)

        pinBorderCheck.target = self
        pinBorderCheck.action = #selector(pinBorderToggled)
        stack.addArrangedSubview(pinBorderCheck)

        pinSpacesCheck.target = self
        pinSpacesCheck.action = #selector(pinSpacesToggled)
        stack.addArrangedSubview(pinSpacesCheck)

        return wrapInContainer(stack)
    }

    // MARK: - Helpers

    private func makeTabStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func wrapInContainer(_ stack: NSStackView) -> NSView {
        let wrapper = NSView()
        wrapper.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor)
        ])
        return wrapper
    }

    private func makeCornerControlRow(
        title: String,
        segmented: NSSegmentedControl,
        segAction: Selector,
        slider: NSSlider,
        sliderAction: Selector,
        valueLabel: NSTextField
    ) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY

        let lbl = NSTextField(labelWithString: title)
        lbl.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        lbl.alignment = .right
        lbl.widthAnchor.constraint(equalToConstant: 145).isActive = true
        row.addArrangedSubview(lbl)

        segmented.target = self
        segmented.action = segAction
        segmented.segmentStyle = .rounded
        segmented.widthAnchor.constraint(equalToConstant: 108).isActive = true
        row.addArrangedSubview(segmented)

        slider.target = self
        slider.action = sliderAction
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 135).isActive = true
        row.addArrangedSubview(slider)

        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.widthAnchor.constraint(equalToConstant: 42).isActive = true
        row.addArrangedSubview(valueLabel)

        return row
    }

    private func makeDivider() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: 468).isActive = true
        return line
    }

    // MARK: - Actions

    @objc private func launchAtLoginToggled() {
        let desired = (launchAtLoginCheck.state == .on)
        let ok = AppSettings.shared.setLaunchAtLogin(desired)
        if !ok {
            launchAtLoginCheck.state = AppSettings.shared.isLaunchAtLoginEnabled ? .on : .off
            ToastHUD.shared.show(
                "请在「系统设置 -> 通用 -> 登录项」中允许 PixSnap",
                symbolName: "gearshape.fill",
                accentColor: .systemOrange,
                duration: 2.5
            )
        }
    }

    @objc private func soundToggled() {
        AppSettings.shared.playCaptureSound = (soundCheck.state == .on)
    }

    @objc private func autoCopyOnSaveToggled() {
        AppSettings.shared.autoCopyOnSave = (autoCopyOnSaveCheck.state == .on)
    }

    @objc private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = AppSettings.shared.saveDirectoryURL
        panel.beginSheetModal(for: self) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            AppSettings.shared.saveDirectoryURL = url
            self?.saveDirLabel.stringValue = url.path
        }
    }

    @objc private func revealSaveDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([AppSettings.shared.saveDirectoryURL])
    }

    @objc private func saveFormatChanged() {
        let idx = formatPopup.indexOfSelectedItem
        if idx >= 0 && idx < SaveImageFormat.allCases.count {
            AppSettings.shared.saveFormat = SaveImageFormat.allCases[idx]
        }
    }

    private func handleShortcutRecorded(action: HotKeyAction, keyCode: UInt32, modifiers: UInt32, display: String) {
        let success = HotKeyManager.shared.updateHotKey(
            action: action,
            keyCode: keyCode,
            modifiers: modifiers,
            displayString: display
        )
        recorderButtons[action]?.updateButtonTitle()
        if success {
            showShortcutStatus("✅ 「\(action.title)」已生效：\(display)", isError: false)
        } else {
            showShortcutStatus("❌ 注册失败：\(display) 可能与系统或其他快捷键冲突，已保留原设置", isError: true)
        }
    }

    @objc private func clearShortcutClicked(_ sender: NSButton) {
        guard let action = HotKeyAction(rawValue: UInt32(sender.tag)) else { return }
        HotKeyManager.shared.clearHotKey(action: action)
        recorderButtons[action]?.updateButtonTitle()
        showShortcutStatus("已清除「\(action.title)」快捷键", isError: false)
    }

    @objc private func resetAllShortcuts() {
        HotKeyManager.shared.resetAllToDefault()
        for btn in recorderButtons.values {
            btn.updateButtonTitle()
        }
        showShortcutStatus("✅ 已恢复全部默认快捷键", isError: false)
    }

    private func showShortcutStatus(_ msg: String, isError: Bool) {
        shortcutStatusLabel.textColor = isError ? .systemRed : .systemGreen
        shortcutStatusLabel.stringValue = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            if self?.shortcutStatusLabel.stringValue == msg {
                self?.shortcutStatusLabel.stringValue = ""
            }
        }
    }

    @objc private func magnifierToggled() {
        AppSettings.shared.showMagnifier = (magnifierCheck.state == .on)
    }

    @objc private func windowDetectToggled() {
        AppSettings.shared.enableWindowDetection = (windowDetectCheck.state == .on)
    }

    @objc private func colorFormatChanged() {
        let idx = colorFormatPopup.indexOfSelectedItem
        if idx >= 0 && idx < ColorCopyFormat.allCases.count {
            AppSettings.shared.colorCopyFormat = ColorCopyFormat.allCases[idx]
        }
    }

    @objc private func pinAnchorChanged() {
        let idx = pinAnchorPopup.indexOfSelectedItem
        if idx >= 0 && idx < PinZoomAnchorMode.allCases.count {
            AppSettings.shared.pinZoomAnchorMode = PinZoomAnchorMode.allCases[idx]
        }
    }

    @objc private func pinBorderToggled() {
        AppSettings.shared.pinShowBorder = (pinBorderCheck.state == .on)
        onPinAppearanceSettingsChanged?()
    }

    @objc private func pinSpacesToggled() {
        AppSettings.shared.pinStayAcrossSpaces = (pinSpacesCheck.state == .on)
        onPinAppearanceSettingsChanged?()
    }

    @objc private func selectionCornerStyleChanged() {
        let rounded = (selectionCornerSeg.selectedSegment == 1)
        AppSettings.shared.selectionUseRoundedCorners = rounded
        selectionRadiusSlider.isEnabled = rounded
        selectionRadiusLabel.stringValue = rounded ? "\(Int(round(AppSettings.shared.selectionCornerRadius))) px" : "直角"
    }

    @objc private func selectionRadiusChanged() {
        let val = round(selectionRadiusSlider.doubleValue)
        AppSettings.shared.selectionCornerRadius = CGFloat(val)
        selectionRadiusLabel.stringValue = "\(Int(val)) px"
    }

    @objc private func rectCornerStyleChanged() {
        let rounded = (rectCornerSeg.selectedSegment == 1)
        AppSettings.shared.rectAnnotationRounded = rounded
        rectRadiusSlider.isEnabled = rounded
        rectRadiusLabel.stringValue = rounded ? "\(Int(round(AppSettings.shared.rectAnnotationCornerRadius))) px" : "直角"
    }

    @objc private func rectRadiusChanged() {
        let val = round(rectRadiusSlider.doubleValue)
        AppSettings.shared.rectAnnotationCornerRadius = CGFloat(val)
        rectRadiusLabel.stringValue = "\(Int(val)) px"
    }

    @objc private func pinCornerStyleChanged() {
        let rounded = (pinCornerSeg.selectedSegment == 1)
        AppSettings.shared.pinUseRoundedCorners = rounded
        pinRadiusSlider.isEnabled = rounded
        pinRadiusLabel.stringValue = rounded ? "\(Int(round(AppSettings.shared.pinCornerRadius))) px" : "直角"
        onPinAppearanceSettingsChanged?()
    }

    @objc private func pinRadiusChanged() {
        let val = round(pinRadiusSlider.doubleValue)
        AppSettings.shared.pinCornerRadius = CGFloat(val)
        pinRadiusLabel.stringValue = "\(Int(val)) px"
        onPinAppearanceSettingsChanged?()
    }
}
