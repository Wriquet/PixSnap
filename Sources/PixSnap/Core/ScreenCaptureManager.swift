import ScreenCaptureKit
import Cocoa

public final class ScreenCaptureManager: @unchecked Sendable {
    public static let shared = ScreenCaptureManager()

    public struct CapturedScreen: Sendable {
        public let displayID: CGDirectDisplayID
        public let image: CGImage
        /// Global Cocoa screen coordinates (origin & size in points)
        public let screenFrame: CGRect
        public let pixelSize: CGSize
        public let scaleFactor: CGFloat
        public let windows: [DetectedWindow]
        /// Primary monitor height in Cocoa points (used for CG <-> Cocoa top-left conversion in AX queries)
        public let primaryScreenHeight: CGFloat

        public init(
            displayID: CGDirectDisplayID,
            image: CGImage,
            screenFrame: CGRect,
            pixelSize: CGSize,
            scaleFactor: CGFloat,
            windows: [DetectedWindow] = [],
            primaryScreenHeight: CGFloat = 1080
        ) {
            self.displayID = displayID
            self.image = image
            self.screenFrame = screenFrame
            self.pixelSize = pixelSize
            self.scaleFactor = scaleFactor
            self.windows = windows
            self.primaryScreenHeight = primaryScreenHeight
        }
    }

    private struct ScreenDescriptor: Sendable {
        let displayID: CGDirectDisplayID
        let frame: CGRect
        let scale: CGFloat
    }

    /// Capture ALL active screens concurrently using a single SCShareableContent query,
    /// matching each SCDisplay cleanly to its NSScreen by CGDirectDisplayID.
    public func captureAllScreens(includeWindowDetection: Bool = true) async throws -> [CapturedScreen] {
        let screenInfo: (descriptors: [ScreenDescriptor], primaryHeight: CGFloat) = await MainActor.run {
            let screens = NSScreen.screens
            let primaryHeight = screens.first?.frame.height ?? 1080
            let descs: [ScreenDescriptor] = screens.compactMap { screen in
                guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                    return nil
                }
                return ScreenDescriptor(
                    displayID: CGDirectDisplayID(num.uint32Value),
                    frame: screen.frame,
                    scale: screen.backingScaleFactor
                )
            }
            return (descs, primaryHeight)
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard !content.displays.isEmpty else {
            throw NSError(
                domain: "ScreenCaptureManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "未检测到可用显示器"]
            )
        }

        let displayMap = Dictionary(uniqueKeysWithValues: content.displays.map { ($0.displayID, $0) })
        let scWindows = content.windows
        let primaryHeight = screenInfo.primaryHeight

        // Build matched pairs (fallback to first display if screen descriptors somehow empty)
        var targets: [(SCDisplay, ScreenDescriptor)] = []
        for desc in screenInfo.descriptors {
            if let display = displayMap[desc.displayID] {
                targets.append((display, desc))
            }
        }
        if targets.isEmpty, let firstDisplay = content.displays.first {
            let fallbackDesc = ScreenDescriptor(
                displayID: firstDisplay.displayID,
                frame: CGRect(x: 0, y: 0, width: CGFloat(firstDisplay.width), height: CGFloat(firstDisplay.height)),
                scale: 2.0
            )
            targets.append((firstDisplay, fallbackDesc))
        }

        struct CaptureJob: @unchecked Sendable {
            let filter: SCContentFilter
            let config: SCStreamConfiguration
            let desc: ScreenDescriptor
            let windows: [DetectedWindow]
        }

        let jobs: [CaptureJob] = targets.map { (display, desc) in
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(round(desc.frame.width * desc.scale))
            config.height = Int(round(desc.frame.height * desc.scale))
            config.showsCursor = false
            config.capturesAudio = false

            let detectedWindows: [DetectedWindow]
            if includeWindowDetection {
                let ordered = WindowDetector.shared.extractOrderedWindows(
                    primaryScreenHeight: primaryHeight,
                    targetScreenFrame: desc.frame
                )
                detectedWindows = ordered.isEmpty
                    ? WindowDetector.shared.extractVisibleWindows(
                        from: scWindows,
                        primaryScreenHeight: primaryHeight,
                        targetScreenFrame: desc.frame
                    )
                    : ordered
            } else {
                detectedWindows = []
            }
            return CaptureJob(filter: filter, config: config, desc: desc, windows: detectedWindows)
        }

        // Capture all displays concurrently for minimum latency
        return try await withThrowingTaskGroup(of: CapturedScreen.self) { group in
            for job in jobs {
                group.addTask {
                    let cgImage = try await SCScreenshotManager.captureImage(
                        contentFilter: job.filter,
                        configuration: job.config
                    )
                    return CapturedScreen(
                        displayID: job.desc.displayID,
                        image: cgImage,
                        screenFrame: job.desc.frame,
                        pixelSize: CGSize(width: cgImage.width, height: cgImage.height),
                        scaleFactor: job.desc.scale,
                        windows: job.windows,
                        primaryScreenHeight: primaryHeight
                    )
                }
            }

            var results: [CapturedScreen] = []
            for try await captured in group {
                results.append(captured)
            }
            return results
        }
    }
}
