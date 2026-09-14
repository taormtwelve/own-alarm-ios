import AudioToolbox
import AVFoundation
import Combine

/// Plays sound inside the app: the alarm itself while the app is open — the in-app
/// ringing screen, or a test ring that comes due there — and a short preview of a
/// tone as it is picked.
///
/// A picked tone is previewed as media: at the phone's media volume as it is, never
/// changed, only so the sound can be recognised. The level is heard truly by ringing
/// the real alarm a few seconds ahead — `AlarmStore.testRing` — since no app can play
/// a sound the way the Lock Screen alarm will.
///
/// An alarm ringing inside the app has to loop until stopped and ring through
/// Silent. It plays under `AVAudioSession(.playback)`, with `SystemVolume` setting the
/// phone's volume to the alarm's level and putting the user's own back when it stops.
/// One set to vibrate also buzzes, every `vibrationInterval`, until it is stopped;
/// previews never vibrate.
@MainActor
final class AlarmPlayer: ObservableObject {
    @Published private(set) var playingToneID: String?

    /// The tone being previewed, if any.
    @Published private(set) var previewingToneID: String?

    /// How long a preview plays before it stops by itself.
    static let previewSeconds: TimeInterval = 6

    /// How often the phone buzzes while a vibrating alarm rings.
    static let vibrationInterval: TimeInterval = 1.6

    private var player: AVAudioPlayer?
    private var previewPlayer: AVAudioPlayer?
    private var previewStop: DispatchWorkItem?
    private var vibrationTimer: Timer?
    private let system: SystemVolume
    private let vibrate: () -> Void

    /// Tests pass a pretend phone volume and their own `vibrate` to count buzzes; the
    /// app uses the real ones.
    init(system: SystemVolume = .shared,
         vibrate: @escaping () -> Void = { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }) {
        self.system = system
        self.vibrate = vibrate
    }

    /// One buzz — what switching Vibrate on in the editor feels like.
    func buzzOnce() {
        vibrate()
    }

    // MARK: Preview

    /// Plays `tone` for a few seconds so it can be recognised — as media, at the media
    /// volume as it is. Never over an alarm that is ringing.
    func preview(_ tone: AlarmTone) {
        guard player == nil else { return }
        stopPreview()
        guard let url = tone.fileURL else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // Alongside whatever else is playing; `.playback` is heard through Silent.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let preview = try AVAudioPlayer(contentsOf: url)
            preview.numberOfLoops = -1
            guard preview.play() else { return }
            previewPlayer = preview
            previewingToneID = tone.id
            let work = DispatchWorkItem { [weak self] in self?.stopPreview() }
            previewStop = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.previewSeconds, execute: work)
        } catch {
            print("AlarmPlayer could not preview \(tone.id): \(error.localizedDescription)")
        }
    }

    /// Ends a preview at once — another tone picked, the screen or tab left, the app
    /// backgrounded. A ringing alarm is not a preview and is left alone.
    func stopPreview() {
        previewStop?.cancel()
        previewStop = nil
        guard let preview = previewPlayer else { return }
        preview.stop()
        previewPlayer = nil
        previewingToneID = nil
        if player == nil {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // MARK: Ringing

    func startRinging(_ alarm: Alarm, tone: AlarmTone) {
        stopPreview()
        player?.stop()
        player = nil
        // Independent of the sound: an alarm that cannot play still buzzes.
        if alarm.vibrates { startVibrating() }

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
            system.takeOver(at: Float(min(1, max(0, alarm.volume))))

            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.prepareToPlay()
            player.play()
            self.player = player
            playingToneID = tone.id
        } catch {
            print("AlarmPlayer could not start: \(error.localizedDescription)")
        }
    }

    /// Stops the alarm, its buzzing and any preview, and hands the phone's volume back.
    func stop() {
        vibrationTimer?.invalidate()
        vibrationTimer = nil
        stopPreview()
        player?.stop()
        player = nil
        playingToneID = nil
        system.restore()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
