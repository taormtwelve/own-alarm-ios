import Foundation
import Combine

/// Owns the alarms, the settings and the tone library, persists them to disk, and
/// keeps the notification schedule in step with every edit.
@MainActor
final class AlarmStore: ObservableObject {
    @Published private(set) var alarms: [Alarm] = []
    @Published var settings = AppSettings() { didSet { persistSettings() } }
    @Published private(set) var tones: [AlarmTone] = AlarmTone.bundled

    /// Set when an alarm fires while the app is in the foreground, or when the user
    /// taps its notification — drives the ringing presentation.
    @Published var ringing: Alarm?

    private let scheduler: AlarmScheduling
    private let fileURL: URL
    private let defaults: UserDefaults
    private let seed: [Alarm]
    private let settingsKey = "ownalarm.settings"

    /// `fileURL` and `defaults` are injectable so tests — and UI-test launches —
    /// get their own storage instead of trampling the real app's data.
    /// `seed` fills an empty store on first launch; the real app passes nothing,
    /// so a new user starts with no alarms they did not set themselves.
    init(scheduler: AlarmScheduling = AlarmScheduler(),
         fileURL: URL? = nil,
         defaults: UserDefaults = .standard,
         seed: [Alarm] = []) {
        self.scheduler = scheduler
        self.defaults = defaults
        self.seed = seed
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("alarms.json")
        load()
    }

    /// A store backed by a throwaway directory. Used when the app launches under
    /// `-uitesting` so the UI suite sees a known state every run.
    static func ephemeral(scheduler: AlarmScheduling = AlarmScheduler(),
                          seed: [Alarm] = Alarm.starter) -> AlarmStore {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OwnAlarmTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = UserDefaults(suiteName: "ownalarm.ephemeral.\(UUID().uuidString)") ?? .standard
        return AlarmStore(scheduler: scheduler,
                          fileURL: folder.appendingPathComponent("alarms.json"),
                          defaults: suite,
                          seed: seed)
    }

    // MARK: Derived

    var sortedAlarms: [Alarm] {
        alarms.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    var enabledCount: Int { alarms.filter(\.isEnabled).count }

    /// The alarm that will go off soonest, with its fire date.
    var nextAlarm: (alarm: Alarm, date: Date)? {
        alarms
            .compactMap { alarm in alarm.nextFireDate().map { (alarm, $0) } }
            .min { $0.1 < $1.1 }
    }

    func tone(for alarm: Alarm) -> AlarmTone {
        AlarmTone.tone(id: alarm.toneID, in: tones)
    }

    /// How many alarms use a given tone — shown in the Sounds tab.
    func usageCount(of tone: AlarmTone) -> Int {
        alarms.filter { $0.toneID == tone.id }.count
    }

    // MARK: Mutation

    func add(_ alarm: Alarm) {
        alarms.append(alarm)
        persist()
        reschedule(alarm)
    }

    func update(_ alarm: Alarm) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[index] = alarm
        persist()
        reschedule(alarm)
    }

    func delete(_ alarm: Alarm) {
        alarms.removeAll { $0.id == alarm.id }
        persist()
        scheduler.cancel(alarm)
    }

    func delete(at offsets: IndexSet, in list: [Alarm]) {
        offsets.map { list[$0] }.forEach(delete)
    }

    func setEnabled(_ isEnabled: Bool, for alarm: Alarm) {
        var copy = alarm
        copy.isEnabled = isEnabled
        update(copy)
    }

    func addImportedTone(_ tone: AlarmTone) {
        guard !tones.contains(where: { $0.id == tone.id }) else { return }
        tones.append(tone)
    }

    // MARK: Ringing

    func snooze(_ alarm: Alarm) {
        ringing = nil
        var copy = alarm
        if alarm.louderAfterSnooze {
            copy.volume = min(1.0, alarm.volume + 0.10)
        }
        scheduler.scheduleSnooze(copy, minutes: alarm.snoozeMinutes)
    }

    func stop(_ alarm: Alarm) {
        ringing = nil
        scheduler.cancelSnooze(alarm)
        // A one-shot alarm has done its job; a repeating one stays armed.
        if alarm.repeatDays.isEmpty {
            setEnabled(false, for: alarm)
        }
    }

    func alarm(withID id: UUID) -> Alarm? {
        alarms.first { $0.id == id }
    }

    // MARK: Scheduling

    func rescheduleAll() {
        scheduler.cancelAll()
        for alarm in alarms where alarm.isEnabled {
            scheduler.schedule(alarm, tone: tone(for: alarm), showOnLockScreen: settings.showOnLockScreen)
        }
    }

    private func reschedule(_ alarm: Alarm) {
        scheduler.cancel(alarm)
        guard alarm.isEnabled else { return }
        scheduler.schedule(alarm, tone: tone(for: alarm), showOnLockScreen: settings.showOnLockScreen)
    }

    // MARK: Persistence

    private func load() {
        if let data = defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        }

        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Alarm].self, from: data) else {
            // First launch: empty for real users, who add their own. Only tests
            // and UI-test launches pass a seed.
            alarms = seed
            if !seed.isEmpty { persist() }
            return
        }
        alarms = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(alarms) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    private func persistSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: settingsKey)
    }
}
