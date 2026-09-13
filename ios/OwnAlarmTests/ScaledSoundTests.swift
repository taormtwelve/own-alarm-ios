import XCTest
import AVFoundation
@testable import OwnAlarm

/// The system plays alarm sounds at the Ringer & Alerts volume with no volume
/// parameter, so per-task volume survives only if the scaled copies are right — and
/// a preview only tells the truth if it plays the same sound.
final class ScaledSoundTests: XCTestCase {

    private let siren = AlarmTone.tone(id: "siren", in: AlarmTone.bundled)

    func testScaledCopyIsWrittenWhereTheSystemLooksForSounds() throws {
        let name = try XCTUnwrap(ScaledSound.fileName(for: siren, volume: 0.3))
        let url = ScaledSound.directory.appendingPathComponent(name)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Sounds")
        XCTAssertEqual(url.pathExtension, "caf")
    }

    func testTheCopyIsScaledByTheFormula() throws {
        let original = try peak(of: XCTUnwrap(siren.fileURL))
        let name = try XCTUnwrap(ScaledSound.fileName(for: siren, volume: 0.3))
        let scaled = try peak(of: ScaledSound.directory.appendingPathComponent(name))

        XCTAssertEqual(scaled, original * ScaledSound.copyGain(for: 0.3, peak: original), accuracy: 0.002)
    }

    func testFullVolumeIsAsLoudAsTheFileCanGoWithoutClipping() throws {
        let name = try XCTUnwrap(ScaledSound.fileName(for: siren, volume: 1.0))
        let scaled = try peak(of: ScaledSound.directory.appendingPathComponent(name))

        XCTAssertEqual(scaled, ScaledSound.ceiling, accuracy: 0.02)
    }

    func testAPreviewIsTheRealAlarmsOwnSound() throws {
        let name = try XCTUnwrap(ScaledSound.fileName(for: siren, volume: 0.42))
        let real = try peak(of: ScaledSound.directory.appendingPathComponent(name))
        let preview = try XCTUnwrap(ScaledSound.previewFile(for: siren, volume: 0.42))
        defer { try? FileManager.default.removeItem(at: preview) }

        XCTAssertEqual(try peak(of: preview), real, accuracy: 0.0005,
                       "What you hear while choosing a level is what rings")
    }

    func testAContinuedPreviewPicksUpWhereTheToneWas() throws {
        // A slider moving to a new level renders the new copy from where the old
        // one had got to: its first sample is the straight copy's sample at that time.
        let straight = try XCTUnwrap(ScaledSound.previewFile(for: siren, volume: 0.5))
        let continued = try XCTUnwrap(ScaledSound.previewFile(for: siren, volume: 0.5, startingAt: 1.0))
        defer { for url in [straight, continued] { try? FileManager.default.removeItem(at: url) } }

        let whole = try samples(of: straight)
        let resumed = try samples(of: continued)
        let rate = try AVAudioFile(forReading: straight).processingFormat.sampleRate
        let at = Int(rate * 1.0)

        XCTAssertEqual(resumed.count, whole.count, "Same length: it still loops on the same period")
        for i in 0..<200 {
            XCTAssertEqual(resumed[i], whole[at + i], accuracy: 0.0002, "sample \(i)")
        }
    }

    func testAContinuedPreviewWrapsRoundTheTone() throws {
        let duration = try XCTUnwrap(ScaledSound.duration(of: siren))
        let straight = try XCTUnwrap(ScaledSound.previewFile(for: siren, volume: 0.5))
        // Half a second short of the end: the copy has to wrap back to the start.
        let continued = try XCTUnwrap(ScaledSound.previewFile(for: siren, volume: 0.5, startingAt: duration - 0.5))
        defer { for url in [straight, continued] { try? FileManager.default.removeItem(at: url) } }

        let whole = try samples(of: straight)
        let resumed = try samples(of: continued)
        let rate = try AVAudioFile(forReading: straight).processingFormat.sampleRate
        let beforeWrap = Int((rate * 0.5).rounded())

        for i in 0..<200 {
            XCTAssertEqual(resumed[beforeWrap + i], whole[i], accuracy: 0.0002, "sample \(i) after the wrap")
        }
    }

    func testAPreviewOfALongToneRendersOnlyItsStart() throws {
        let bell = AlarmTone.tone(id: "soft-bell", in: AlarmTone.bundled)   // 8 seconds
        let preview = try XCTUnwrap(ScaledSound.previewFile(for: bell, volume: 0.5))
        defer { try? FileManager.default.removeItem(at: preview) }

        let file = try AVAudioFile(forReading: preview)
        XCTAssertLessThanOrEqual(Double(file.length) / file.fileFormat.sampleRate,
                                 ScaledSound.previewSeconds + 0.05,
                                 "A short render keeps dragging responsive")
    }

    func testEachLevelGetsItsOwnFile() throws {
        let a = try XCTUnwrap(ScaledSound.fileName(for: siren, volume: 0.30))
        let b = try XCTUnwrap(ScaledSound.fileName(for: siren, volume: 0.31))
        XCTAssertNotEqual(a, b, "Changing the volume must produce a different sound")
    }

    func testCopiesStayUnderTheThirtySecondSystemLimit() throws {
        for tone in AlarmTone.bundled {
            let name = try XCTUnwrap(ScaledSound.fileName(for: tone, volume: 0.5))
            let file = try AVAudioFile(forReading: ScaledSound.directory.appendingPathComponent(name))
            let seconds = Double(file.length) / file.fileFormat.sampleRate
            XCTAssertLessThanOrEqual(seconds, 30, "\(tone.name) is \(seconds)s")
        }
    }

    func testDiscardingATonesCopiesLeavesOtherTonesAlone() throws {
        let bell = AlarmTone.tone(id: "soft-bell", in: AlarmTone.bundled)
        let sirenCopy = try XCTUnwrap(ScaledSound.fileName(for: siren, volume: 0.42))
        let bellCopy = try XCTUnwrap(ScaledSound.fileName(for: bell, volume: 0.42))

        ScaledSound.discardCopies(of: siren.id)

        let exists = { FileManager.default.fileExists(atPath: ScaledSound.directory.appendingPathComponent($0).path) }
        XCTAssertFalse(exists(sirenCopy), "A replaced tone's old copies must go")
        XCTAssertTrue(exists(bellCopy), "Other tones keep theirs")
    }

    // MARK: The formula

    func testFullVolumeIsTheLoudestTheToneCanGo() {
        for peak: Float in [0.2, 0.62, 1.0] {
            XCTAssertEqual(ScaledSound.copyGain(for: 1, peak: peak) * peak, ScaledSound.ceiling,
                           accuracy: 0.0001, "peak \(peak)")
        }
    }

    func testEveryLevelIsThatShareOfFullVolume() {
        // 50% is half as loud as 100%, 30% is 30% — for preview and real ring alike,
        // since both play the same copy at the Ringer & Alerts volume.
        let full = ScaledSound.copyGain(for: 1, peak: 0.5)
        for level in stride(from: 0.0, through: 1.0, by: 0.05) {
            XCTAssertEqual(ScaledSound.copyGain(for: level, peak: 0.5), full * Float(level),
                           accuracy: 0.0001, "\(Int((level * 100).rounded()))%")
        }
    }

    func testALouderTaskAlwaysGetsALouderCopy() {
        let gains = stride(from: 0.05, through: 1.0, by: 0.05)
            .map { ScaledSound.copyGain(for: $0, peak: 0.5) }
        XCTAssertEqual(gains, gains.sorted())
        XCTAssertEqual(Set(gains).count, gains.count)
    }

    func testNoLevelEverClips() {
        for peak: Float in [0.3, 0.7, 1.0] {
            for level in stride(from: 0.0, through: 1.0, by: 0.05) {
                XCTAssertLessThanOrEqual(ScaledSound.copyGain(for: level, peak: peak) * peak,
                                         ScaledSound.ceiling + 0.0001)
            }
        }
    }

    func testZeroIsSilent() {
        XCTAssertEqual(ScaledSound.copyGain(for: 0, peak: 0.5), 0)
    }

    // MARK: Helpers

    /// The first channel, sample by sample.
    private func samples(of url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData)[0]
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    private func peak(of url: URL) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        // Every channel, as the render does: its scale is set by the loudest one.
        let channels = try XCTUnwrap(buffer.floatChannelData)
        var loudest: Float = 0
        for channel in 0..<Int(file.processingFormat.channelCount) {
            for i in 0..<Int(buffer.frameLength) { loudest = max(loudest, abs(channels[channel][i])) }
        }
        return loudest
    }
}
