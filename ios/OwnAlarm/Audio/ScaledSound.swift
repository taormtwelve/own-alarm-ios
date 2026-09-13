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
/// it plays the file at its own level; there is no volume parameter. So the level is
/// baked into the file: a copy of the tone with its samples scaled to the alarm's
/// percentage, written to Library/Sounds, where the system looks for custom sounds.
/// A 30% task rings with a file 30% as loud as the original.
enum ScaledSound {
    /// System alert sounds are capped at 30 seconds.
    static let maxSeconds: Double = 29

    static var directory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    /// Deletes every copy rendered from a tone — its source file has been replaced,
    /// and the cache below only knows tones by name.
    static func discardCopies(of toneID: String) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where file.hasPrefix("\(toneID)-") && file.hasSuffix(".caf") {
            guard Int(file.dropFirst(toneID.count + 1).dropLast(4)) != nil else { continue }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    /// File name of the scaled copy, rendered on first use and cached by tone and
    /// percentage. Nil if the tone could not be read — callers fall back to the
    /// original file.
    static func fileName(for tone: AlarmTone, volume: Double) -> String? {
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

            let gain = Float(percent) / 100
            if let channels = buffer.floatChannelData {
                for channel in 0..<Int(format.channelCount) {
                    let samples = channels[channel]
                    for i in 0..<Int(buffer.frameLength) { samples[i] *= gain }
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
}
