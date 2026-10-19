import Foundation
import UserNotifications

/// Schedules the "rest is over" notification. iOS only shows it when the app
/// is in the background, because the app doesn't ask for foreground banners.
@MainActor
protocol RestNotifying: AnyObject {
    func scheduleRestEnd(at date: Date)
    func cancelRestEnd()
}

@MainActor
final class RestNotifier: RestNotifying {
    private static let identifier = "rest-timer"
    private let center = UNUserNotificationCenter.current()
    private var didRequestAuthorization = false

    func scheduleRestEnd(at date: Date) {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Rest is over")
        content.body = String(localized: "Time for your next set.")
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        Task {
            if !didRequestAuthorization {
                didRequestAuthorization = true
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            try? await center.add(request)
        }
    }

    func cancelRestEnd() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }
}

@MainActor
final class NoOpRestNotifier: RestNotifying {
    private(set) var scheduledDates: [Date] = []
    private(set) var cancelCount = 0

    func scheduleRestEnd(at date: Date) { scheduledDates.append(date) }
    func cancelRestEnd() { cancelCount += 1 }
}
