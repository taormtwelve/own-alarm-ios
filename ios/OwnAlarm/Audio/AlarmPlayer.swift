import AVFoundation
import Combine

/// Plays a tone in-app: the audition button in the Sounds tab, and the alarm itself
/// while the app is in the foreground.
///
/// `.playback` is the category that keeps sound coming through the Silent switch,
/// and `setVolume(_:fadeDuration:)` gives the fade-in for free rather than us
/// stepping a timer.
@MainActor
final class AlarmPlayer: ObservableObject {
    @Published private(set) var playingToneID: String?

    private var player: AVAudioPlayer?
    private var stopWork: DispatchWorkItem?

    // MARK: Audition

    /// Plays a short preview at exactly the level the alarm is set to, so "60%" is
    /// something you can hear before you rely on it.
    func preview(_ tone: AlarmTone, at volume: Double, seconds: TimeInterval = 6) {
        play(tone, volume: volume, fadeInSeconds: 0, loops: 0)
        playingToneID = tone.id

        stopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stop() }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: Ringing

    func startRinging(_ alarm: Alarm, tone: AlarmTone) {
        play(tone,
             volume: alarm.volume,
             fadeInSeconds: TimeInterval(alarm.fadeInSeconds),
             loops: -1,
             startingAt: alarm.startingVolume)
        playingToneID = tone.id
    }

    func stop() {
        stopWork?.cancel()
        stopWork = nil
        player?.stop()
        player = nil
        playingToneID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Engine

    private func play(_ tone: AlarmTone,
                      volume: Double,
                      fadeInSeconds: TimeInterval,
                      loops: Int,
                      startingAt startVolume: Double? = nil) {
        stop()

        guard let url = url(for: tone) else {
            assertionFailure("Missing audio file for tone \(tone.id)")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            // .playback ignores the Silent switch; .duckOthers lowers music instead
            // of stopping it dead.
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = loops
            player.volume = Float(startVolume ?? volume)
            player.prepareToPlay()
            player.play()

            if fadeInSeconds > 0 {
                player.setVolume(Float(volume), fadeDuration: fadeInSeconds)
            }
            self.player = player
        } catch {
            print("AlarmPlayer could not start: \(error.localizedDescription)")
        }
    }

    private func url(for tone: AlarmTone) -> URL? {
        switch tone.source {
        case .bundled, .system:
            let name = (tone.fileName as NSString).deletingPathExtension
            let ext = (tone.fileName as NSString).pathExtension
            return Bundle.main.url(forResource: name, withExtension: ext.isEmpty ? "wav" : ext)
        case .imported:
            // Imported files are copied into Application Support on import.
            return FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Tones", isDirectory: true)
                .appendingPathComponent(tone.fileName)
        }
    }
}
