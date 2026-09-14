import AVFoundation

extension AlarmTone {
    /// Where this tone's audio lives: the app bundle for built-in tones, Application
    /// Support for ones the user imported.
    var fileURL: URL? {
        switch source {
        case .bundled, .system:
            let name = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension
            return Bundle.main.url(forResource: name, withExtension: ext.isEmpty ? "wav" : ext)
        case .imported:
            return FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Tones", isDirectory: true)
                .appendingPathComponent(fileName)
        }
    }
}

/// Per-task volume, baked into the sound file.
///
/// When iOS rings an alarm for us — AlarmKit on the Lock Screen, or a notification —
/// it plays the file at the Ringer & Alerts volume; there is no volume parameter. So
/// the level is baked into the file: a copy of the tone with its samples scaled,
/// written to Library/Sounds, where the system looks for custom sounds.
///
/// Previews play a copy rendered the same way, through the same system player and at
/// the same volume (`AlarmPlayer`), so what you hear while choosing a level is how
/// the alarm will ring.
///
/// 100% is the Ringer & Alerts volume itself — the tone as loud as it can go without
/// clipping. Every other level is that share of it: a 50% task is half as loud as
/// the ringer plays, a 30% task 30%.
///
///     copy = level × ceiling / peak
enum ScaledSound {
    /// System alert sounds are capped at 30 seconds.
    static let maxSeconds: Double = 29

    /// A preview is a chain of chunks this long, each rendered from where the tone has
    /// got to; short, so a new level is heard within a fraction of a second.
    static let previewChunkSeconds: Double = 0.3

    /// Chunks overlap by this much, fading out and in, so the chain plays as one
    /// unbroken tone.
    static let previewCrossfade: Double = 0.03

    /// The loudest a sample may be at 100% — just under full scale.
    static let ceiling: Float = 0.98

    /// Bumped whenever the formula changes, so copies rendered by an older one are
    /// thrown away rather than served from the cache.
    private static let formulaVersion = 4
    private static let formulaKey = "ownalarm.scaledSound.formula"
    private static var checkedFormula = false

    /// Loudest sample of each tone, so a preview — which renders only the start —
    /// scales exactly as the full copy does.
    private static var peaks: [String: Float] = [:]

    static var directory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    // MARK: The formula

    /// How loud a level plays relative to 100%, as an amplitude factor: the level
    /// itself — 1 at 100%, 0.5 at 50%, silent at 0.
    static func levelGain(_ level: Double) -> Double {
        min(1, max(0, level))
    }

    /// The factor the copy's samples are multiplied by, for a task at `level` and a
    /// tone whose loudest sample is `peak`.
    static func copyGain(for level: Double, peak: Float) -> Float {
        let gain = Float(levelGain(level))
        guard peak > 0 else { return gain }
        return gain * ceiling / peak
    }

    static func percent(_ volume: Double) -> Int {
        Int((min(1, max(0, volume)) * 100).rounded())
    }

    // MARK: Files

    /// File name of the real alarm's copy, rendered on first use and cached by tone
    /// and percentage. Nil if the tone could not be read — callers fall back to the
    /// original file.
    static func fileName(for tone: AlarmTone, volume: Double) -> String? {
        discardOutdatedCopies()
        let level = percent(volume)
        let name = "\(tone.id)-\(level).caf"
        let destination = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) { return name }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return render(tone, percent: level, seconds: maxSeconds, to: destination) ? name : nil
    }

    /// One chunk of a preview — `previewChunkSeconds` of the tone from `offset`
    /// (wrapping round at the end), scaled as the real alarm's copy is, with
    /// `previewCrossfade` faded at each edge. A throwaway file in the temporary
    /// folder; the caller deletes it when done.
    static func previewFile(for tone: AlarmTone, volume: Double, startingAt offset: TimeInterval = 0) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ownalarm-preview-\(UUID().uuidString).caf")
        return render(tone, percent: percent(volume), seconds: previewChunkSeconds, from: offset,
                      fadeEdges: previewCrossfade, to: url) ? url : nil
    }

    /// `previewChunkSeconds` of digital silence, for probing the Silent switch:
    /// muted it ends at once, heard through it takes its full length. Kept in the
    /// temporary folder and rendered again if the system has cleared it.
    static func silentProbeFile() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ownalarm-silence.caf")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(44_100 * previewChunkSeconds)) else { return nil }
        buffer.frameLength = buffer.frameCapacity
        if let samples = buffer.floatChannelData?[0] {
            for i in 0..<Int(buffer.frameLength) { samples[i] = 0 }
        }
        return write(buffer, to: url) ? url : nil
    }

    /// How much of the tone the system can play, in seconds.
    static func duration(of tone: AlarmTone) -> TimeInterval? {
        guard let source = tone.fileURL, let input = try? AVAudioFile(forReading: source) else { return nil }
        return min(Double(input.length) / input.processingFormat.sampleRate, maxSeconds)
    }

    private static func render(_ tone: AlarmTone, percent: Int, seconds: Double,
                               from offset: TimeInterval = 0, fadeEdges: Double = 0,
                               to destination: URL) -> Bool {
        guard let source = tone.fileURL,
              let loudest = peak(of: tone),
              let whole = read(source, seconds: maxSeconds) else { return false }

        let format = whole.format
        let total = Int(whole.frameLength)
        let count = min(total, Int(format.sampleRate * seconds))
        guard total > 0, count > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return false }
        buffer.frameLength = AVAudioFrameCount(count)

        let start = Int((max(0, offset) * format.sampleRate).rounded()) % total
        let gain = copyGain(for: Double(percent) / 100, peak: loudest)
        // A short linear ramp at each end, so chunks can cross-fade without a click.
        let ramp = min(Int(fadeEdges * format.sampleRate), count / 2)
        if let from = whole.floatChannelData, let to = buffer.floatChannelData {
            for channel in 0..<Int(format.channelCount) {
                for i in 0..<count {
                    var edge: Float = 1
                    if ramp > 0 {
                        if i < ramp { edge = Float(i) / Float(ramp) }
                        else if i >= count - ramp { edge = Float(count - i) / Float(ramp) }
                    }
                    to[channel][i] = from[channel][(start + i) % total] * gain * edge
                }
            }
        }

        guard write(buffer, to: destination) else {
            print("ScaledSound could not render \(tone.id) at \(percent)%")
            return false
        }
        return true
    }

    /// 16-bit linear PCM in CAF: a format every system sound path accepts.
    private static func write(_ buffer: AVAudioPCMBuffer, to destination: URL) -> Bool {
        do {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: buffer.format.sampleRate,
                AVNumberOfChannelsKey: buffer.format.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
            let output = try AVAudioFile(forWriting: destination, settings: settings,
                                         commonFormat: .pcmFormatFloat32, interleaved: false)
            try output.write(from: buffer)
            return true
        } catch {
            try? FileManager.default.removeItem(at: destination)
            print("ScaledSound could not write \(destination.lastPathComponent): \(error)")
            return false
        }
    }

    /// Loudest sample in the part of the tone the system can play.
    static func peak(of tone: AlarmTone) -> Float? {
        if let cached = peaks[tone.id] { return cached }
        guard let source = tone.fileURL, let buffer = read(source, seconds: maxSeconds) else { return nil }
        var loudest: Float = 0
        if let channels = buffer.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                for i in 0..<Int(buffer.frameLength) { loudest = max(loudest, abs(channels[channel][i])) }
            }
        }
        peaks[tone.id] = loudest
        return loudest
    }

    private static func read(_ url: URL, seconds: Double) -> AVAudioPCMBuffer? {
        guard let input = try? AVAudioFile(forReading: url) else { return nil }
        let format = input.processingFormat
        let frames = AVAudioFrameCount(min(Double(input.length), format.sampleRate * seconds))
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              (try? input.read(into: buffer, frameCount: frames)) != nil else { return nil }
        return buffer
    }

    // MARK: Cache

    /// Deletes every copy rendered from a tone — its source file has been replaced,
    /// and the cache above only knows tones by name.
    static func discardCopies(of toneID: String) {
        peaks[toneID] = nil
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where file.hasPrefix("\(toneID)-") && file.hasSuffix(".caf") {
            guard Int(file.dropFirst(toneID.count + 1).dropLast(4)) != nil else { continue }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    /// Once per launch: if the copies were rendered by an older formula, delete them
    /// all. The next re-arm renders them afresh.
    private static func discardOutdatedCopies() {
        guard !checkedFormula else { return }
        checkedFormula = true
        guard UserDefaults.standard.integer(forKey: formulaKey) < formulaVersion else { return }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where file.hasSuffix(".caf") {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
        UserDefaults.standard.set(formulaVersion, forKey: formulaKey)
    }
}
