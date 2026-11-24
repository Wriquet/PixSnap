import Cocoa
import ServiceManagement

public enum SaveImageFormat: String, CaseIterable, Sendable {
    case png = "png"
    case jpeg = "jpeg"

    public var displayName: String {
        switch self {
        case .png: return "PNG（无损高清）"
        case .jpeg: return "JPEG（高压缩小体积）"
        }
    }

    public var fileExtension: String { rawValue }
}

public enum ColorCopyFormat: String, CaseIterable, Sendable {
    case hex = "hex"
    case hexNoHash = "hexNoHash"
    case rgb = "rgb"
    case hsl = "hsl"

    public var displayName: String {
        switch self {
        case .hex: return "HEX (#RRGGBB)"
        case .hexNoHash: return "HEX (RRGGBB)"
        case .rgb: return "RGB (r, g, b)"
        case .hsl: return "HSL (h, s%, l%)"
        }
    }

    public var shortLabel: String {
        switch self {
        case .hex: return "HEX"
        case .hexNoHash: return "HEX无#"
        case .rgb: return "RGB"
        case .hsl: return "HSL"
        }
    }

    public var next: ColorCopyFormat {
        let all = ColorCopyFormat.allCases
        guard let idx = all.firstIndex(of: self) else { return .hex }
        return all[(idx + 1) % all.count]
    }

    public func format(r: UInt8, g: UInt8, b: UInt8) -> String {
        switch self {
        case .hex:
            return String(format: "#%02X%02X%02X", r, g, b)
        case .hexNoHash:
            return String(format: "%02X%02X%02X", r, g, b)
        case .rgb:
            return "rgb(\(r), \(g), \(b))"
        case .hsl:
            let (h, s, l) = Self.rgbToHSL(r: r, g: g, b: b)
            return "hsl(\(h), \(s)%, \(l)%)"
        }
    }

    public static func rgbToHSL(r: UInt8, g: UInt8, b: UInt8) -> (Int, Int, Int) {
        let rf = Double(r) / 255.0
        let gf = Double(g) / 255.0
        let bf = Double(b) / 255.0

        let maxVal = max(rf, gf, bf)
        let minVal = min(rf, gf, bf)
        let delta = maxVal - minVal

        let l = (maxVal + minVal) / 2.0
        var h = 0.0
        var s = 0.0

        if delta > 0.0001 {
            s = l > 0.5 ? delta / (2.0 - maxVal - minVal) : delta / (maxVal + minVal)
            if maxVal == rf {
                h = ((gf - bf) / delta) + (gf < bf ? 6.0 : 0.0)
            } else if maxVal == gf {
                h = ((bf - rf) / delta) + 2.0
            } else {
                h = ((rf - gf) / delta) + 4.0
            }
            h *= 60.0
        }

        return (Int(round(h)) % 360, Int(round(s * 100.0)), Int(round(l * 100.0)))
    }
}

public enum PinZoomAnchorMode: String, CaseIterable, Sendable {
    case topLeft = "topLeft"
    case center = "center"
    case mouse = "mouse"

    public var displayName: String {
        switch self {
        case .topLeft: return "以左上角固定缩放（默认）"
        case .center: return "以贴图中心缩放"
        case .mouse: return "以鼠标位置缩放"
        }
    }
}

@MainActor
public final class AppSettings {
    public static let shared = AppSettings()

    private let ud = UserDefaults.standard

    private enum Keys {
        static let saveDirectoryPath = "pixsnap_save_directory"
        static let saveFormat = "pixsnap_save_format"
        static let jpegQuality = "pixsnap_jpeg_quality"
        static let autoCopyOnSave = "pixsnap_auto_copy_on_save"
        static let playCaptureSound = "pixsnap_play_sound"
        static let showMagnifier = "pixsnap_show_magnifier"
        static let enableWindowDetection = "pixsnap_window_detection"
        static let pinZoomAnchorMode = "PinZoomAnchorMode"
        static let pinShowBorder = "pixsnap_pin_show_border"
        static let pinStayAcrossSpaces = "pixsnap_pin_across_spaces"
        static let pinUseRoundedCorners = "pixsnap_pin_use_rounded_corners"
        static let pinCornerRadius = "pixsnap_pin_corner_radius"
        static let selectionUseRoundedCorners = "pixsnap_selection_use_rounded_corners"
        static let selectionCornerRadius = "pixsnap_selection_corner_radius"
        static let rectAnnotationRounded = "pixsnap_rect_annot_rounded"
        static let rectAnnotationCornerRadius = "pixsnap_rect_annot_corner_radius"
        static let colorCopyFormat = "pixsnap_color_copy_format"
        static let toolbarGlassOpacity = "pixsnap_toolbar_glass_opacity"
    }

    /// Posted on the main actor whenever `toolbarGlassOpacity` changes (live-updates open toolbars).
    public static let toolbarGlassOpacityDidChange = Notification.Name("PixSnapToolbarGlassOpacityDidChange")
    public static let toolbarGlassOpacityRange: ClosedRange<CGFloat> = 0.2...1.0
    public static let toolbarGlassOpacityDefault: CGFloat = 0.6

    private init() {}

    public var saveDirectoryURL: URL {
        get {
            if let path = ud.string(forKey: Keys.saveDirectoryPath), !path.isEmpty {
                let url = URL(fileURLWithPath: path, isDirectory: true)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    return url
                }
            }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        }
        set {
            ud.set(newValue.path, forKey: Keys.saveDirectoryPath)
        }
    }

    public var saveFormat: SaveImageFormat {
        get {
            SaveImageFormat(rawValue: ud.string(forKey: Keys.saveFormat) ?? "png") ?? .png
        }
        set {
            ud.set(newValue.rawValue, forKey: Keys.saveFormat)
        }
    }

    public var jpegQuality: Double {
        get {
            if ud.object(forKey: Keys.jpegQuality) == nil { return 0.92 }
            return max(0.3, min(1.0, ud.double(forKey: Keys.jpegQuality)))
        }
        set {
            ud.set(max(0.3, min(1.0, newValue)), forKey: Keys.jpegQuality)
        }
    }

    public var autoCopyOnSave: Bool {
        get {
            if ud.object(forKey: Keys.autoCopyOnSave) == nil { return true }
            return ud.bool(forKey: Keys.autoCopyOnSave)
        }
        set {
            ud.set(newValue, forKey: Keys.autoCopyOnSave)
        }
    }

    public var playCaptureSound: Bool {
        get {
            if ud.object(forKey: Keys.playCaptureSound) == nil { return true }
            return ud.bool(forKey: Keys.playCaptureSound)
        }
        set {
            ud.set(newValue, forKey: Keys.playCaptureSound)
        }
    }

    public var showMagnifier: Bool {
        get {
            if ud.object(forKey: Keys.showMagnifier) == nil { return true }
            return ud.bool(forKey: Keys.showMagnifier)
        }
        set {
            ud.set(newValue, forKey: Keys.showMagnifier)
        }
    }

    public var enableWindowDetection: Bool {
        get {
            if ud.object(forKey: Keys.enableWindowDetection) == nil { return true }
            return ud.bool(forKey: Keys.enableWindowDetection)
        }
        set {
            ud.set(newValue, forKey: Keys.enableWindowDetection)
        }
    }

    public var pinZoomAnchorMode: PinZoomAnchorMode {
        get {
            PinZoomAnchorMode(rawValue: ud.string(forKey: Keys.pinZoomAnchorMode) ?? "topLeft") ?? .topLeft
        }
        set {
            ud.set(newValue.rawValue, forKey: Keys.pinZoomAnchorMode)
        }
    }

    public var pinShowBorder: Bool {
        get {
            if ud.object(forKey: Keys.pinShowBorder) == nil { return true }
            return ud.bool(forKey: Keys.pinShowBorder)
        }
        set {
            ud.set(newValue, forKey: Keys.pinShowBorder)
        }
    }

    public var pinStayAcrossSpaces: Bool {
        get {
            if ud.object(forKey: Keys.pinStayAcrossSpaces) == nil { return true }
            return ud.bool(forKey: Keys.pinStayAcrossSpaces)
        }
        set {
            ud.set(newValue, forKey: Keys.pinStayAcrossSpaces)
        }
    }

    /// 贴图是否使用圆角（false = 90° 直角，true = 按 pinCornerRadius 圆角）
    public var pinUseRoundedCorners: Bool {
        get {
            if ud.object(forKey: Keys.pinUseRoundedCorners) == nil { return false }
            return ud.bool(forKey: Keys.pinUseRoundedCorners)
        }
        set {
            ud.set(newValue, forKey: Keys.pinUseRoundedCorners)
        }
    }

    /// 贴图圆角半径（2 ~ 24 pt，仅在 pinUseRoundedCorners 为 true 时生效）
    public var pinCornerRadius: CGFloat {
        get {
            if ud.object(forKey: Keys.pinCornerRadius) == nil { return 8.0 }
            return max(2.0, min(24.0, CGFloat(ud.double(forKey: Keys.pinCornerRadius))))
        }
        set {
            ud.set(Double(max(2.0, min(24.0, newValue))), forKey: Keys.pinCornerRadius)
        }
    }

    public var effectivePinCornerRadius: CGFloat {
        pinUseRoundedCorners ? pinCornerRadius : 0.0
    }

    /// 框选区域（含截图导出裁剪）是否使用圆角
    public var selectionUseRoundedCorners: Bool {
        get {
            if ud.object(forKey: Keys.selectionUseRoundedCorners) == nil { return false }
            return ud.bool(forKey: Keys.selectionUseRoundedCorners)
        }
        set {
            ud.set(newValue, forKey: Keys.selectionUseRoundedCorners)
        }
    }

    /// 框选区域圆角半径（2 ~ 24 pt）
    public var selectionCornerRadius: CGFloat {
        get {
            if ud.object(forKey: Keys.selectionCornerRadius) == nil { return 8.0 }
            return max(2.0, min(24.0, CGFloat(ud.double(forKey: Keys.selectionCornerRadius))))
        }
        set {
            ud.set(Double(max(2.0, min(24.0, newValue))), forKey: Keys.selectionCornerRadius)
        }
    }

    public var effectiveSelectionCornerRadius: CGFloat {
        selectionUseRoundedCorners ? selectionCornerRadius : 0.0
    }

    /// 矩形标注框默认是否圆角
    public var rectAnnotationRounded: Bool {
        get {
            if ud.object(forKey: Keys.rectAnnotationRounded) == nil { return false }
            return ud.bool(forKey: Keys.rectAnnotationRounded)
        }
        set {
            ud.set(newValue, forKey: Keys.rectAnnotationRounded)
        }
    }

    /// 矩形标注框圆角半径（2 ~ 20 pt）
    public var rectAnnotationCornerRadius: CGFloat {
        get {
            if ud.object(forKey: Keys.rectAnnotationCornerRadius) == nil { return 6.0 }
            return max(2.0, min(20.0, CGFloat(ud.double(forKey: Keys.rectAnnotationCornerRadius))))
        }
        set {
            ud.set(Double(max(2.0, min(20.0, newValue))), forKey: Keys.rectAnnotationCornerRadius)
        }
    }

    public var effectiveRectAnnotationCornerRadius: CGFloat {
        rectAnnotationRounded ? rectAnnotationCornerRadius : 0.0
    }

    /// 截图工具栏液态玻璃材质的不透明度（0.2 ~ 1.0，越小越透明；1.0 = 系统原生玻璃）
    public var toolbarGlassOpacity: CGFloat {
        get {
            if ud.object(forKey: Keys.toolbarGlassOpacity) == nil { return Self.toolbarGlassOpacityDefault }
            let r = Self.toolbarGlassOpacityRange
            return max(r.lowerBound, min(r.upperBound, CGFloat(ud.double(forKey: Keys.toolbarGlassOpacity))))
        }
        set {
            let r = Self.toolbarGlassOpacityRange
            ud.set(Double(max(r.lowerBound, min(r.upperBound, newValue))), forKey: Keys.toolbarGlassOpacity)
            NotificationCenter.default.post(name: Self.toolbarGlassOpacityDidChange, object: nil)
        }
    }

    public var colorCopyFormat: ColorCopyFormat {
        get {
            ColorCopyFormat(rawValue: ud.string(forKey: Keys.colorCopyFormat) ?? "hex") ?? .hex
        }
        set {
            ud.set(newValue.rawValue, forKey: Keys.colorCopyFormat)
        }
    }

    public var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    public func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            print("⚠️ 开机自启动设置失败: \(error.localizedDescription)")
            return false
        }
    }

    public func playFeedbackSound() {
        guard playCaptureSound else { return }
        if let sound = NSSound(named: NSSound.Name("Pop")) ?? NSSound(named: NSSound.Name("Tink")) {
            sound.volume = 0.35
            sound.play()
        }
    }
}
