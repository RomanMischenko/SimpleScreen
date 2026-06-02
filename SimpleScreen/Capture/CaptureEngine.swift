import AppKit
import CoreGraphics
import ScreenCaptureKit
import UniformTypeIdentifiers

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
            config.width = display.width
            config.height = display.height

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

    private func log(_ message: String) {
        let logURL = URL(fileURLWithPath: "/tmp/simplescreenlog.txt")
        let line = "\(Date()): \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    private func saveImageToDisk(_ capture: Capture) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let filename = "Screenshot \(formatter.string(from: capture.timestamp)).png"

        let saveDir = settings.saveLocationURL
        log("saveDir = \(saveDir.path)")
        log("imageSize = \(capture.image.width)x\(capture.image.height), colorSpace = \(capture.image.colorSpace?.name ?? "nil" as CFString)")

        do {
            try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
            log("createDirectory OK")
        } catch {
            log("createDirectory FAILED: \(error)")
        }

        let fileURL = saveDir.appendingPathComponent(filename)
        do {
            try writePNG(capture.image, to: fileURL)
            log("write OK: \(fileURL.path)")
            return fileURL.path
        } catch {
            log("primary write FAILED (\(fileURL.path)): \(error)")
        }

        let desktopURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent(filename)
        do {
            try writePNG(capture.image, to: desktopURL)
            log("desktop write OK: \(desktopURL.path)")
            let alert = NSAlert()
            alert.messageText = "Screenshot Saved to Desktop"
            alert.informativeText = "The configured save folder was unavailable. The screenshot was saved to your Desktop instead."
            alert.runModal()
            return desktopURL.path
        } catch {
            log("desktop write FAILED (\(desktopURL.path)): \(error)")
        }

        let alert = NSAlert()
        alert.messageText = "Screenshot Save Failed"
        alert.informativeText = "Could not save to \(fileURL.path) or Desktop. Check /tmp/simplescreenlog.txt for details."
        alert.runModal()
        return nil
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        log("rep bitsPerPixel=\(rep.bitsPerPixel) bitmapFormat=\(rep.bitmapFormat.rawValue) hasAlpha=\(rep.hasAlpha)")
        guard let data = rep.representation(using: .png, properties: [:]) else {
            log("rep.representation returned nil")
            throw CocoaError(.fileWriteUnknown)
        }
        log("png data size=\(data.count)")
        try data.write(to: url, options: .atomic)
    }

    private func copyToClipboard(_ image: CGImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: .zero)])
    }
}
