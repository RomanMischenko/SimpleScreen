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
    private var cropWindow: CropWindow?
    private var preferencesPanel: NSPanel?
    private(set) var fullScreenConflict = false
    private(set) var areaSelectConflict = false

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
        Task { await showAreaSelectionWindow() }
    }

    @objc func openPreferences() {
        if preferencesPanel == nil {
            let view = PreferencesView(
                settings: settings,
                hotKeyManager: hotKeyManager,
                initialFullScreenConflict: fullScreenConflict,
                initialAreaSelectConflict: areaSelectConflict,
                fullScreenCallback: { [weak self] in
                    Task { await self?.captureEngine.captureFullScreen() }
                },
                areaSelectCallback: { [weak self] in
                    Task { await self?.showAreaSelectionWindow() }
                },
                onResolveConflict: { [weak self] mode in
                    switch mode {
                    case .fullScreen: self?.markConflict(fullScreen: false)
                    case .areaSelect: self?.markConflict(areaSelect: false)
                    }
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

    func showAreaSelectionWindow() async {
        guard let fullImage = await captureEngine.captureDisplayImage() else { return }

        await MainActor.run {
            if let existing = cropWindow {
                existing.close()
                cropWindow = nil
            }
            let window = CropWindow(image: fullImage)
            cropWindow = window
            window.cropCompletion = { [weak self] rect in
                DispatchQueue.main.async {
                    self?.cropWindow = nil
                }
                guard let self, let rect else { return }
                let scaleFactor = NSScreen.main?.backingScaleFactor ?? 1.0
                let pixelRect = CGRect(
                    x: rect.origin.x * scaleFactor,
                    y: rect.origin.y * scaleFactor,
                    width: rect.width * scaleFactor,
                    height: rect.height * scaleFactor
                )
                guard let cropped = CaptureEngine.cropImage(fullImage, to: pixelRect) else { return }
                self.captureEngine.handleAreaCapture(cropped)
            }
            window.makeKeyAndOrderFront(nil)
        }
    }

    func updateAreaSelectKeyEquivalent() {
        if areaSelectConflict {
            captureAreaItem.title = "Capture Selected Area (in use by system)"
            captureAreaItem.keyEquivalent = ""
            captureAreaItem.keyEquivalentModifierMask = []
            return
        }
        captureAreaItem.title = "Capture Selected Area"
        if let shortcut = settings.areaSelectShortcut {
            captureAreaItem.keyEquivalent = keyEquivalentString(for: shortcut.keyCode)
            captureAreaItem.keyEquivalentModifierMask = nsModifierFlags(from: shortcut.modifierFlags)
        } else {
            captureAreaItem.keyEquivalent = ""
            captureAreaItem.keyEquivalentModifierMask = []
        }
    }

    func updateFullScreenKeyEquivalent() {
        if fullScreenConflict {
            captureFullScreenItem.title = "Capture Full Screen (in use by system)"
            captureFullScreenItem.keyEquivalent = ""
            captureFullScreenItem.keyEquivalentModifierMask = []
            return
        }
        captureFullScreenItem.title = "Capture Full Screen"
        if let shortcut = settings.fullScreenShortcut {
            captureFullScreenItem.keyEquivalent = keyEquivalentString(for: shortcut.keyCode)
            captureFullScreenItem.keyEquivalentModifierMask = nsModifierFlags(from: shortcut.modifierFlags)
        } else {
            captureFullScreenItem.keyEquivalent = ""
            captureFullScreenItem.keyEquivalentModifierMask = []
        }
    }

    func markConflict(fullScreen: Bool? = nil, areaSelect: Bool? = nil) {
        if let fullScreen { fullScreenConflict = fullScreen }
        if let areaSelect { areaSelectConflict = areaSelect }
        updateFullScreenKeyEquivalent()
        updateAreaSelectKeyEquivalent()
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
