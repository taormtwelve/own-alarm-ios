import AVFoundation
import Combine

/// Plays tones in-app: the audition button in the Sounds tab, live feedback while a
/// volume slider is being dragged, and the alarm itself while the app is open.
///
/// Levels are shares of the iPhone's maximum. While a sound plays, `SystemVolume`
/// sets the phone's volume to the chosen level and the player runs at full scale on
/// top; the moment the sound ends — the finger lifts, the preview finishes, the alarm
/// is stopped, the app leaves the screen — the user's own volume is put back.
/// Previews play alongside other apps' audio rather than pausing it. `.playback` is
/// the session category that keeps sound coming through the Silent switch.
@MainActor
final class AlarmPlayer: ObservableObject {
    @Published private(set) var playingToneID: String?

    private var player: AVAudioPlayer?
    private var stopWork: DispatchWorkItem?
    private var isScrubbing = false
    /// True while an alarm — not a preview — is sounding.
    private var isRinging = false
    private let system: SystemVolume

    init(system: SystemVolume = .shared) {
        self.system = system
    }

    // MARK: Audition

    /// A short preview at the level given, so "60%" is something you can hear
    /// before relying on it.
    func preview(_ tone: AlarmTone, at volume: Double, seconds: TimeInterval = 6) {
        stopWork?.cancel()
        play(tone, level: volume, loops: 0, purpose: .preview)
        scheduleStop(after: seconds)
    }

    // MARK: Live slider feedback

    /// A finger lands on a volume slider: the phone's volume is remembered and the
    /// tone starts looping at the slider's level.
    func beginScrub(_ tone: AlarmTone, at volume: Double) {
        stopWork?.cancel()
        isScrubbing = true
        if playingToneID == tone.id, player?.isPlaying == true {
            system.takeOver(at: Float(volume))
        } else {
            play(tone, level: volume, loops: -1, purpose: .preview)
        }
    }

    /// Follows the slider — the phone's volume moves with it.
    func scrub(to volume: Double) {
        guard isScrubbing else { return }
        system.set(Float(volume))
    }

    /// The finger lifted: the final level rings for a moment, then the sound stops
    /// and the phone's own volume comes back.
    func endScrub() {
        isScrubbing = false
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
    }

    /// The app has left the screen — backgrounded, locked, or Control Center pulled
    /// down. Previews and slider feedback stop at once and the volume comes back. A
    /// ringing alarm keeps going: leaving the app must not be a way to silence it.
    func appDidLeaveForeground() {
        guard !isRinging else { return }
        stop()
    }

    func stop() {
        stopWork?.cancel()
        stopWork = nil
        isScrubbing = false
        isRinging = false
        player?.stop()
        player = nil
        playingToneID = nil
        // The user's own volume comes back the moment the sound ends.
        system.restore()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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

    private func scheduleStop(after seconds: TimeInterval) {
        stopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stop() }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func url(for tone: AlarmTone) -> URL? {
        tone.fileURL
    }
}
