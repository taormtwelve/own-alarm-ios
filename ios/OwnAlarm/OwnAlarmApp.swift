import SwiftUI
import UserNotifications

@main
struct OwnAlarmApp: App {
    @StateObject private var store = AlarmStore()
    @StateObject private var player = AlarmPlayer()
    private let notifications = NotificationRouter()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(player)
                .task {
                    AlarmScheduler.registerCategories()
                    _ = await AlarmScheduler.requestAuthorization()
                    notifications.store = store
                    UNUserNotificationCenter.current().delegate = notifications
                    store.rescheduleAll()
                }
                .onChange(of: scenePhase) { phase in
                    // Repeat triggers can drift after a long background spell or a
                    // time-zone change; re-arming on activation keeps them honest.
                    if phase == .active { store.rescheduleAll() }
                }
        }
    }
}

/// Bridges notification taps and action buttons back into the app's state.
///
/// The Lock Screen presentation in the design *is* this notification: its title,
/// body and the Stop / Snooze actions registered in `AlarmScheduler`. There is no
/// custom view for it — iOS owns that surface.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    weak var store: AlarmStore?

    /// Fired while the app is open: show our own ringing screen rather than a banner.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await route(notification.request.content, action: nil)
        return []
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await route(response.notification.request.content, action: response.actionIdentifier)
    }

    @MainActor
    private func route(_ content: UNNotificationContent, action: String?) {
        guard let store,
              let raw = content.userInfo["alarmID"] as? String,
              let id = UUID(uuidString: raw),
              let alarm = store.alarm(withID: id) else { return }

        switch action {
        case AlarmScheduler.snoozeAction:
            store.snooze(alarm)
        case AlarmScheduler.stopAction, UNNotificationDismissActionIdentifier:
            store.stop(alarm)
        default:
            store.ringing = alarm
        }
    }
}
