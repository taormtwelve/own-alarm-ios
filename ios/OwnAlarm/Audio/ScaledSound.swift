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
/// 100% is the tone as loud as it can go without clipping. Lower levels step down in
/// equal decibels, the way the phone's own volume buttons do:
///
///     copy = phoneGain(level) × ceiling / peak
enum ScaledSound {
    /// System alert sounds are capped at 30 seconds.
    static let maxSeconds: Double = 29

    /// How much of the tone a preview renders. It loops, so a few seconds is enough,
    /// and a short render keeps a drag responsive.
    static let previewSeconds: Double = 6

    /// The span from 100% down to 0%, in decibels, stepped evenly — an approximation
    /// of iOS's own volume taper, so the slider feels like the volume buttons.
    static let volumeRangeDB: Double = 40

    /// The loudest a sample may be at 100% — just under full scale.
    static let ceiling: Float = 0.98

    /// Bumped whenever the formula changes, so copies rendered by an older one are
    /// thrown away rather than served from the cache.
    private static let formulaVersion = 3
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

    /// How loud a level plays relative to 100%, as an amplitude factor: 1 at 100%,
    /// silent at 0.
    static func phoneGain(_ level: Double) -> Double {
        guard level > 0 else { return 0 }
        return pow(10, (min(1, level) - 1) * volumeRangeDB / 20)
    }

    /// The factor the copy's samples are multiplied by, for a task at `level` and a
    /// tone whose loudest sample is `peak`.
    static func copyGain(for level: Double, peak: Float) -> Float {
        let gain = Float(phoneGain(level))
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

    /// A throwaway copy for a preview, rendered as the real alarm's is, in the
    /// temporary folder. The caller deletes it when done.
    static func previewFile(for tone: AlarmTone, volume: Double) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ownalarm-preview-\(UUID().uuidString).caf")
        return render(tone, percent: percent(volume), seconds: previewSeconds, to: url) ? url : nil
    }

    private static func render(_ tone: AlarmTone, percent: Int, seconds: Double, to destination: URL) -> Bool {
        guard let source = tone.fileURL,
              let loudest = peak(of: tone),
              let buffer = read(source, seconds: seconds) else { return false }

        let gain = copyGain(for: Double(percent) / 100, peak: loudest)
        if let channels = buffer.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                let samples = channels[channel]
                for i in 0..<Int(buffer.frameLength) { samples[i] *= gain }
            }
        }

        do {
            // 16-bit linear PCM in CAF: a format every system sound path accepts.
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
            print("ScaledSound could not render \(tone.id) at \(percent)%: \(error)")
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
