import FitnessCore
import Foundation
import UserNotifications

/// LiveContainer-safe local notification adapter for workout HR zone updates (zero ActivityKit / Live Activities).
final class LiveWorkoutNotificationDispatcher {
    static let shared = LiveWorkoutNotificationDispatcher()
    private init() {}

    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func postZoneEvent(_ event: WorkoutZoneNotificationEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        let request = UNNotificationRequest(
            identifier: "whoop-live-zone-banner",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
