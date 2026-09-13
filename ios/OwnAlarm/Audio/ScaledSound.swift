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

/// Per-task volume for sounds the *system* plays.
///
/// When iOS rings an alarm for us — AlarmKit on the Lock Screen, or a notification —
/// it plays the file at the Ringer & Alerts level; there is no volume parameter. So
/// the level is baked into the file: a copy of the tone with its samples scaled,
/// written to Library/Sounds, where the system looks for custom sounds.
///
/// The scale is chosen so the real alarm sounds like the preview. The preview plays
/// the tone at full scale with the phone's volume at the task's level; the real alarm
/// plays the copy at the ringer's level. With `phoneGain` for how loud a volume
/// setting plays:
///
///     copy × phoneGain(ringer) = phoneGain(level)
///     copy = phoneGain(level) / phoneGain(ringer)
///
/// Apps cannot read the ringer's level, so it is `assumedRinger`. And a copy can only
/// get so loud: past the point where its loudest sample reaches full scale, more gain
/// is distortion, not volume, so the boost stops there.
enum ScaledSound {
    /// System alert sounds are capped at 30 seconds.
    static let maxSeconds: Double = 29

    /// iOS's volume steps are roughly equal in decibels, not in amplitude: modelled
    /// as a straight line from 0 dB at 100% down this far at 0%. An approximation —
    /// tune it by ear against the preview.
    static let volumeRangeDB: Double = 40

    /// The Ringer & Alerts level the real alarm is matched against. Apps cannot read
    /// it, so this assumes the middle of the slider.
    static let assumedRinger: Double = 0.5

    /// The loudest a sample may be after a boost — just under full scale.
    static let ceiling: Float = 0.98

    /// Bumped whenever the formula changes, so copies rendered by an older one are
    /// thrown away rather than served from the cache.
    private static let formulaVersion = 2
    private static let formulaKey = "ownalarm.scaledSound.formula"
    private static var checkedFormula = false

    static var directory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    // MARK: The formula

    /// How loud the phone plays at a volume setting, as an amplitude factor: 1 at
    /// 100%, silent at 0.
    static func phoneGain(_ level: Double) -> Double {
        guard level > 0 else { return 0 }
        return pow(10, (min(1, level) - 1) * volumeRangeDB / 20)
    }

    /// The factor the copy's samples are multiplied by, for a task at `level` and a
    /// tone whose loudest sample is `peak`.
    static func copyGain(for level: Double, peak: Float, ringer: Double = assumedRinger) -> Float {
        let wanted = phoneGain(level) / phoneGain(ringer)
        let limit = peak > 0 ? Double(ceiling / peak) : 1
        return Float(min(wanted, limit))
    }

    // MARK: Files

    /// File name of the scaled copy, rendered on first use and cached by tone and
    /// percentage. Nil if the tone could not be read — callers fall back to the
    /// original file.
    static func fileName(for tone: AlarmTone, volume: Double) -> String? {
        discardOutdatedCopies()
        let percent = Int((min(1, max(0, volume)) * 100).rounded())
        let name = "\(tone.id)-\(percent).caf"
        let destination = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) { return name }
        guard let source = tone.fileURL else { return nil }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let input = try AVAudioFile(forReading: source)
            let format = input.processingFormat
            let frames = AVAudioFrameCount(min(Double(input.length), format.sampleRate * maxSeconds))
            guard frames > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
            try input.read(into: buffer, frameCount: frames)

            if let channels = buffer.floatChannelData {
                let count = Int(format.channelCount)
                let length = Int(buffer.frameLength)
                var peak: Float = 0
                for channel in 0..<count {
                    for i in 0..<length { peak = max(peak, abs(channels[channel][i])) }
                }
                let gain = copyGain(for: Double(percent) / 100, peak: peak)
                for channel in 0..<count {
                    let samples = channels[channel]
                    for i in 0..<length { samples[i] *= gain }
                }
            }

            // 16-bit linear PCM in CAF: a format every system sound path accepts.
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
            let output = try AVAudioFile(forWriting: destination, settings: settings,
                                         commonFormat: .pcmFormatFloat32, interleaved: false)
            try output.write(from: buffer)
            return name
        } catch {
            try? FileManager.default.removeItem(at: destination)
            print("ScaledSound could not render \(tone.id) at \(percent)%: \(error)")
            return nil
        }
    }

    /// Deletes every copy rendered from a tone — its source file has been replaced,
    /// and the cache above only knows tones by name.
    static func discardCopies(of toneID: String) {
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
