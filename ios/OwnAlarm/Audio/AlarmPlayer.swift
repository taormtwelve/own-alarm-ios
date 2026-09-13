import AVFoundation
import Combine

/// Plays tones in-app: the audition button in the Sounds tab, live feedback while a
/// volume slider is being dragged, and the alarm itself while the app is open.
///
/// Other apps are left alone. The app never changes the iPhone's volume — iOS has one
/// media volume shared by every app, so changing it would change theirs — and
/// previews mix with whatever else is playing instead of lowering it. Levels are
/// therefore relative to the iPhone's own volume. `.playback` is the session category
/// that keeps sound coming through the Silent switch.
@MainActor
final class AlarmPlayer: ObservableObject {
    @Published private(set) var playingToneID: String?

    private var player: AVAudioPlayer?
    private var stopWork: DispatchWorkItem?
    private var isScrubbing = false
    /// True while an alarm — not a preview — is sounding.
    private var isRinging = false

    // MARK: Audition

    /// A short preview at the level given, so "60%" is something you can hear
    /// before relying on it.
    func preview(_ tone: AlarmTone, at volume: Double, seconds: TimeInterval = 6) {
        stopWork?.cancel()
        play(tone, level: volume, loops: 0, purpose: .preview)
        scheduleStop(after: seconds)
    }

    // MARK: Live slider feedback

    /// Called when a finger lands on a volume slider: starts the tone looping.
    func beginScrub(_ tone: AlarmTone, at volume: Double) {
        stopWork?.cancel()
        isScrubbing = true
        if playingToneID == tone.id, let player, player.isPlaying {
            player.volume = Float(volume)
        } else {
            play(tone, level: volume, loops: -1, purpose: .preview)
        }
    }

    /// Follows the slider as it moves — what you hear is the level you are setting.
    func scrub(to volume: Double) {
        guard isScrubbing else { return }
        player?.volume = Float(min(1, max(0, volume)))
    }

    /// The finger lifted: let the final level ring for a moment, then stop.
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
    /// down. Previews and slider feedback stop at once. A ringing alarm keeps going:
    /// leaving the app must not be a way to silence it.
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
        // Hands audio back to other apps at their own level.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Engine

    private enum Purpose {
        /// Plays alongside other apps' audio, which is left exactly as it was.
        case preview
        /// An alarm has to be heard: other audio dips while it rings and comes back
        /// when it stops.
        case alarm
    }

    /// `level` is 0...1 of the iPhone's current volume. With `fadeFrom`, the player
    /// ramps from that fraction of the level up to all of it.
    private func play(_ tone: AlarmTone,
                      level: Double,
                      loops: Int,
                      purpose: Purpose,
                      fadeFrom: Double? = nil,
                      fadeSeconds: TimeInterval = 0) {
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

            let target = Float(min(1, max(0, level)))
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = loops
            player.volume = fadeFrom.map { target * Float($0) } ?? target
            player.prepareToPlay()
            player.play()
            if fadeFrom != nil, fadeSeconds > 0 {
                player.setVolume(target, fadeDuration: fadeSeconds)
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
