import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // Allow banners and sound even while the app is the active process.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func postSavedNotification(path: String) {
        let content = UNMutableNotificationContent()
        content.title = "Screenshot Saved"
        content.body = "Saved to \(path)"
        content.categoryIdentifier = "ss.capture.save"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "ss.capture.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    func postHotkeyConflictNotification(shortcuts: [String]) {
        guard !shortcuts.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = "Hotkey Conflict"
        let list = shortcuts.joined(separator: ", ")
        let verb = shortcuts.count == 1 ? "is" : "are"
        content.body = "\(list) \(verb) reserved by macOS. Open Preferences to change, or disable the system shortcut in System Settings → Keyboard → Shortcuts → Screenshots."
        content.categoryIdentifier = "ss.hotkey.conflict"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "ss.hotkey.conflict",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    func postSavedToDesktopFallbackNotification(desktopPath: String) {
        let content = UNMutableNotificationContent()
        content.title = "Screenshot Saved to Desktop"
        content.body = "The configured save folder was unavailable. Saved to \(desktopPath) instead."
        content.categoryIdentifier = "ss.capture.fallback"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "ss.capture.fallback.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    func postSaveFailedNotification(primaryPath: String) {
        let content = UNMutableNotificationContent()
        content.title = "Screenshot Save Failed"
        content.body = "Could not save to \(primaryPath) or Desktop. Check Console.app (subsystem com.simplescreenapp.SimpleScreen) for details."
        content.categoryIdentifier = "ss.capture.save-failed"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "ss.capture.save-failed.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    func postSelectionTooSmallNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Selection Too Small"
        content.body = "The selected area was too small — capture cancelled."
        content.categoryIdentifier = "ss.area.too-small"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "ss.area.too-small.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    func postCopiedNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Screenshot Copied"
        content.body = "Screenshot copied to clipboard"
        content.categoryIdentifier = "ss.capture.copy"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "ss.capture.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
