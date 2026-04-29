import AppKit
import Carbon
import Observation
import SwiftUI

final class StatusBarController {
    private let statusItem: NSStatusItem
    private(set) var captureFullScreenItem: NSMenuItem
    private(set) var captureAreaItem: NSMenuItem
    let settings: AppSettings
    private let captureEngine: CaptureEngine
    private let hotKeyManager: HotKeyManager
    private var areaSelectionWindow: AreaSelectionWindow?
    private var preferencesPanel: NSPanel?

    init(settings: AppSettings, captureEngine: CaptureEngine, hotKeyManager: HotKeyManager) {
        self.settings = settings
        self.captureEngine = captureEngine
        self.hotKeyManager = hotKeyManager

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "SimpleScreen")

        captureFullScreenItem = NSMenuItem(title: "Capture Full Screen", action: nil, keyEquivalent: "")
        captureAreaItem = NSMenuItem(title: "Capture Selected Area", action: nil, keyEquivalent: "")

        let menu = NSMenu()
        menu.addItem(captureFullScreenItem)
        menu.addItem(captureAreaItem)
        menu.addItem(NSMenuItem.separator())
        let prefsItem = NSMenuItem(title: "Preferences…", action: nil, keyEquivalent: "")
        menu.addItem(prefsItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusItem.menu = menu

        captureFullScreenItem.target = self
        captureFullScreenItem.action = #selector(triggerFullScreenCapture)

        captureAreaItem.target = self
        captureAreaItem.action = #selector(triggerAreaCapture)

        prefsItem.target = self
        prefsItem.action = #selector(openPreferences)

        updateFullScreenKeyEquivalent()
        observeKeyEquivalents()
    }

    @objc private func triggerFullScreenCapture() {
        Task { await captureEngine.captureFullScreen() }
    }

    @objc private func triggerAreaCapture() {
        showAreaSelectionWindow()
    }

    @objc func openPreferences() {
        if preferencesPanel == nil {
            let view = PreferencesView(
                settings: settings,
                hotKeyManager: hotKeyManager,
                fullScreenCallback: { [weak self] in
                    Task { await self?.captureEngine.captureFullScreen() }
                },
                areaSelectCallback: { [weak self] in
                    self?.showAreaSelectionWindow()
                },
                onDone: { [weak self] in
                    self?.preferencesPanel?.orderOut(nil)
                }
            )
            let hostingView = NSHostingView(rootView: view)
            hostingView.sizingOptions = [.intrinsicContentSize]
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 100),
                styleMask: [.titled, .closable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = "Preferences"
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.contentView = hostingView
            panel.setContentSize(hostingView.intrinsicContentSize)
            panel.center()
            preferencesPanel = panel
        }
        preferencesPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showAreaSelectionWindow() {
        if let existing = areaSelectionWindow {
            existing.close()
            areaSelectionWindow = nil
        }
        let window = AreaSelectionWindow()
        areaSelectionWindow = window
        window.completion = { [weak self] rect in
            // Defer nil-out to next run loop so the current event's autorelease
            // pool fully drains before the window/view are released.
            DispatchQueue.main.async {
                self?.areaSelectionWindow = nil
            }
            guard let rect else { return }
            Task { await self?.captureEngine.captureArea(rect: rect) }
        }
        // Do NOT call NSApp.activate — on macOS 26 it triggers extra window-management
        // releases that over-release the overlay window and cause EXC_BAD_ACCESS.
        // canBecomeKey=true on AreaSelectionWindow ensures keyboard events still work.
        window.makeKeyAndOrderFront(nil)
    }

    func updateAreaSelectKeyEquivalent() {
        if let shortcut = settings.areaSelectShortcut {
            captureAreaItem.keyEquivalent = keyEquivalentString(for: shortcut.keyCode)
            captureAreaItem.keyEquivalentModifierMask = nsModifierFlags(from: shortcut.modifierFlags)
        } else {
            captureAreaItem.keyEquivalent = ""
            captureAreaItem.keyEquivalentModifierMask = []
        }
    }

    func updateFullScreenKeyEquivalent() {
        if let shortcut = settings.fullScreenShortcut {
            captureFullScreenItem.keyEquivalent = keyEquivalentString(for: shortcut.keyCode)
            captureFullScreenItem.keyEquivalentModifierMask = nsModifierFlags(from: shortcut.modifierFlags)
        } else {
            captureFullScreenItem.keyEquivalent = ""
            captureFullScreenItem.keyEquivalentModifierMask = []
        }
    }

    private func observeKeyEquivalents() {
        withObservationTracking {
            _ = settings.fullScreenShortcut
            _ = settings.areaSelectShortcut
        } onChange: {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateFullScreenKeyEquivalent()
                self.updateAreaSelectKeyEquivalent()
                self.observeKeyEquivalents()
            }
        }
    }

    private func keyEquivalentString(for keyCode: UInt32) -> String {
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
        return map[keyCode] ?? ""
    }

    private func nsModifierFlags(from carbonFlags: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonFlags & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonFlags & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonFlags & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonFlags & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    func disableCaptureItems() {
        captureFullScreenItem.isEnabled = false
        captureAreaItem.isEnabled = false
    }

    func enableCaptureItems() {
        captureFullScreenItem.isEnabled = true
        captureAreaItem.isEnabled = true
    }
}
