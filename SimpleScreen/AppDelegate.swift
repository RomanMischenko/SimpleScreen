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

        var conflictLabels: [String] = []
        if let label = registerFullScreenHotKey() { conflictLabels.append(label) }
        if let label = registerAreaSelectHotKey() { conflictLabels.append(label) }
        if !conflictLabels.isEmpty {
            notificationManager.postHotkeyConflictNotification(shortcuts: conflictLabels)
        }
        checkScreenCapturePermission()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if permissionAlert != nil && CGPreflightScreenCaptureAccess() {
            grantedPermission()
        }
    }

    private func registerFullScreenHotKey() -> String? {
        let defaultShortcut = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_3), modifierFlags: UInt32(cmdKey | shiftKey))
        let stored = settings.fullScreenShortcut
        let shortcut = stored ?? defaultShortcut
        var conflictLabel: String? = nil
        do {
            try hotKeyManager.register(shortcut: shortcut, id: 1) { [weak self] in
                guard let self else { return }
                Task { await self.captureEngine.captureFullScreen() }
            }
            if stored == nil {
                settings.fullScreenShortcut = shortcut
            }
            statusBarController.markConflict(fullScreen: false)
        } catch HotKeyError.conflict {
            statusBarController.markConflict(fullScreen: true)
            conflictLabel = displayString(shortcut)
        } catch {}
        statusBarController.updateFullScreenKeyEquivalent()
        return conflictLabel
    }

    private func registerAreaSelectHotKey() -> String? {
        let defaultShortcut = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_4), modifierFlags: UInt32(cmdKey | shiftKey))
        let stored = settings.areaSelectShortcut
        let shortcut = stored ?? defaultShortcut
        var conflictLabel: String? = nil
        do {
            try hotKeyManager.register(shortcut: shortcut, id: 2) { [weak self] in
                guard let self else { return }
                Task { await self.statusBarController.showAreaSelectionWindow() }
            }
            if stored == nil {
                settings.areaSelectShortcut = shortcut
            }
            statusBarController.markConflict(areaSelect: false)
        } catch HotKeyError.conflict {
            statusBarController.markConflict(areaSelect: true)
            conflictLabel = displayString(shortcut)
        } catch {}
        statusBarController.updateAreaSelectKeyEquivalent()
        return conflictLabel
    }

    private func displayString(_ shortcut: KeyboardShortcut) -> String {
        let flags = shortcut.modifierFlags
        var s = ""
        if flags & UInt32(controlKey) != 0 { s += "⌃" }
        if flags & UInt32(optionKey) != 0 { s += "⌥" }
        if flags & UInt32(shiftKey) != 0 { s += "⇧" }
        if flags & UInt32(cmdKey) != 0 { s += "⌘" }
        s += keyChar(shortcut.keyCode).uppercased()
        return s
    }

    private func keyChar(_ keyCode: UInt32) -> String {
        let map: [UInt32: String] = [
            0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6",
            0x17: "5", 0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-",
            0x1C: "8", 0x1D: "0", 0x00: "a", 0x0B: "b", 0x08: "c",
            0x02: "d", 0x0E: "e", 0x03: "f", 0x05: "g", 0x04: "h",
            0x22: "i", 0x26: "j", 0x28: "k", 0x25: "l", 0x2E: "m",
            0x2D: "n", 0x1F: "o", 0x23: "p", 0x0C: "q", 0x0F: "r",
            0x01: "s", 0x11: "t", 0x20: "u", 0x09: "v", 0x0D: "w",
            0x07: "x", 0x10: "y", 0x06: "z",
        ]
        return map[keyCode] ?? "?"
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
