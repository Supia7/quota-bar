import QuotaBarCore
import QuotaBarUI
import UserNotifications

@MainActor
final class QuotaResetNotifier {
    private let center = UNUserNotificationCenter.current()
    private var authorizationRequested = false

    func notify(_ events: [QuotaResetEvent]) {
        guard !events.isEmpty else { return }

        if authorizationRequested {
            addRequests(events, granted: true)
            return
        }

        authorizationRequested = true
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in
                self?.addRequests(events, granted: granted)
            }
        }
    }

    private func addRequests(_ events: [QuotaResetEvent], granted: Bool) {
        guard granted else { return }
        for event in events {
            let content = UNMutableNotificationContent()
            content.title = L10n.string("notification.quota_reset_title")
            content.body = L10n.resetNotice(event)
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "quotabar-reset-\(event.id)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
}
