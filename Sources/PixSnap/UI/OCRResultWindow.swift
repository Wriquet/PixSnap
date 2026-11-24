import Cocoa

@MainActor
public final class OCRWindowManager: NSObject, NSWindowDelegate {
    public static let shared = OCRWindowManager()
    private var openWindows: [OCRResultWindow] = []

    private override init() {
        super.init()
    }

    public func present(result: OCREngine.OCRResult) {
        let win = OCRResultWindow(result: result)
        win.delegate = self
        openWindows.append(win)
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        if let win = notification.object as? OCRResultWindow {
            openWindows.removeAll { $0 === win }
        }
    }
}

public final class OCRResultWindow: NSPanel, NSTextViewDelegate {
    private let textView = NSTextView()
    private let countLabel = NSTextField(labelWithString: "")
    private let qrCodes: [String]

    public init(result: OCREngine.OCRResult) {
        self.qrCodes = result.qrCodes
        let height: CGFloat = result.qrCodes.isEmpty ? 340 : 400
        let frame = NSRect(x: 0, y: 0, width: 520, height: height)
        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.title = "文字识别结果 (已自动复制)"
        self.minSize = NSSize(width: 380, height: 240)
        self.level = .floating
        self.isReleasedWhenClosed = false
        self.appearance = NSAppearance(named: .darkAqua)

        let combinedCopyText: String
        if !result.fullText.isEmpty {
            combinedCopyText = result.fullText
        } else if let firstQR = result.qrCodes.first {
            combinedCopyText = firstQR
        } else {
            combinedCopyText = ""
        }

        setupUI(text: result.fullText)

        if !combinedCopyText.isEmpty {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(combinedCopyText, forType: .string)
        }
    }

    private func setupUI(text: String) {
        let root = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.appearance = NSAppearance(named: .darkAqua)

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.spacing = 10
        mainStack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: root.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        // Optional QR Code / Barcode Banner
        if let firstQR = qrCodes.first {
            let qrBox = NSBox()
            qrBox.boxType = .custom
            qrBox.cornerRadius = 8
            qrBox.borderWidth = 1
            qrBox.borderColor = NSColor.systemBlue.withAlphaComponent(0.45)
            qrBox.fillColor = NSColor.systemBlue.withAlphaComponent(0.14)
            qrBox.translatesAutoresizingMaskIntoConstraints = false

            let qrRow = NSStackView()
            qrRow.orientation = .horizontal
            qrRow.alignment = .centerY
            qrRow.spacing = 8
            qrRow.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
            qrRow.translatesAutoresizingMaskIntoConstraints = false
            qrBox.addSubview(qrRow)

            NSLayoutConstraint.activate([
                qrRow.leadingAnchor.constraint(equalTo: qrBox.leadingAnchor),
                qrRow.trailingAnchor.constraint(equalTo: qrBox.trailingAnchor),
                qrRow.topAnchor.constraint(equalTo: qrBox.topAnchor),
                qrRow.bottomAnchor.constraint(equalTo: qrBox.bottomAnchor)
            ])

            let qrLabel = NSTextField(labelWithString: "二维码: \(firstQR)")
            qrLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            qrLabel.textColor = .white
            qrLabel.lineBreakMode = .byTruncatingMiddle
            qrLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            qrRow.addArrangedSubview(qrLabel)

            let copyQRBtn = NSButton(title: "复制", target: self, action: #selector(copyQRCode))
            copyQRBtn.bezelStyle = .rounded
            copyQRBtn.controlSize = .small
            qrRow.addArrangedSubview(copyQRBtn)

            if let url = URL(string: firstQR), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                let openBtn = NSButton(title: "打开链接", target: self, action: #selector(openQRLink))
                openBtn.bezelStyle = .rounded
                openBtn.controlSize = .small
                qrRow.addArrangedSubview(openBtn)
            }

            mainStack.addArrangedSubview(qrBox)
            qrBox.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -28).isActive = true
        }

        // Scrollable editable text area
        let scrollContainer = NSBox()
        scrollContainer.boxType = .custom
        scrollContainer.cornerRadius = 8
        scrollContainer.borderWidth = 1
        scrollContainer.borderColor = NSColor.white.withAlphaComponent(0.12)
        scrollContainer.fillColor = NSColor.black.withAlphaComponent(0.24)
        scrollContainer.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView.string = text.isEmpty && !qrCodes.isEmpty ? qrCodes.joined(separator: "\n") : text
        textView.font = NSFont.systemFont(ofSize: 13.5)
        textView.textColor = .white
        textView.insertionPointColor = .systemBlue
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.delegate = self
        scrollView.documentView = textView

        scrollContainer.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: scrollContainer.leadingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: scrollContainer.trailingAnchor, constant: -4),
            scrollView.topAnchor.constraint(equalTo: scrollContainer.topAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: scrollContainer.bottomAnchor, constant: -4)
        ])

        mainStack.addArrangedSubview(scrollContainer)
        scrollContainer.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -28).isActive = true

        // Bottom bar
        let bottomBar = NSStackView()
        bottomBar.orientation = .horizontal
        bottomBar.spacing = 8
        bottomBar.alignment = .centerY
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        countLabel.textColor = NSColor.white.withAlphaComponent(0.65)
        countLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        updateCountLabel()
        bottomBar.addArrangedSubview(countLabel)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bottomBar.addArrangedSubview(spacer)

        let joinBtn = NSButton(title: "合并换行", target: self, action: #selector(joinLines))
        joinBtn.bezelStyle = .rounded
        joinBtn.toolTip = "去除段落中的多余换行符"
        bottomBar.addArrangedSubview(joinBtn)

        let copyBtn = NSButton(title: "复制全部", target: self, action: #selector(copyAll))
        copyBtn.bezelStyle = .rounded
        copyBtn.keyEquivalent = "\r"
        bottomBar.addArrangedSubview(copyBtn)

        let closeBtn = NSButton(title: "关闭", target: self, action: #selector(closeWindow))
        closeBtn.bezelStyle = .rounded
        bottomBar.addArrangedSubview(closeBtn)

        mainStack.addArrangedSubview(bottomBar)
        bottomBar.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -28).isActive = true
        bottomBar.heightAnchor.constraint(equalToConstant: 28).isActive = true

        self.contentView = root
    }

    private func updateCountLabel() {
        let str = textView.string
        let lineCount = str.isEmpty ? 0 : str.components(separatedBy: .newlines).count
        countLabel.stringValue = "\(str.count) 字 · \(lineCount) 行"
    }

    public func textDidChange(_ notification: Notification) {
        updateCountLabel()
    }

    public override func cancelOperation(_ sender: Any?) {
        closeWindow()
    }

    @objc private func joinLines() {
        let lines = textView.string
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // Join CJK seamlessly without extra spaces, insert space around Latin/digit boundaries
        var joined = ""
        for line in lines {
            if joined.isEmpty {
                joined = line
            } else if let prevLast = joined.last, let nextFirst = line.first,
                      prevLast.isASCII && nextFirst.isASCII {
                joined += " " + line
            } else {
                joined += line
            }
        }
        textView.string = joined
        updateCountLabel()
    }

    @objc private func copyQRCode() {
        guard let first = qrCodes.first else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(first, forType: .string)
        ToastHUD.shared.show("已复制二维码内容", symbolName: "qrcode", accentColor: .systemBlue)
    }

    @objc private func openQRLink() {
        guard let first = qrCodes.first, let url = URL(string: first) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyAll() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(textView.string, forType: .string)
        self.title = "✅ 已复制到剪贴板"
        ToastHUD.shared.show("已复制 \(textView.string.count) 个字符", symbolName: "doc.on.clipboard.fill", accentColor: .systemGreen)
    }

    @objc private func closeWindow() {
        self.orderOut(nil)
        self.close()
    }
}
