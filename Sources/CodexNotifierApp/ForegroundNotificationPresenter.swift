import Foundation
import CodexNotifierCore
import UserNotifications

final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let presentationOptions: UNNotificationPresentationOptions = [.banner, .list, .sound]
    static let focusActionIdentifier = "codex-notifier.focus"
    static let focusCategoryIdentifier = "codex-notifier.focus"

    static var notificationCategory: UNNotificationCategory {
        let focusAction = UNNotificationAction(
            identifier: focusActionIdentifier,
            title: "보기",
            options: [.foreground]
        )
        return UNNotificationCategory(
            identifier: focusCategoryIdentifier,
            actions: [focusAction],
            intentIdentifiers: [],
            options: []
        )
    }

    var onFocusRequested: ((MacOSFocusTarget) -> Void)?

    static func shouldRequestFocus(actionIdentifier: String) -> Bool {
        actionIdentifier == UNNotificationDefaultActionIdentifier
            || actionIdentifier == focusActionIdentifier
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Self.presentationOptions)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard Self.shouldRequestFocus(actionIdentifier: response.actionIdentifier),
              let focusTarget = MacOSNotificationFocusUserInfo.focusTarget(
                from: response.notification.request.content.userInfo
              ) else {
            return
        }

        onFocusRequested?(focusTarget)
    }
}
