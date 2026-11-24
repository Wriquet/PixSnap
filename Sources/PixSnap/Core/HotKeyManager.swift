import Cocoa
import Carbon

public enum HotKeyAction: UInt32, CaseIterable, Sendable {
    case capture = 1
    case pinClipboard = 2
    case ocrCapture = 3
    case restorePin = 4

    public var title: String {
        switch self {
        case .capture: return "区域截图"
        case .pinClipboard: return "贴剪贴板图片 / 文字"
        case .ocrCapture: return "快速截图 OCR"
        case .restorePin: return "恢复关闭的贴图"
        }
    }

    public var storagePrefix: String {
        switch self {
        case .capture: return "pixsnap_hotkey"
        case .pinClipboard: return "pixsnap_hotkey_pinclip"
        case .ocrCapture: return "pixsnap_hotkey_ocr"
        case .restorePin: return "pixsnap_hotkey_restorepin"
        }
    }

    public var defaultConfig: HotKeyConfig? {
        switch self {
        case .capture:
            return HotKeyConfig(
                keyCode: 7, // X
                modifiers: UInt32(cmdKey | shiftKey),
                displayString: "⌘ + ⇧ + X"
            )
        case .pinClipboard:
            return HotKeyConfig(
                keyCode: 9, // V
                modifiers: UInt32(optionKey | shiftKey),
                displayString: "⌥ + ⇧ + V"
            )
        case .ocrCapture:
            return HotKeyConfig(
                keyCode: 31, // O
                modifiers: UInt32(optionKey | shiftKey),
                displayString: "⌥ + ⇧ + O"
            )
        case .restorePin:
            return HotKeyConfig(
                keyCode: 6, // Z
                modifiers: UInt32(optionKey | shiftKey),
                displayString: "⌥ + ⇧ + Z"
            )
        }
    }
}

public struct HotKeyConfig: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var displayString: String

    public init(keyCode: UInt32, modifiers: UInt32, displayString: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayString = displayString
    }

    public static let `default` = HotKeyAction.capture.defaultConfig!
}

public final class HotKeyManager: @unchecked Sendable {
    public static let shared = HotKeyManager()

    private static let signature: OSType = 0x50495853 // 'PIXS'

    private var hotKeyRefs: [HotKeyAction: EventHotKeyRef] = [:]
    private var configs: [HotKeyAction: HotKeyConfig] = [:]
    private var isHandlerInstalled: Bool = false

    public var onActionTriggered: (@Sendable (HotKeyAction) -> Void)?
    public var onHotKeysChanged: (() -> Void)?

    public init() {
        loadAllConfigs()
    }

    public func config(for action: HotKeyAction) -> HotKeyConfig? {
        configs[action]
    }

    public func displayString(for action: HotKeyAction) -> String {
        configs[action]?.displayString ?? "未设置"
    }

    public var currentConfig: HotKeyConfig {
        configs[.capture] ?? .default
    }

    private func loadAllConfigs() {
        let ud = UserDefaults.standard
        for action in HotKeyAction.allCases {
            let disabledKey = "\(action.storagePrefix)_disabled"
            if ud.bool(forKey: disabledKey) {
                configs[action] = nil
                continue
            }

            let kcKey = "\(action.storagePrefix)_keycode"
            let modKey = "\(action.storagePrefix)_modifiers"
            let dispKey = "\(action.storagePrefix)_display"

            if ud.object(forKey: kcKey) != nil {
                let kc = UInt32(ud.integer(forKey: kcKey))
                let mods = UInt32(ud.integer(forKey: modKey))
                let disp = ud.string(forKey: dispKey) ?? action.defaultConfig?.displayString ?? ""
                configs[action] = HotKeyConfig(keyCode: kc, modifiers: mods, displayString: disp)
            } else {
                configs[action] = action.defaultConfig
            }
        }
    }

    private func ensureHandlerInstalled() {
        guard !isHandlerInstalled else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, theEvent, _) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    theEvent,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if err == noErr, let action = HotKeyAction(rawValue: hotKeyID.id) {
                    HotKeyManager.shared.onActionTriggered?(action)
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
        isHandlerInstalled = true
    }

    public func registerAll() {
        for action in HotKeyAction.allCases {
            if let cfg = configs[action] {
                _ = register(action: action, config: cfg, persist: false)
            }
        }
    }

    /// Register a shortcut for the given action. Returns `true` if macOS Carbon accepted it without conflict.
    @discardableResult
    public func register(action: HotKeyAction, config: HotKeyConfig, persist: Bool = true) -> Bool {
        // Reject duplicate shortcut already used by another PixSnap action
        for (otherAction, otherConfig) in configs where otherAction != action {
            if otherConfig.keyCode == config.keyCode && otherConfig.modifiers == config.modifiers {
                return false
            }
        }

        ensureHandlerInstalled()

        // Temporarily unregister old binding for this action; restore if new registration fails
        let previousConfig = configs[action]
        unregister(action: action)

        var newRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        let status = RegisterEventHotKey(
            config.keyCode,
            config.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )

        if status == noErr, let ref = newRef {
            hotKeyRefs[action] = ref
            configs[action] = config
            if persist {
                saveConfig(config, for: action)
                onHotKeysChanged?()
            }
            return true
        } else {
            // Rollback previous hotkey if we had one
            if let prev = previousConfig {
                var rollbackRef: EventHotKeyRef?
                let rbStatus = RegisterEventHotKey(
                    prev.keyCode,
                    prev.modifiers,
                    hotKeyID,
                    GetApplicationEventTarget(),
                    0,
                    &rollbackRef
                )
                if rbStatus == noErr, let ref = rollbackRef {
                    hotKeyRefs[action] = ref
                    configs[action] = prev
                }
            }
            return false
        }
    }

    @discardableResult
    public func updateHotKey(action: HotKeyAction, keyCode: UInt32, modifiers: UInt32, displayString: String) -> Bool {
        let newConfig = HotKeyConfig(keyCode: keyCode, modifiers: modifiers, displayString: displayString)
        return register(action: action, config: newConfig, persist: true)
    }

    public func clearHotKey(action: HotKeyAction) {
        unregister(action: action)
        configs[action] = nil
        let ud = UserDefaults.standard
        ud.set(true, forKey: "\(action.storagePrefix)_disabled")
        onHotKeysChanged?()
    }

    public func resetAllToDefault() {
        let ud = UserDefaults.standard
        for action in HotKeyAction.allCases {
            ud.removeObject(forKey: "\(action.storagePrefix)_disabled")
            if let def = action.defaultConfig {
                _ = register(action: action, config: def, persist: true)
            }
        }
        onHotKeysChanged?()
    }

    private func saveConfig(_ config: HotKeyConfig, for action: HotKeyAction) {
        let ud = UserDefaults.standard
        ud.set(false, forKey: "\(action.storagePrefix)_disabled")
        ud.set(Int(config.keyCode), forKey: "\(action.storagePrefix)_keycode")
        ud.set(Int(config.modifiers), forKey: "\(action.storagePrefix)_modifiers")
        ud.set(config.displayString, forKey: "\(action.storagePrefix)_display")
    }

    public func unregister(action: HotKeyAction) {
        if let ref = hotKeyRefs.removeValue(forKey: action) {
            UnregisterEventHotKey(ref)
        }
    }

    public func unregisterAll() {
        for action in HotKeyAction.allCases {
            unregister(action: action)
        }
    }

    /// Validate that a key combination is safe for a global shortcut (F1–F19 allowed bare; other keys require a modifier)
    public static func isValidGlobalShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        let functionKeyCodes: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80]
        if functionKeyCodes.contains(keyCode) {
            return true
        }
        let cleanMods = modifiers.intersection([.command, .option, .control, .shift])
        // Disallow bare key or Shift-only on normal printable characters (would hijack typing!)
        if cleanMods.isEmpty || cleanMods == .shift {
            return false
        }
        return true
    }
}
