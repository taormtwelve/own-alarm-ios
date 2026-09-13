import AudioToolbox
import AVFoundation
import Combine

/// Plays tones in-app: the audition button in the Sounds tab, live feedback while a
/// volume slider is being dragged, and the alarm itself while the app is open.
///
/// Levels are shares of the iPhone's maximum. While a sound plays, `SystemVolume`
/// sets the phone's volume to the chosen level and the player runs at full scale on
/// top; the moment the sound ends — the finger lifts, the preview finishes, another
/// control is touched, the tab changes, the app leaves the screen, the alarm is
/// stopped — the user's own volume is put back. Previews play alongside other apps'
/// audio rather than pausing it. `.playback` keeps sound coming through Silent.
///
/// A ringing alarm set to vibrate also buzzes, every `vibrationInterval`, until it
/// is stopped. Previews never vibrate.
@MainActor
final class AlarmPlayer: ObservableObject {
    @Published private(set) var playingToneID: String?

    /// How long a slider can sit untouched before its sound stops by itself. iOS can
    /// cancel a drag — a scroll takes the finger over — without the slider ever
    /// reporting that it was let go, and the tone must not loop forever after that.
    static let scrubIdleTimeout: TimeInterval = 2

    /// How often the phone buzzes while a vibrating alarm rings.
    static let vibrationInterval: TimeInterval = 1.6

    private var player: AVAudioPlayer?
    private var stopWork: DispatchWorkItem?
    private var isScrubbing = false
    private var scrubTone: AlarmTone?
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

    /// A short preview at the level given, so "60%" is something you can hear
    /// before relying on it.
    func preview(_ tone: AlarmTone, at volume: Double, seconds: TimeInterval = 6) {
        stopWork?.cancel()
        play(tone, level: volume, loops: 0, purpose: .preview)
        scheduleStop(after: seconds)
    }

    /// One buzz — what switching Vibrate on in the editor feels like.
    func buzzOnce() {
        vibrate()
    }

    // MARK: Live slider feedback

    /// A finger lands on a volume slider: the phone's volume is remembered and the
    /// tone starts looping at the slider's level.
    func beginScrub(_ tone: AlarmTone, at volume: Double) {
        isScrubbing = true
        scrubTone = tone
        if playingToneID == tone.id, player?.isPlaying == true {
            system.takeOver(at: Float(volume))
        } else {
            play(tone, level: volume, loops: -1, purpose: .preview)
        }
        scheduleIdleSilence()
    }

    /// Follows the slider — the phone's volume moves with it.
    func scrub(to volume: Double) {
        guard isScrubbing, let tone = scrubTone else { return }
        if player == nil {
            // Went quiet after sitting still; the finger is moving again.
            play(tone, level: volume, loops: -1, purpose: .preview)
        } else {
            system.set(Float(volume))
        }
        scheduleIdleSilence()
    }

    /// The finger lifted: the final level rings for a moment, then the sound stops
    /// and the phone's own volume comes back.
    func endScrub() {
        isScrubbing = false
        scrubTone = nil
        scheduleStop(after: 0.8)
    }

    // MARK: Ringing

    func startRinging(_ alarm: Alarm, tone: AlarmTone) {
        stopWork?.cancel()
        play(tone,
             level: alarm.volume,
             loops: -1,
             purpose: .alarm,
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

    // MARK: Engine

    private enum Purpose {
        /// Plays alongside other apps' audio.
        case preview
        /// An alarm has to be heard: other audio dips while it rings and comes back
        /// when it stops.
        case alarm
    }

    /// `level` is 0...1 of the phone's maximum. With `fadeFrom`, the player ramps
    /// from that fraction of the level up to all of it.
    private func play(_ tone: AlarmTone,
                      level: Double,
                      loops: Int,
                      purpose: Purpose,
                      fadeFrom: Double? = nil,
                      fadeSeconds: TimeInterval = 0) {
        // Stop the previous sound without restoring the volume — the level the user
        // had before *any* of our playback is the one to go back to.
        player?.stop()
        player = nil

        guard let url = url(for: tone) else {
            assertionFailure("Missing audio file for tone \(tone.id)")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback,
                                    mode: .default,
                                    options: purpose == .alarm ? [.duckOthers] : [.mixWithOthers])
            try session.setActive(true)

            // The phone's volume becomes the chosen level; the player runs at full
            // scale on top, so 60% is 60% of the device's maximum.
            system.takeOver(at: Float(min(1, max(0, level))))

            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = loops
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

    /// Stops the sound and hands the volume back, without touching the scrub state.
    private func silence() {
        player?.stop()
        player = nil
        playingToneID = nil
        // The user's own volume comes back the moment the sound ends.
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
        let work = DispatchWorkItem(block: body)
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func url(for tone: AlarmTone) -> URL? {
        tone.fileURL
    }
}
