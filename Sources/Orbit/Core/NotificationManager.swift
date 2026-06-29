import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    private init() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        center.add(request)
    }
}
