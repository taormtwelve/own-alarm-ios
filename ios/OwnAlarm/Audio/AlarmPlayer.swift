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
/// never touched for a preview.
///
/// A system sound can neither change volume nor be stopped part-way, so a preview is
/// a chain of short chunks (`ScaledSound.previewChunkSeconds`), each rendered from
/// where the tone has got to, at whatever level the slider wants by then. The next
/// chunk starts a little before the current one ends and both carry a short fade at
/// their edges, so they cross-fade: no gap, no click, and a level change eases in.
/// Nothing is ever cut off — a chunk is simply not followed — so stopping, switching
/// tone or changing level can never leave two sounds playing over each other.
///
/// The Silent switch mutes alert sounds, previews included: a muted chunk ends the
/// instant it starts, which sets `previewMuted` and the screens say so. While that
/// is set, a chunk of digital silence — inaudible either way — is played every
/// `silentProbeInterval`, so the flag clears as soon as the switch is turned off.
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

    /// The level, in percent, of the chunk playing now.
    private(set) var previewPercent: Int?

    /// The level the slider wants; the next chunk picks it up.
    private(set) var previewTargetPercent: Int?

    /// True after a preview ended the instant it started — the Silent switch is on
    /// (or there is no audio output), so alert sounds are muted. Cleared the moment
    /// a preview, or the silent probe, is heard through.
    @Published private(set) var previewMuted = false

    /// How long a slider can sit untouched before its sound stops by itself. iOS can
    /// cancel a drag — a scroll takes the finger over — without the slider ever
    /// reporting that it was let go, and the tone must not loop forever after that.
    static let scrubIdleTimeout: TimeInterval = 2

    /// How often the phone buzzes while a vibrating alarm rings.
    static let vibrationInterval: TimeInterval = 1.6

    /// How often the Silent switch is probed while previews are muted.
    static let silentProbeInterval: TimeInterval = 2

    /// A chunk that ended sooner than this never played: alert sounds are muted.
    private static let mutedThreshold: TimeInterval = 0.1

    /// One rendered piece of a preview, ready to play.
    private struct Chunk {
        let id: SystemSoundID
        let file: URL
        let toneID: String
        let percent: Int
        let offset: TimeInterval
    }

    private var player: AVAudioPlayer?
    private var current: Chunk?
    private var next: Chunk?
    private var previewTone: AlarmTone?
    /// Where in the tone the chunk after `current` begins.
    private var nextOffset: TimeInterval = 0
    private var nextStart: DispatchWorkItem?
    private var renderWork: DispatchWorkItem?
    /// Sounds disposed of while still playing; their completions are not news.
    private var disposed: Set<SystemSoundID> = []
    private var previewActive: Bool { current != nil }
    private var lastMutedAttempt = Date.distantPast
    private var probeTimer: Timer?
    private var probeSound: SystemSoundID?
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

    /// A finger lands on a volume slider: the tone plays at its level — carrying on
    /// if it is already playing.
    func beginScrub(_ tone: AlarmTone, at volume: Double) {
        isScrubbing = true
        scrubTone = tone
        playPreview(tone, at: volume)
        scheduleIdleSilence()
    }

    /// Follows the slider: the next chunk plays at the new level.
    func scrub(to volume: Double) {
        guard isScrubbing, let tone = scrubTone else { return }
        playPreview(tone, at: volume)
        scheduleIdleSilence()
    }

    /// The finger lifted: the level it let go at rings for a moment, then stops.
    func endScrub() {
        isScrubbing = false
        scrubTone = nil
        scheduleStop(after: ScaledSound.previewChunkSeconds + 1)
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

    /// Starts previewing `tone` at `volume`, or moves a running preview to them: a
    /// new level takes effect at the next chunk, a new tone starts from its
    /// beginning at the next chunk.
    private func playPreview(_ tone: AlarmTone, at volume: Double) {
        let percent = ScaledSound.percent(volume)
        previewTargetPercent = percent
        if current != nil {
            if previewTone?.id != tone.id {
                previewTone = tone
                nextOffset = 0
                renderNext()
            } else {
                renderNextSoon()
            }
            return
        }
        // Muted: trying again every frame of a drag would only churn.
        if previewMuted, Date().timeIntervalSince(lastMutedAttempt) < 0.5 { return }
        previewTone = tone
        releaseAudioSession()
        guard let chunk = render(tone, percent: percent, offset: 0) else {
            print("AlarmPlayer could not render a preview of \(tone.id)")
            playingToneID = nil
            return
        }
        play(chunk)
    }

    /// Plays a chunk now, renders the one after it, and books that one to start
    /// just before this one ends.
    private func play(_ chunk: Chunk) {
        current = chunk
        previewPercent = chunk.percent
        if playingToneID != chunk.toneID { playingToneID = chunk.toneID }
        let lead = ScaledSound.previewChunkSeconds - ScaledSound.previewCrossfade
        nextOffset = chunk.offset + lead
        let started = Date()
        AudioServicesPlaySystemSoundWithCompletion(chunk.id) { [weak self] in
            Task { @MainActor in self?.chunkEnded(chunk, after: Date().timeIntervalSince(started)) }
        }
        renderNext()
        nextStart?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.startNext() }
        nextStart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + lead, execute: work)
    }

    /// The chunk after the current one, rendered ahead of time with the level and
    /// tone wanted now. Rendered again if they change before it starts.
    private func renderNext() {
        renderWork?.cancel()
        renderWork = nil
        guard let tone = previewTone, current != nil else { return }
        let percent = previewTargetPercent ?? previewPercent ?? 0
        if let ready = next, ready.toneID == tone.id, ready.percent == percent, ready.offset == nextOffset { return }
        if let ready = next { dispose(ready) }
        next = render(tone, percent: percent, offset: nextOffset)
    }

    /// A drag reports every frame; one render shortly covers all of them.
    private func renderNextSoon() {
        guard renderWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.renderWork = nil
            self?.renderNext()
        }
        renderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    /// Time for the next chunk: the current one is in its final fade.
    private func startNext() {
        nextStart?.cancel()
        nextStart = nil
        guard let tone = previewTone, current != nil else { return }
        renderWork?.cancel()
        renderWork = nil
        let upcoming = next ?? render(tone, percent: previewTargetPercent ?? previewPercent ?? 0, offset: nextOffset)
        next = nil
        guard let upcoming else {
            endPreview()
            playingToneID = nil
            return
        }
        play(upcoming)
    }

    /// A chunk finished playing. Normally the next one has long taken over; if not,
    /// this one either never played (muted) or the chain is late, and carries on.
    private func chunkEnded(_ chunk: Chunk, after seconds: TimeInterval) {
        if disposed.remove(chunk.id) != nil {
            try? FileManager.default.removeItem(at: chunk.file)
            return
        }
        dispose(chunk)
        let heard = seconds > Self.mutedThreshold
        if previewMuted == heard { previewMuted = !heard }
        guard current?.id == chunk.id else { return }
        if heard {
            startNext()
        } else {
            // Alert sounds are muted: stop chaining, and watch for the switch.
            nextStart?.cancel()
            nextStart = nil
            if let ready = next { dispose(ready) }
            next = nil
            current = nil
            playingToneID = nil
            lastMutedAttempt = Date()
            startProbing()
        }
    }

    private func render(_ tone: AlarmTone, percent: Int, offset: TimeInterval) -> Chunk? {
        guard let file = ScaledSound.previewFile(for: tone, volume: Double(percent) / 100, startingAt: offset) else {
            return nil
        }
        var id: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(file as CFURL, &id) == kAudioServicesNoError else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return Chunk(id: id, file: file, toneID: tone.id, percent: percent, offset: offset)
    }

    private func dispose(_ chunk: Chunk) {
        AudioServicesDisposeSystemSoundID(chunk.id)
        try? FileManager.default.removeItem(at: chunk.file)
    }

    /// Ends the preview: nothing follows the chunk playing now, which is also
    /// disposed of — iOS may stop it on the spot, or let it run its last fraction of
    /// a second out.
    private func endPreview() {
        nextStart?.cancel()
        nextStart = nil
        renderWork?.cancel()
        renderWork = nil
        if let playing = current {
            disposed.insert(playing.id)
            AudioServicesDisposeSystemSoundID(playing.id)
        }
        if let ready = next { dispose(ready) }
        current = nil
        next = nil
        previewTone = nil
        previewPercent = nil
        previewTargetPercent = nil
        nextOffset = 0
    }

    /// Alert sounds follow the Ringer & Alerts volume only while the app has no
    /// active audio session; one left active by the in-app alarm would pull them
    /// onto media volume and make a preview louder than the real ring.
    private func releaseAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Silent switch

    private func startProbing() {
        guard probeTimer == nil else { return }
        probeTimer = Timer.scheduledTimer(withTimeInterval: Self.silentProbeInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.probeSilentSwitch() }
        }
    }

    private func stopProbing() {
        probeTimer?.invalidate()
        probeTimer = nil
    }

    /// Plays a chunk of digital silence. Muted, it ends at once; heard through, it
    /// takes its full length — which is how the switch is known to be off again.
    private func probeSilentSwitch() {
        guard previewMuted else {
            stopProbing()
            return
        }
        guard !previewActive, probeSound == nil,
              let file = ScaledSound.silentProbeFile() else { return }
        var id: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(file as CFURL, &id) == kAudioServicesNoError else { return }
        probeSound = id
        releaseAudioSession()
        let started = Date()
        AudioServicesPlaySystemSoundWithCompletion(id) { [weak self] in
            Task { @MainActor in
                AudioServicesDisposeSystemSoundID(id)
                guard let self else { return }
                self.probeSound = nil
                if Date().timeIntervalSince(started) > Self.mutedThreshold {
                    self.previewMuted = false
                    self.stopProbing()
                }
            }
        }
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
        let work = DispatchWorkItem(block: body)
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func url(for tone: AlarmTone) -> URL? {
        tone.fileURL
    }
}
