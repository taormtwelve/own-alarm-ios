import Foundation

/// The two plans: free, which keeps up to three alarms, and membership — a yearly
/// subscription through the App Store — with no limit.
enum Plan: String, Codable, Equatable, Sendable {
    case free, member

    /// How many alarms the free plan keeps.
    static let freeAlarmLimit = 3

    /// Whether one more alarm can be created when `count` exist. Alarms over the
    /// limit, kept from a membership that has lapsed, stay and keep ringing; only new
    /// ones wait.
    func canAddAlarm(having count: Int) -> Bool {
        self == .member || count < Self.freeAlarmLimit
    }
}
