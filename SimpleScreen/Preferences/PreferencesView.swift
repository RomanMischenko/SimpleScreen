import AppKit
import Carbon
import SwiftUI

// Reference type so NSEvent monitor closures can mutate recording state and trigger SwiftUI updates
@Observable
final class ShortcutRecordingState {
    var isRecordingFullScreen = false
    var isRecordingAreaSelect = false
    var fullScreenConflict = false
    var areaSelectConflict = false
    var eventMonitor: Any?
}

struct PreferencesView: View {
    @Bindable var settings: AppSettings
    let hotKeyManager: HotKeyManager
    let initialFullScreenConflict: Bool
    let initialAreaSelectConflict: Bool
    let fullScreenCallback: () -> Void
    let areaSelectCallback: () -> Void
    let onResolveConflict: (CaptureMode) -> Void
    let onDone: () -> Void

    @State private var rec = ShortcutRecordingState()
    @State private var didSyncInitialConflicts = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Post-Capture Action") {
                    Picker("", selection: $settings.postCaptureAction) {
                        Text("Save to File").tag(PostCaptureAction.saveToFile)
                        Text("Copy to Clipboard").tag(PostCaptureAction.copyToClipboard)
                        Text("Save and Copy").tag(PostCaptureAction.saveAndCopy)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }

                Section("Save Location") {
                    HStack {
                        Text(settings.saveLocationURL.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…") { chooseFolder() }
                    }
                }

                Section("Keyboard Shortcuts") {
                    shortcutRow(
                        label: "Full Screen",
                        shortcut: settings.fullScreenShortcut,
                        isRecording: rec.isRecordingFullScreen,
                        hasConflict: rec.fullScreenConflict
                    ) { startRecording(for: .fullScreen) }

                    shortcutRow(
                        label: "Area Select",
                        shortcut: settings.areaSelectShortcut,
                        isRecording: rec.isRecordingAreaSelect,
                        hasConflict: rec.areaSelectConflict
                    ) { startRecording(for: .areaSelect) }
                }

                Section {
                    Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Done") {
                    cancelRecording()
                    onDone()
                }
            }
            .padding([.horizontal, .bottom])
        }
        .frame(minWidth: 460)
        .onAppear {
            if !didSyncInitialConflicts {
                rec.fullScreenConflict = initialFullScreenConflict
                rec.areaSelectConflict = initialAreaSelectConflict
                didSyncInitialConflicts = true
            }
        }
        .onDisappear { cancelRecording() }
    }

    @ViewBuilder
    private func shortcutRow(
        label: String,
        shortcut: KeyboardShortcut?,
        isRecording: Bool,
        hasConflict: Bool,
        onRecord: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(shortcut.map(displayString) ?? "Not Set")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button(isRecording ? "Recording…" : "Record", action: onRecord)
            }
            if hasConflict {
                Text("This shortcut conflicts with a system shortcut — choose another")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
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

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveLocationURL = url
        }
    }

    private func startRecording(for mode: CaptureMode) {
        cancelRecording()
        switch mode {
        case .fullScreen: rec.isRecordingFullScreen = true
        case .areaSelect: rec.isRecordingAreaSelect = true
        }
        let recCapture = rec
        rec.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                cancelRecording()
                return nil
            }
            let carbonMods = carbonModifiers(from: event.modifierFlags)
            // Require at least one modifier and a non-modifier key — reject bare
            // letters (would hijack the key globally) and modifier-only presses.
            guard carbonMods != 0, !isModifierKeyCode(event.keyCode) else {
                NSSound.beep()
                return nil
            }
            let newShortcut = KeyboardShortcut(
                keyCode: UInt32(event.keyCode),
                modifierFlags: carbonMods
            )
            attemptRegister(shortcut: newShortcut, for: mode, rec: recCapture)
            return nil
        }
    }

    private func attemptRegister(shortcut: KeyboardShortcut, for mode: CaptureMode, rec: ShortcutRecordingState) {
        let id: UInt32 = mode == .fullScreen ? 1 : 2
        let callback = mode == .fullScreen ? fullScreenCallback : areaSelectCallback
        let oldShortcut = mode == .fullScreen ? settings.fullScreenShortcut : settings.areaSelectShortcut

        hotKeyManager.unregister(id: id)

        do {
            try hotKeyManager.register(shortcut: shortcut, id: id, callback: callback)
            switch mode {
            case .fullScreen:
                settings.fullScreenShortcut = shortcut
                rec.isRecordingFullScreen = false
                rec.fullScreenConflict = false
            case .areaSelect:
                settings.areaSelectShortcut = shortcut
                rec.isRecordingAreaSelect = false
                rec.areaSelectConflict = false
            }
            onResolveConflict(mode)
            removeMonitor(rec: rec)
        } catch HotKeyError.conflict {
            if let old = oldShortcut {
                try? hotKeyManager.register(shortcut: old, id: id, callback: callback)
            }
            switch mode {
            case .fullScreen: rec.fullScreenConflict = true
            case .areaSelect: rec.areaSelectConflict = true
            }
        } catch {}
    }

    private func cancelRecording() {
        rec.isRecordingFullScreen = false
        rec.isRecordingAreaSelect = false
        rec.fullScreenConflict = false
        rec.areaSelectConflict = false
        removeMonitor(rec: rec)
    }

    private func removeMonitor(rec: ShortcutRecordingState) {
        if let m = rec.eventMonitor {
            NSEvent.removeMonitor(m)
            rec.eventMonitor = nil
        }
    }

    // Left/right modifier key codes (Command, Shift, CapsLock, Option, Control,
    // Function): 0x36...0x3F. A pure modifier press must not become a shortcut.
    private func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        (0x36...0x3F).contains(keyCode)
    }

    private func carbonModifiers(from nsFlags: NSEvent.ModifierFlags) -> UInt32 {
        var flags: UInt32 = 0
        if nsFlags.contains(.command) { flags |= UInt32(cmdKey) }
        if nsFlags.contains(.shift) { flags |= UInt32(shiftKey) }
        if nsFlags.contains(.option) { flags |= UInt32(optionKey) }
        if nsFlags.contains(.control) { flags |= UInt32(controlKey) }
        return flags
    }
}
