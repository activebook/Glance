import AppKit
import UserNotifications

/// Dispatches native macOS completion & failure banners with actionable responses
/// ("Copy Translation" and "View in History").
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    enum ActionID {
        static let copyTranslation = "GLANCE_ACTION_COPY"
        static let viewSnapshot = "GLANCE_ACTION_VIEW"
    }

    enum CategoryID {
        static let translation = "GLANCE_CATEGORY_TRANSLATION"
    }

    var onOpenSnapshot: ((UUID) -> Void)?

    private override init() {
        super.init()
    }

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                NSLog("Glance: Notification authorization error: \(error)")
            } else {
                NSLog("Glance: Notification authorization granted: \(granted)")
            }
        }

        let copyAction = UNNotificationAction(
            identifier: ActionID.copyTranslation,
            title: "Copy Translation",
            options: []
        )

        let viewAction = UNNotificationAction(
            identifier: ActionID.viewSnapshot,
            title: "View in History",
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: CategoryID.translation,
            actions: [copyAction, viewAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([category])
    }

    // MARK: - Post Notifications

    func postSuccess(record: SnapshotRecord, playSound: Bool) {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "Glance Translation"

        if let endpoint = record.endpointLabel {
            let latencyStr = record.latencyMs.map { " · \($0) ms" } ?? ""
            content.subtitle = "\(endpoint)\(latencyStr)"
        }

        let primaryText = record.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        content.body = primaryText.isEmpty ? "(No text detected)" : primaryText
        content.categoryIdentifier = CategoryID.translation

        if playSound {
            content.sound = .default
        }

        content.userInfo = [
            "snapshotID": record.id.uuidString,
            "translatedText": record.translatedText
        ]

        let request = UNNotificationRequest(
            identifier: record.id.uuidString,
            content: content,
            trigger: nil // deliver immediately
        )

        center.add(request) { error in
            if let error {
                NSLog("Glance: failed to schedule notification: \(error)")
            }
        }
    }

    func postFailure(message: String, snapshotID: UUID?, playSound: Bool) {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "Glance Translation Failed"
        content.body = message
        content.categoryIdentifier = CategoryID.translation

        if playSound {
            content.sound = .default
        }

        if let snapshotID {
            content.userInfo = ["snapshotID": snapshotID.uuidString]
        }

        let request = UNNotificationRequest(
            identifier: (snapshotID ?? UUID()).uuidString,
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error {
                NSLog("Glance: failed to schedule failure notification: \(error)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Always present banner and sound even when Glance is active
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }

        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case ActionID.copyTranslation:
            if let text = userInfo["translatedText"] as? String, !text.isEmpty {
                DispatchQueue.main.async {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
        case ActionID.viewSnapshot:
            if let idString = userInfo["snapshotID"] as? String, let id = UUID(uuidString: idString) {
                DispatchQueue.main.async { [weak self] in
                    self?.onOpenSnapshot?(id)
                }
            }
        default:
            break
        }
    }
}
