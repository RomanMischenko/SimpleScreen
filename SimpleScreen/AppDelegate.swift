import AppKit
import Carbon
import CoreGraphics

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var settings: AppSettings!
    private var hotKeyManager: HotKeyManager!
    private var notificationManager: NotificationManager!
    private var captureEngine: CaptureEngine!
    private var statusBarController: StatusBarController!

    private var permissionAlert: NSAlert?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        settings = AppSettings()
        hotKeyManager = HotKeyManager()
        hotKeyManager.setup()
        notificationManager = NotificationManager()
        notificationManager.requestAuthorization()
        captureEngine = CaptureEngine(settings: settings, notificationManager: notificationManager)
        statusBarController = StatusBarController(settings: settings, captureEngine: captureEngine, hotKeyManager: hotKeyManager)

        registerFullScreenHotKey()
        registerAreaSelectHotKey()
        checkScreenCapturePermission()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if permissionAlert != nil && CGPreflightScreenCaptureAccess() {
            grantedPermission()
        }
    }

    private func registerFullScreenHotKey() {
        let defaultShortcut = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_3), modifierFlags: UInt32(cmdKey | shiftKey))
        let stored = settings.fullScreenShortcut
        let shortcut = stored ?? defaultShortcut
        do {
            try hotKeyManager.register(shortcut: shortcut, id: 1) { [weak self] in
                guard let self else { return }
                Task { await self.captureEngine.captureFullScreen() }
            }
            if stored == nil {
                settings.fullScreenShortcut = shortcut
            }
        } catch HotKeyError.conflict {
        } catch {}
        statusBarController.updateFullScreenKeyEquivalent()
    }

    private func registerAreaSelectHotKey() {
        let defaultShortcut = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_4), modifierFlags: UInt32(cmdKey | shiftKey))
        let stored = settings.areaSelectShortcut
        let shortcut = stored ?? defaultShortcut
        do {
            try hotKeyManager.register(shortcut: shortcut, id: 2) { [weak self] in
                guard let self else { return }
                Task { await self.statusBarController.showAreaSelectionWindow() }
            }
            if stored == nil {
                settings.areaSelectShortcut = shortcut
            }
        } catch HotKeyError.conflict {
        } catch {}
        statusBarController.updateAreaSelectKeyEquivalent()
    }

    private func checkScreenCapturePermission() {
        guard !CGPreflightScreenCaptureAccess() else { return }

        statusBarController.disableCaptureItems()

        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "SimpleScreen requires Screen Recording permission to capture screenshots. Grant access in System Settings, then return to SimpleScreen."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        permissionAlert = alert

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if CGPreflightScreenCaptureAccess() {
                self.grantedPermission()
            }
        }
    }

    private func grantedPermission() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        permissionAlert = nil
        statusBarController.enableCaptureItems()
    }
}
