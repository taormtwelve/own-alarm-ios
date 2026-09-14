import Foundation
import Combine

/// Owns the alarms, the settings and the tone library, persists them to disk, and
/// keeps the notification schedule in step with every edit.
@MainActor
final class AlarmStore: ObservableObject {
    @Published private(set) var alarms: [Alarm] = []
    @Published var settings = AppSettings() {
        didSet {
            persistSettings()
            // Notifications and Lock Screen alerts are written in the app's language.
            scheduler.language = settings.language
        }
    }
    @Published private(set) var tones: [AlarmTone] = AlarmTone.bundled

    /// Set when an alarm fires while the app is in the foreground, or when the user
    /// taps its notification — drives the ringing presentation.
    @Published var ringing: Alarm?

    /// When a test ring is due, while one is pending.
    @Published private(set) var testRingsAt: Date?

    /// The last test ring could not be set up: neither Alarms nor Notifications may
    /// ring for this app. Said on screen rather than counting down to silence.
    @Published private(set) var testBlocked = false

    /// A test that came due while the app was open on the notification route. A real
    /// alarm rings inside the app there (media volume, through Silent), so the test
    /// does too: the root view plays it while this is set.
    @Published private(set) var testRingingInApp: Alarm?

    /// How far ahead a test ring is set: long enough to lock the phone and hear it
    /// as the Lock Screen alarm.
    static let testLead: TimeInterval = 5

    /// How long a test ringing inside the app lasts before it stops by itself.
    static let testInAppSeconds: TimeInterval = 30

    /// The copy the pending test rings with.
    private var pendingTest: Alarm?
    private var testClear: DispatchWorkItem?
    private var testInAppStop: DispatchWorkItem?

    private let scheduler: AlarmScheduling
    private let fileURL: URL
    private let defaults: UserDefaults
    private let seed: [Alarm]
    private let settingsKey = AppSettings.storageKey
    private let tonesKey = "ownalarm.importedTones"

    /// `fileURL` and `defaults` are injectable so tests — and UI-test launches —
    /// get their own storage instead of trampling the real app's data.
    /// `seed` fills an empty store on first launch; the real app passes nothing,
    /// so a new user starts with no alarms they did not set themselves.
    init(scheduler: AlarmScheduling = AlarmScheduler.makeDefault(),
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
        scheduler.language = settings.language
        scheduler.onFinished = { [weak self] id in
            Task { @MainActor in self?.alarmFinished(id) }
        }
    }

    /// The system reports this alarm has rung and been stopped. A one-shot alarm has
    /// done its job and switches off; a repeating one stays armed for its next day.
    /// A snoozed alarm never arrives here — it is still counting down.
    func alarmFinished(_ id: UUID) {
        guard let alarm = alarm(withID: id), alarm.repeatDays.isEmpty, alarm.isEnabled else { return }
        setEnabled(false, for: alarm)
    }

    /// A store backed by a throwaway directory. Used when the app launches under
    /// `-uitesting` so the UI suite sees a known state every run.
    static func ephemeral(scheduler: AlarmScheduling = AlarmScheduler.makeDefault(),
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

    /// Saving from the editor. Stores the alarm, then remembers its volume, sound,
    /// snooze and vibration as the starting point for the next new alarm, so a
    /// routine is set up once rather than re-dialled every time. Switching an alarm
    /// on or off goes through `setEnabled` and deliberately does not count.
    func save(_ alarm: Alarm, isNew: Bool) {
        if isNew { add(alarm) } else { update(alarm) }

        var remembered = settings.defaults
        remembered.volume = alarm.volume
        remembered.toneID = alarm.toneID
        remembered.snoozeMinutes = alarm.snoozeMinutes
        remembered.vibrates = alarm.vibrates
        settings.defaults = remembered   // one write, one persist
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
        // The file behind this name may just have been replaced; copies rendered
        // from the old one must not keep ringing.
        ScaledSound.discardCopies(of: tone.id)
        guard !tones.contains(where: { $0.id == tone.id }) else {
            rescheduleAll()   // renders fresh copies from the new file
            return
        }
        tones.append(tone)
        persistTones()
    }

    // MARK: Test ring

    /// A throwaway copy of `alarm` to ring as a test: its own id, so nothing done to
    /// the test — Stop, Snooze, finishing — reaches the real alarm; no snooze, since
    /// there is nothing to come back to; and named as a test.
    nonisolated static func testCopy(of alarm: Alarm, language: AppLanguage) -> Alarm {
        var test = alarm
        test.id = UUID()
        test.snoozeMinutes = 0
        test.task = language("Test · {0}", alarm.task.isEmpty ? language("Alarm") : alarm.task)
        return test
    }

    /// Rings `alarm` for real in `testLead` seconds — its tone at its level, through
    /// the same route as the scheduled alarm — without touching the alarm itself.
    /// The alarm need not be saved: the editor passes what is on screen.
    func testRing(_ alarm: Alarm) {
        stopTestInApp()
        let test = Self.testCopy(of: alarm, language: settings.language)
        pendingTest = test
        testBlocked = false
        scheduler.scheduleTest(test, tone: tone(for: alarm), in: Self.testLead)
        testRingsAt = Date().addingTimeInterval(Self.testLead)
        testClear?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.testRingsAt = nil }
        testClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.testLead, execute: work)

        // Without permission nothing will ring; say so instead of counting down.
        Task { [weak self, scheduler] in
            guard await !scheduler.canRingTest() else { return }
            guard let self, self.pendingTest?.id == test.id else { return }
            self.cancelTestRing()
            self.testBlocked = true
        }
    }

    func cancelTestRing() {
        scheduler.cancelTest()
        pendingTest = nil
        testClear?.cancel()
        testClear = nil
        testRingsAt = nil
        stopTestInApp()
    }

    /// The pending test came due while the app was open, on the notification route:
    /// it rings in the app, as a real alarm would there. False when no test is
    /// pending — one already cancelled — so the caller can let the notification be.
    @discardableResult
    func testArrivedInApp() -> Bool {
        guard let test = pendingTest else { return false }
        pendingTest = nil
        testClear?.cancel()
        testClear = nil
        testRingsAt = nil
        testRingingInApp = test
        testInAppStop?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stopTestInApp() }
        testInAppStop = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.testInAppSeconds, execute: work)
        return true
    }

    func stopTestInApp() {
        testInAppStop?.cancel()
        testInAppStop = nil
        testRingingInApp = nil
    }

    // MARK: Ringing

    func snooze(_ alarm: Alarm) {
        ringing = nil
        scheduler.scheduleSnooze(alarm, tone: tone(for: alarm), minutes: alarm.snoozeMinutes)
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

    /// What the user did with an alarm's notification. Tapping it opens the ringing
    /// screen; the buttons snooze or stop. An alarm deleted since is ignored.
    func respond(_ response: AlarmResponse, toAlarmWithID id: UUID) {
        guard let alarm = alarm(withID: id) else { return }
        switch response {
        case .open: ringing = alarm
        case .snooze: snooze(alarm)
        case .stop: stop(alarm)
        }
    }

    // MARK: Scheduling

    func rescheduleAll() {
        scheduler.cancelAll(alarms)
        for alarm in alarms where alarm.isEnabled {
            scheduler.schedule(alarm, tone: tone(for: alarm), showOnLockScreen: settings.showOnLockScreen)
        }
        discardUnusedSounds()
    }

    /// Scaled copies nothing will ring — levels tested but never saved, alarms since
    /// changed or deleted — are deleted, so Library/Sounds does not grow with every
    /// test. Runs after a re-arm, once every copy in use has been rendered.
    private func discardUnusedSounds() {
        var keep = Set(alarms.filter(\.isEnabled).map { ScaledSound.name(for: tone(for: $0), volume: $0.volume) })
        // Critical alerts play an imported tone from its full-level copy.
        keep.formUnion(tones.filter { $0.source == .imported }.map { ScaledSound.name(for: $0, volume: 1) })
        for test in [pendingTest, testRingingInApp].compactMap({ $0 }) {
            keep.insert(ScaledSound.name(for: tone(for: test), volume: test.volume))
        }
        ScaledSound.discardCopies(except: keep)
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
        } else {
            // First launch: the language just taken from the phone stays the app's
            // until it is changed in Settings.
            persistSettings()
        }

        if let data = defaults.data(forKey: tonesKey),
           let imported = try? JSONDecoder().decode([AlarmTone].self, from: data) {
            tones = AlarmTone.bundled + imported
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

    private func persistTones() {
        guard let data = try? JSONEncoder().encode(tones.filter { $0.source == .imported }) else { return }
        defaults.set(data, forKey: tonesKey)
    }
}
