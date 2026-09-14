import AudioToolbox
import AVFoundation
import Combine

/// Plays the alarm itself while the app is open — the in-app ringing screen.
///
/// Hearing a level *before* it rings is not done here: no app can play a sound the
/// way the Lock Screen alarm will (at the Ringer & Alerts volume, through Silent).
/// So the app rings the real alarm instead, a few seconds ahead — `AlarmStore.testRing`.
///
/// An alarm ringing inside the app has to loop until stopped, fade in and ring
/// through Silent. It plays under `AVAudioSession(.playback)`, with `SystemVolume`
/// setting the phone's volume to the alarm's level and putting the user's own back
/// when it stops. A ringing alarm set to vibrate also buzzes, every
/// `vibrationInterval`, until it is stopped.
@MainActor
final class AlarmPlayer: ObservableObject {
    @Published private(set) var playingToneID: String?

    /// How often the phone buzzes while a vibrating alarm rings.
    static let vibrationInterval: TimeInterval = 1.6

    private var player: AVAudioPlayer?
    private var vibrationTimer: Timer?
    private let system: SystemVolume
    private let vibrate: () -> Void

    /// Tests pass their own `vibrate` to count buzzes; the app uses the real motor.
    init(system: SystemVolume = .shared,
         vibrate: @escaping () -> Void = { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }) {
        self.system = system
        self.vibrate = vibrate
    }

    /// One buzz — what switching Vibrate on in the editor feels like.
    func buzzOnce() {
        vibrate()
    }

    // MARK: Ringing

    func startRinging(_ alarm: Alarm, tone: AlarmTone) {
        play(tone,
             level: alarm.volume,
             fadeFrom: alarm.fadeInSeconds > 0 ? Alarm.fadeInFloor : nil,
             fadeSeconds: TimeInterval(alarm.fadeInSeconds))
        // Independent of the sound: an alarm that cannot play still buzzes.
        if alarm.vibrates { startVibrating() }
    }

    /// Stops the sound and the buzzing, and hands the phone's volume back.
    func stop() {
        vibrationTimer?.invalidate()
        vibrationTimer = nil
        player?.stop()
        player = nil
        playingToneID = nil
        system.restore()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Engine

    /// `level` is 0...1 of the phone's media volume. With `fadeFrom`, the player
    /// ramps from that fraction of the level up to all of it.
    private func play(_ tone: AlarmTone,
                      level: Double,
                      fadeFrom: Double?,
                      fadeSeconds: TimeInterval) {
        player?.stop()
        player = nil

        guard let url = tone.fileURL else {
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
}
