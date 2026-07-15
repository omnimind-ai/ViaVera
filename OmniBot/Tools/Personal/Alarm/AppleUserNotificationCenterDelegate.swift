#if os(macOS)
import Foundation
import UserNotifications

/// Keeps macOS notification reminders visible when OmniBot is frontmost.
/// `UNUserNotificationCenter` retains its delegate weakly, so the alarm
/// service owns this instance for the service's full lifetime.
nonisolated final class AppleUserNotificationCenterDelegate:
    NSObject,
    UNUserNotificationCenterDelegate,
    @unchecked Sendable
{
    static let foregroundPresentationOptions: UNNotificationPresentationOptions = [
        .banner,
        .list,
        .sound,
    ]

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (
            UNNotificationPresentationOptions
        ) -> Void
    ) {
        _ = center
        _ = notification
        completionHandler(Self.foregroundPresentationOptions)
    }
}
#endif
