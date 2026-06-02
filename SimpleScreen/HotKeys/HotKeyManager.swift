import Carbon
import Foundation
import os

private let log = Logger(subsystem: "com.simplescreenapp.SimpleScreen", category: "hotkeys")

enum HotKeyError: Error {
    case conflict
    case registrationFailed(OSStatus)
}

final class HotKeyManager {
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var callbacks: [UInt32: () -> Void] = [:]
    private var eventHandlerRef: EventHandlerRef?

    func setup() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                manager.callbacks[hotKeyID.id]?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        if status != noErr {
            log.error("InstallEventHandler failed: OSStatus=\(status)")
        }
    }

    func register(shortcut: KeyboardShortcut, id: UInt32, callback: @escaping () -> Void) throws {
        let hotKeyID = EventHotKeyID(signature: OSType(0x5353_4353), id: id)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifierFlags, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        if status == OSStatus(eventHotKeyExistsErr) {
            throw HotKeyError.conflict
        } else if status != noErr {
            throw HotKeyError.registrationFailed(status)
        }

        hotKeyRefs[id] = hotKeyRef
        callbacks[id] = callback
    }

    func unregister(id: UInt32) {
        if let ref = hotKeyRefs[id] {
            UnregisterEventHotKey(ref)
            hotKeyRefs.removeValue(forKey: id)
        }
        callbacks.removeValue(forKey: id)
    }
}
