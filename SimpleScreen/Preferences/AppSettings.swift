import Foundation
import os
import ServiceManagement

private let log = Logger(subsystem: "com.simplescreenapp.SimpleScreen", category: "launchAtLogin")

enum PostCaptureAction: String {
    case saveToFile = "saveToFile"
    case copyToClipboard = "copyToClipboard"
    case saveAndCopy = "saveAndCopy"
}

enum CaptureMode {
    case fullScreen
    case areaSelect
}

struct KeyboardShortcut {
    var keyCode: UInt32
    var modifierFlags: UInt32
}

@Observable final class AppSettings {
    var postCaptureAction: PostCaptureAction {
        didSet {
            UserDefaults.standard.set(postCaptureAction.rawValue, forKey: "ss_postCaptureAction")
        }
    }

    var saveLocationURL: URL {
        didSet {
            UserDefaults.standard.set(saveLocationURL.path, forKey: "ss_saveLocationPath")
        }
    }

    var fullScreenShortcut: KeyboardShortcut? {
        didSet {
            if let s = fullScreenShortcut {
                UserDefaults.standard.set(Int(s.keyCode), forKey: "ss_fullScreenShortcutKeyCode")
                UserDefaults.standard.set(Int(s.modifierFlags), forKey: "ss_fullScreenShortcutModifiers")
            } else {
                UserDefaults.standard.removeObject(forKey: "ss_fullScreenShortcutKeyCode")
                UserDefaults.standard.removeObject(forKey: "ss_fullScreenShortcutModifiers")
            }
        }
    }

    var areaSelectShortcut: KeyboardShortcut? {
        didSet {
            if let s = areaSelectShortcut {
                UserDefaults.standard.set(Int(s.keyCode), forKey: "ss_areaSelectShortcutKeyCode")
                UserDefaults.standard.set(Int(s.modifierFlags), forKey: "ss_areaSelectShortcutModifiers")
            } else {
                UserDefaults.standard.removeObject(forKey: "ss_areaSelectShortcutKeyCode")
                UserDefaults.standard.removeObject(forKey: "ss_areaSelectShortcutModifiers")
            }
        }
    }

    var launchAtLogin: Bool {
        didSet {
            guard !isRevertingLaunchAtLogin else { return }
            UserDefaults.standard.set(launchAtLogin, forKey: "ss_launchAtLogin")
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                let attempted = launchAtLogin
                log.error("SMAppService \(attempted ? "register" : "unregister") failed: \(error.localizedDescription, privacy: .public)")
                isRevertingLaunchAtLogin = true
                launchAtLogin = oldValue
                UserDefaults.standard.set(launchAtLogin, forKey: "ss_launchAtLogin")
                isRevertingLaunchAtLogin = false
                onLaunchAtLoginRegistrationFailed?(attempted, error)
            }
        }
    }

    var onLaunchAtLoginRegistrationFailed: ((Bool, Error) -> Void)?
    private var isRevertingLaunchAtLogin = false

    init() {
        let defaults = UserDefaults.standard

        let actionRaw = defaults.string(forKey: "ss_postCaptureAction") ?? "saveAndCopy"
        postCaptureAction = PostCaptureAction(rawValue: actionRaw) ?? .saveAndCopy

        let savedPath = defaults.string(forKey: "ss_saveLocationPath")
        if let savedPath {
            saveLocationURL = URL(fileURLWithPath: savedPath)
        } else {
            saveLocationURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Pictures/Screenshot")
        }

        let fsKeyCode = defaults.object(forKey: "ss_fullScreenShortcutKeyCode") as? Int
        let fsModifiers = defaults.object(forKey: "ss_fullScreenShortcutModifiers") as? Int
        if let kc = fsKeyCode, let mf = fsModifiers {
            fullScreenShortcut = KeyboardShortcut(keyCode: UInt32(kc), modifierFlags: UInt32(mf))
        } else {
            fullScreenShortcut = nil
        }

        let asKeyCode = defaults.object(forKey: "ss_areaSelectShortcutKeyCode") as? Int
        let asModifiers = defaults.object(forKey: "ss_areaSelectShortcutModifiers") as? Int
        if let kc = asKeyCode, let mf = asModifiers {
            areaSelectShortcut = KeyboardShortcut(keyCode: UInt32(kc), modifierFlags: UInt32(mf))
        } else {
            areaSelectShortcut = nil
        }

        launchAtLogin = defaults.bool(forKey: "ss_launchAtLogin")
    }
}
