import Foundation

/// Stands in for the real schedulers when the app is launched for UI tests.
///
/// Nothing reaches the notification center or AlarmKit, so no real alarm — a sample
/// alarm whose time comes round, or a test ring — can go off in the middle of the
/// suite. Whether a test ring may sound is fixed by the launch (`-ringAllowed`), not by
/// whatever permissions the simulator happens to hold: CI's simulator allows
/// notifications, a fresh one does not.
final class UITestScheduler: AlarmScheduling {
    private let allowsRinging: Bool

    init(allowsRinging: Bool) {
        self.allowsRinging = allowsRinging
    }

    func schedule(_ alarm: Alarm, tone: AlarmTone, showOnLockScreen: Bool) {}
    func scheduleSnooze(_ alarm: Alarm, tone: AlarmTone, minutes: Int) {}
    func cancel(_ alarm: Alarm) {}
    func cancelSnooze(_ alarm: Alarm) {}
    func cancelAll(_ alarms: [Alarm]) {}
    func scheduleTest(_ alarm: Alarm, tone: AlarmTone, in seconds: TimeInterval) {}
    func cancelTest() {}
    func canRingTest() async -> Bool { allowsRinging }
}
