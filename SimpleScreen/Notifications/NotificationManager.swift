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
