import AppKit
import CoreGraphics
import os
import ScreenCaptureKit
import UniformTypeIdentifiers

private let log = Logger(subsystem: "com.simplescreenapp.SimpleScreen", category: "capture")

struct Capture {
    let mode: CaptureMode
    let timestamp: Date
    let image: CGImage
}

@Observable final class CaptureEngine {
    private(set) var isCapturing = false

    private let settings: AppSettings
    private let notificationManager: NotificationManager

    init(settings: AppSettings, notificationManager: NotificationManager) {
        self.settings = settings
        self.notificationManager = notificationManager
    }

    func captureDisplayImage() async -> CGImage? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else { return nil }

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let config = SCStreamConfiguration()
            let scale = NSScreen.main?.backingScaleFactor ?? 1.0
            config.width = Int(CGFloat(display.width) * scale)
            config.height = Int(CGFloat(display.height) * scale)

            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            return nil
        }
    }

    func captureFullScreen() async {
        guard let image = await captureDisplayImage() else { return }
        let capture = Capture(mode: .fullScreen, timestamp: Date(), image: image)
        dispatchPostCapture(capture)
    }

    func handleAreaCapture(_ image: CGImage) {
        let capture = Capture(mode: .areaSelect, timestamp: Date(), image: image)
        dispatchPostCapture(capture)
    }

    static func cropImage(_ image: CGImage, to rect: CGRect) -> CGImage? {
        image.cropping(to: rect)
    }

    private func dispatchPostCapture(_ capture: Capture) {
        switch settings.postCaptureAction {
        case .saveToFile:
            if let path = saveImageToDisk(capture) {
                notificationManager.postSavedNotification(path: path)
            }
        case .copyToClipboard:
            copyToClipboard(capture.image)
            notificationManager.postCopiedNotification()
        case .saveAndCopy:
            if let path = saveImageToDisk(capture) {
                notificationManager.postSavedNotification(path: path)
            } else {
                notificationManager.postCopiedNotification()
            }
            copyToClipboard(capture.image)
        }
    }

    private func saveImageToDisk(_ capture: Capture) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let filename = "Screenshot \(formatter.string(from: capture.timestamp)).png"

        let saveDir = settings.saveLocationURL
        let colorSpaceName = (capture.image.colorSpace?.name).map { $0 as String } ?? "nil"
        log.debug("saveDir = \(saveDir.path, privacy: .public)")
        log.debug("imageSize = \(capture.image.width)x\(capture.image.height), colorSpace = \(colorSpaceName, privacy: .public)")

        do {
            try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
            log.debug("createDirectory OK")
        } catch {
            log.error("createDirectory FAILED: \(error.localizedDescription, privacy: .public)")
        }

        let fileURL = saveDir.appendingPathComponent(filename)
        do {
            try writePNG(capture.image, to: fileURL)
            log.info("write OK: \(fileURL.path, privacy: .public)")
            return fileURL.path
        } catch {
            log.error("primary write FAILED (\(fileURL.path, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }

        let desktopURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent(filename)
        do {
            try writePNG(capture.image, to: desktopURL)
            log.info("desktop write OK: \(desktopURL.path, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "Screenshot Saved to Desktop"
            alert.informativeText = "The configured save folder was unavailable. The screenshot was saved to your Desktop instead."
            alert.runModal()
            return desktopURL.path
        } catch {
            log.error("desktop write FAILED (\(desktopURL.path, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }

        let alert = NSAlert()
        alert.messageText = "Screenshot Save Failed"
        alert.informativeText = "Could not save to \(fileURL.path) or Desktop. Check Console.app (subsystem com.simplescreenapp.SimpleScreen) for details."
        alert.runModal()
        return nil
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        log.debug("rep bitsPerPixel=\(rep.bitsPerPixel) bitmapFormat=\(rep.bitmapFormat.rawValue) hasAlpha=\(rep.hasAlpha)")
        guard let data = rep.representation(using: .png, properties: [:]) else {
            log.error("rep.representation returned nil")
            throw CocoaError(.fileWriteUnknown)
        }
        log.debug("png data size=\(data.count)")
        try data.write(to: url, options: .atomic)
    }

    private func copyToClipboard(_ image: CGImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: .zero)])
        log.info("clipboard write OK: \(image.width)x\(image.height)")
    }
}
