import SwiftUI
import UIKit
import UserNotifications

@main
struct OwnAlarmApp: App {
    @StateObject private var store = OwnAlarmApp.makeStore()
    @StateObject private var player = AlarmPlayer()
    private let notifications = NotificationRouter()

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // UI tests do not need to watch sheets slide in and out; skipping the
        // animations takes a real bite out of the suite's run time.
        if ProcessInfo.processInfo.arguments.contains("-uitesting") {
            UIView.setAnimationsEnabled(false)
        }
    }

    /// Real launches start with no alarms. Under UI test the app gets throwaway
    /// storage — seeded with sample alarms, or empty with `-emptyStore` — so the
    /// suite sees the same state every run and never touches real data.
    @MainActor
    private static func makeStore() -> AlarmStore {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uitesting") else { return AlarmStore() }
        let store = AlarmStore.ephemeral(seed: args.contains("-emptyStore") ? [] : Alarm.starter)
        // The suite reads English whatever the simulator's language; the language
        // test switches to Thai in Settings.
        store.settings.language = .english
        // The four sample alarms already exceed the Free limit, and most of the
        // suite is not testing that limit — it runs as Premium. A dedicated launch
        // argument switches to Free for the paywall's own tests.
        store.settings.subscriptionTier = args.contains("-freeTier") ? .free : .premium
        return store
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(player)
                .task {
                    // Closed last time while it had the phone's volume? Put it back.
                    SystemVolume.shared.recoverIfNeeded()
                    AlarmScheduler.registerCategories(language: store.settings.language)
                    notifications.store = store
                    UNUserNotificationCenter.current().delegate = notifications

                    let args = ProcessInfo.processInfo.arguments
                    // UI tests run without system permission prompts over the app.
                    if !args.contains("-uitesting") {
                        _ = await AlarmScheduler.requestAuthorization()
                        #if canImport(AlarmKit)
                        if #available(iOS 26.0, *) {
                            // Real alarms: full screen on the Lock Screen, through Silent.
                            await AlarmKitScheduler.requestAuthorization()
                        }
                        #endif
                        // Confirms the plan with the App Store before anything checks
                        // the free limit — skipped under UI test, which fixes its own
                        // plan above rather than asking a StoreKit with nothing to sell.
                        await store.refreshSubscriptionStatus()
                    }
                    store.rescheduleAll()

                    // UI tests of the ringing screen open it for the first alarm.
                    if args.contains("-uitesting"), args.contains("-ringFirstAlarm") {
                        store.ringing = store.sortedAlarms.first
                    }
                }
                .onChange(of: scenePhase) { phase in
                    // Leaving the app ends a preview at once; an alarm keeps ringing.
                    if phase != .active { player.stopPreview() }
                    // Repeat triggers can drift after a long background spell or a
                    // time-zone change; re-arming on activation keeps them honest.
                    if phase == .active { store.rescheduleAll() }
                }
        }
    }
}

/// Bridges notification taps and action buttons back into the app's state. What
/// each one *does* lives in `AlarmStore.respond`, where it can be tested.
///
/// On iOS 16–25 the Lock Screen presentation is this notification: its title, body
/// and the Stop / Snooze actions registered in `AlarmScheduler`. On iOS 26 AlarmKit
/// owns the Lock Screen instead.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    weak var store: AlarmStore?

    /// Fired while the app is open. An alarm shows our own ringing screen rather than
    /// a banner; a test ring rings in the app too, as a real alarm would here; anything
    /// else — the "snoozed" notice — shows as a normal banner.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let content = notification.request.content
        guard content.userInfo["alarmID"] != nil else {
            guard content.userInfo["test"] as? Bool == true else { return [.banner, .list] }
            // A test nobody is waiting for any more is just a notification.
            return await testArrived() ? [] : [.banner, .list, .sound]
        }
        await route(content, action: nil)
        return []
    }

    @MainActor
    private func testArrived() -> Bool {
        store?.testArrivedInApp() ?? false
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await route(response.notification.request.content, action: response.actionIdentifier)
    }

    @MainActor
    private func route(_ content: UNNotificationContent, action: String?) async {
        guard let raw = content.userInfo["alarmID"] as? String,
              let id = UUID(uuidString: raw) else { return }
        let response = AlarmResponse(actionIdentifier: action)
        // The ringing screen is a full-screen cover on the root view, and SwiftUI
        // cannot present it over an open sheet — the editor, the sound picker. Close
        // those first, or the alarm would arrive with nothing on screen.
        if response == .open { await Self.closeSheets() }
        store?.respond(response, toAlarmWithID: id)
    }

    @MainActor
    private static func closeSheets() async {
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        guard let root, root.presentedViewController != nil else { return }
        await withCheckedContinuation { done in
            root.dismiss(animated: false) { done.resume() }
        }
    }
}
