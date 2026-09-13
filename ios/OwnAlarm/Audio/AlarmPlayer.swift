import AudioToolbox
import AVFoundation
import Combine

/// Plays tones in-app: the audition button in the Sounds tab, live feedback while a
/// volume slider is being dragged, and the alarm itself while the app is open.
///
/// Previews — auditions and slider feedback — play the very sound the real alarm
/// rings with (`ScaledSound`) through System Sound Services, the player iOS uses for
/// alert sounds. It plays at the Ringer & Alerts volume, as AlarmKit and alarm
/// notifications do, so a level sounds the same while you choose it as when the
/// alarm goes off, and 100% is the loudest your ringer volume plays. Media volume is
/// never touched for a preview. The Silent switch mutes alert sounds, previews
/// included: the user chose that over a media-volume stand-in, which could not match
/// the real ring.
///
/// A system sound's volume is fixed, so a slider moving to a new level plays a new
/// copy — rendered from the point the old one had reached, so the tone carries on
/// at the new level instead of starting over.
///
/// An alarm ringing inside the app has to loop until stopped, fade in and ring
/// through Silent, which a system sound cannot. It plays under
/// `AVAudioSession(.playback)` instead, with `SystemVolume` setting the phone's
/// volume to the alarm's level and putting the user's own back when it stops.
///
/// A ringing alarm set to vibrate also buzzes, every `vibrationInterval`, until it
/// is stopped. Previews never vibrate.
@MainActor
final class AlarmPlayer: ObservableObject {
    @Published private(set) var playingToneID: String?

    /// The level, in percent, of the preview playing now.
    private(set) var previewPercent: Int?

    /// True after a preview ended the instant it started — the Silent switch is on
    /// (or there is no audio output), so alert sounds are muted. Cleared the moment a
    /// preview is heard again. Screens with a slider tell the user.
    @Published private(set) var previewMuted = false

    /// How long a slider can sit untouched before its sound stops by itself. iOS can
    /// cancel a drag — a scroll takes the finger over — without the slider ever
    /// reporting that it was let go, and the tone must not loop forever after that.
    static let scrubIdleTimeout: TimeInterval = 2

    /// How often slider feedback moves to a new level. Each move swaps in a copy at
    /// the new level, continuing from where the tone was; this keeps a fast drag from
    /// swapping every frame.
    static let scrubStepInterval: TimeInterval = 0.2

    /// How often the phone buzzes while a vibrating alarm rings.
    static let vibrationInterval: TimeInterval = 1.6

    private var player: AVAudioPlayer?
    /// The system sound playing a preview, and the throwaway copy it plays.
    private var previewSound: SystemSoundID?
    private var previewFile: URL?
    private var previewTone: AlarmTone?
    private var previewActive: Bool { previewSound != nil }
    private var lastPreviewStart = Date.distantPast
    /// Where in the tone the current copy began, and how long the copy runs before
    /// it loops — together they say where the tone is now.
    private var previewOffset: TimeInterval = 0
    private var previewPeriod: TimeInterval = 0
    private var pendingStep: DispatchWorkItem?
    private var stopWork: DispatchWorkItem?
    private var isScrubbing = false
    private var scrubTone: AlarmTone?
    private var scrubLevel: Double = 0
    /// True while an alarm — not a preview — is sounding.
    private var isRinging = false
    private var vibrationTimer: Timer?
    private let system: SystemVolume
    private let vibrate: () -> Void

    /// Tests pass their own `vibrate` to count buzzes; the app uses the real motor.
    init(system: SystemVolume = .shared,
         vibrate: @escaping () -> Void = { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }) {
        self.system = system
        self.vibrate = vibrate
    }

    // MARK: Audition

    /// A short preview at the level given — the real alarm's own sound — so "60%"
    /// is something you can hear before relying on it.
    func preview(_ tone: AlarmTone, at volume: Double, seconds: TimeInterval = 6) {
        stopWork?.cancel()
        playPreview(tone, at: volume)
        scheduleStop(after: seconds)
    }

    /// One buzz — what switching Vibrate on in the editor feels like.
    func buzzOnce() {
        vibrate()
    }

    // MARK: Live slider feedback

    /// A finger lands on a volume slider: the tone starts looping at its level.
    func beginScrub(_ tone: AlarmTone, at volume: Double) {
        isScrubbing = true
        scrubTone = tone
        scrubLevel = volume
        let alreadyPlaying = previewActive && playingToneID == tone.id
            && previewPercent == ScaledSound.percent(volume)
        if !alreadyPlaying { playPreview(tone, at: volume) }
        scheduleIdleSilence()
    }

    /// Follows the slider, a step at a time.
    func scrub(to volume: Double) {
        guard isScrubbing, let tone = scrubTone else { return }
        scrubLevel = volume
        if !previewActive {
            // Went quiet after sitting still; the finger is moving again.
            playPreview(tone, at: volume)
        } else {
            step()
        }
        scheduleIdleSilence()
    }

    /// The finger lifted: the level it let go at rings for a moment, then stops.
    func endScrub() {
        if isScrubbing { step(now: true) }
        isScrubbing = false
        scrubTone = nil
        scheduleStop(after: 0.8)
    }

    /// Moves the preview to the slider's level without starting the tone over: a copy
    /// at the new level takes over from where the tone is — now, or once the last
    /// swap is `scrubStepInterval` old, so a fast drag does not swap every frame.
    private func step(now: Bool = false) {
        pendingStep?.cancel()
        pendingStep = nil
        guard let tone = scrubTone, previewActive,
              ScaledSound.percent(scrubLevel) != previewPercent else { return }
        let wait = Self.scrubStepInterval - Date().timeIntervalSince(lastPreviewStart)
        if now || wait <= 0 {
            playPreview(tone, at: scrubLevel, from: previewPosition)
        } else {
            pendingStep = after(wait) { [weak self] in self?.step(now: true) }
        }
    }

    /// How far into the tone the preview is right now.
    private var previewPosition: TimeInterval {
        guard previewPeriod > 0 else { return 0 }
        return (previewOffset + Date().timeIntervalSince(lastPreviewStart))
            .truncatingRemainder(dividingBy: previewPeriod)
    }

    // MARK: Ringing

    func startRinging(_ alarm: Alarm, tone: AlarmTone) {
        stopWork?.cancel()
        play(tone,
             level: alarm.volume,
             fadeFrom: alarm.fadeInSeconds > 0 ? Alarm.fadeInFloor : nil,
             fadeSeconds: TimeInterval(alarm.fadeInSeconds))
        isRinging = true
        // Independent of the sound: an alarm that cannot play still buzzes.
        if alarm.vibrates { startVibrating() }
    }

    // MARK: Stopping

    /// Ends any preview or slider sound at once — the tab changed, another control
    /// was touched, the app left the screen. A ringing alarm is not a preview and
    /// keeps going: none of those must be a way to silence it.
    func stopPreviews() {
        guard !isRinging else { return }
        stop()
    }

    /// The app has left the screen — backgrounded, locked, or Control Center pulled
    /// down.
    func appDidLeaveForeground() {
        stopPreviews()
    }

    func stop() {
        stopWork?.cancel()
        stopWork = nil
        isScrubbing = false
        scrubTone = nil
        isRinging = false
        vibrationTimer?.invalidate()
        vibrationTimer = nil
        silence()
    }

    // MARK: Previews

    /// Starts the tone at `volume` — from its beginning, or from `offset` when a copy
    /// at a new level is taking over from the one playing.
    private func playPreview(_ tone: AlarmTone, at volume: Double, from offset: TimeInterval = 0) {
        guard let file = ScaledSound.previewFile(for: tone, volume: volume, startingAt: offset) else {
            print("AlarmPlayer could not render a preview of \(tone.id)")
            endPreview()
            playingToneID = nil
            return
        }
        var id: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(file as CFURL, &id) == kAudioServicesNoError else {
            try? FileManager.default.removeItem(at: file)
            endPreview()
            playingToneID = nil
            return
        }
        // The old copy stops only now the new one is ready, so the gap is as short
        // as it can be.
        endPreview()
        // Alert sounds follow the Ringer & Alerts volume only while the app has no
        // active audio session; one left active — by the in-app alarm, or a Silent
        // mode preview — would pull them onto media volume and make a preview
        // louder than the real ring. Release it before every preview.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        previewSound = id
        previewFile = file
        previewTone = tone
        previewPercent = ScaledSound.percent(volume)
        previewOffset = offset
        previewPeriod = min(ScaledSound.duration(of: tone) ?? ScaledSound.previewSeconds,
                            ScaledSound.previewSeconds)
        lastPreviewStart = Date()
        playingToneID = tone.id
        loop(id)
    }

    /// A system sound plays once. While its preview is still the current one — an
    /// audition's few seconds, a drag in progress — it goes round again. One that
    /// ended the instant it started is muted (the Silent switch, or no output): it is
    /// left alone, since looping it would only spin, and `previewMuted` says so.
    private func loop(_ id: SystemSoundID) {
        let started = Date()
        AudioServicesPlaySystemSoundWithCompletion(id) { [weak self] in
            Task { @MainActor in
                guard let self, self.previewSound == id else { return }
                let heard = Date().timeIntervalSince(started) > 0.2
                if self.previewMuted == heard { self.previewMuted = !heard }
                if heard { self.loop(id) }
            }
        }
    }

    /// Stops the preview and deletes its copy. Disposing of a system sound is how
    /// one is stopped part-way.
    private func endPreview() {
        pendingStep?.cancel()
        pendingStep = nil
        if let id = previewSound { AudioServicesDisposeSystemSoundID(id) }
        if let file = previewFile { try? FileManager.default.removeItem(at: file) }
        previewSound = nil
        previewFile = nil
        previewTone = nil
        previewPercent = nil
        previewOffset = 0
        previewPeriod = 0
    }

    // MARK: Ringing engine

    /// `level` is 0...1 of the phone's media volume. With `fadeFrom`, the player
    /// ramps from that fraction of the level up to all of it.
    private func play(_ tone: AlarmTone,
                      level: Double,
                      fadeFrom: Double?,
                      fadeSeconds: TimeInterval) {
        endPreview()
        player?.stop()
        player = nil

        guard let url = url(for: tone) else {
            assertionFailure("Missing audio file for tone \(tone.id)")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            // An alarm has to be heard: other audio dips while it rings and comes
            // back when it stops. `.playback` rings through the Silent switch.
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)

            // The phone's volume becomes the alarm's level; the player runs at full
            // scale on top.
            system.takeOver(at: Float(min(1, max(0, level))))

            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = Float(fadeFrom ?? 1)
            player.prepareToPlay()
            player.play()
            if fadeFrom != nil, fadeSeconds > 0 {
                player.setVolume(1, fadeDuration: fadeSeconds)
            }
            self.player = player
            playingToneID = tone.id
        } catch {
            print("AlarmPlayer could not start: \(error.localizedDescription)")
        }
    }

    /// Buzzes now, then every `vibrationInterval` until `stop()`.
    private func startVibrating() {
        vibrationTimer?.invalidate()
        let buzz = vibrate
        buzz()
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: Self.vibrationInterval,
                                              repeats: true) { _ in buzz() }
    }

    /// Stops every sound and hands the volume back, without touching the scrub state.
    private func silence() {
        endPreview()
        player?.stop()
        player = nil
        playingToneID = nil
        // After an alarm rang in the app, the user's own volume comes back.
        system.restore()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func scheduleStop(after seconds: TimeInterval) {
        schedule(after: seconds) { [weak self] in self?.stop() }
    }

    /// Goes quiet if the slider sits still, but stays ready: moving it again brings
    /// the sound back (see `scrub(to:)`).
    private func scheduleIdleSilence() {
        schedule(after: Self.scrubIdleTimeout) { [weak self] in self?.silence() }
    }

    private func schedule(after seconds: TimeInterval, _ body: @escaping () -> Void) {
        stopWork?.cancel()
        stopWork = after(seconds, body)
    }

    private func after(_ seconds: TimeInterval, _ body: @escaping () -> Void) -> DispatchWorkItem {
        let work = DispatchWorkItem(block: body)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        return work
    }

    private func url(for tone: AlarmTone) -> URL? {
        tone.fileURL
    }
}
