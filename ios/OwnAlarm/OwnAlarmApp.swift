import SwiftUI
import UserNotifications

@main
struct OwnAlarmApp: App {
    @StateObject private var store = OwnAlarmApp.makeStore()

    /// Real launches start with no alarms. Under UI test the app gets throwaway
    /// storage — seeded with sample alarms, or empty with `-emptyStore` — so the
    /// suite sees the same state every run and never touches real data.
    @MainActor
    private static func makeStore() -> AlarmStore {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uitesting") else { return AlarmStore() }
        return .ephemeral(seed: args.contains("-emptyStore") ? [] : Alarm.starter)
    }
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
                    notifications.store = store
                    UNUserNotificationCenter.current().delegate = notifications

                    // UI tests run without system permission prompts over the app.
                    if !ProcessInfo.processInfo.arguments.contains("-uitesting") {
                        _ = await AlarmScheduler.requestAuthorization()
                        #if canImport(AlarmKit)
                        if #available(iOS 26.0, *) {
                            // Real alarms: full screen on the Lock Screen, through Silent.
                            await AlarmKitScheduler.requestAuthorization()
                        }
                        #endif
                    }
                    store.rescheduleAll()
                }
                .onChange(of: scenePhase) { phase in
                    // Leaving the app silences previews immediately; a ringing
                    // alarm keeps going.
                    if phase != .active { player.appDidLeaveForeground() }
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
