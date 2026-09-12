import AVFoundation
import Combine

/// Plays tones in-app: the audition button in the Sounds tab, live feedback while a
/// volume slider is being dragged, and the alarm itself while the app is open.
///
/// Levels are absolute — 100% is the iPhone's maximum output, whatever the volume
/// buttons were left at. `SystemVolume` sets the device to the requested level, the
/// player runs at full scale, and the user's own level comes back when we stop.
/// `.playback` is the session category that keeps sound coming through the Silent
/// switch.
@MainActor
final class AlarmPlayer: ObservableObject {
    @Published private(set) var playingToneID: String?

    private var player: AVAudioPlayer?
    private var stopWork: DispatchWorkItem?
    private var isScrubbing = false
    private let system = SystemVolume.shared

    // MARK: Audition

    /// A short preview at exactly the level given, so "60%" is something you can
    /// hear before relying on it.
    func preview(_ tone: AlarmTone, at volume: Double, seconds: TimeInterval = 6) {
        stopWork?.cancel()
        play(tone, level: volume, loops: 0)
        scheduleStop(after: seconds)
    }

    // MARK: Live slider feedback

    /// Called when a finger lands on a volume slider: starts the tone looping.
    func beginScrub(_ tone: AlarmTone, at volume: Double) {
        stopWork?.cancel()
        isScrubbing = true
        if playingToneID == tone.id, player?.isPlaying == true {
            system.set(Float(volume))
        } else {
            play(tone, level: volume, loops: -1)
        }
    }

    /// Follows the slider as it moves — what you hear is the level you are setting.
    func scrub(to volume: Double) {
        guard isScrubbing else { return }
        system.set(Float(volume))
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
             fadeFrom: alarm.fadeInSeconds > 0 ? Alarm.fadeInFloor : nil,
             fadeSeconds: TimeInterval(alarm.fadeInSeconds))
    }

    func stop() {
        stopWork?.cancel()
        stopWork = nil
        isScrubbing = false
        player?.stop()
        player = nil
        playingToneID = nil
        system.restore()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Engine

    /// `level` is the absolute output, 0...1 of the device maximum. With `fadeFrom`,
    /// the player ramps from that fraction of the level up to all of it.
    private func play(_ tone: AlarmTone,
                      level: Double,
                      loops: Int,
                      fadeFrom: Double? = nil,
                      fadeSeconds: TimeInterval = 0) {
        // Stop the previous sound without restoring the system level — that keeps
        // the level the user had before *any* of our playback as the one to return to.
        player?.stop()
        player = nil

        guard let url = url(for: tone) else {
            assertionFailure("Missing audio file for tone \(tone.id)")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
            system.takeOver(at: Float(level))

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
