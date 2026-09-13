import XCTest
import AVFoundation
@testable import OwnAlarm

/// The system plays alarm sounds at its own level, so per-task volume survives only
/// if the scaled copies really are quieter by the right amount.
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

        let gain = ScaledSound.copyGain(for: 0.3, peak: original)
        XCTAssertEqual(scaled, original * gain, accuracy: 0.02)
    }

    func testFullVolumeIsAsLoudAsTheFileCanGoWithoutClipping() throws {
        let name = try XCTUnwrap(ScaledSound.fileName(for: siren, volume: 1.0))
        let scaled = try peak(of: ScaledSound.directory.appendingPathComponent(name))

        XCTAssertEqual(scaled, ScaledSound.ceiling, accuracy: 0.02)
    }

    // MARK: The formula

    /// A tone quiet enough that the no-clipping cap never gets in the way.
    private let roomy: Float = 0.01

    func testAtTheRingerLevelTheCopyIsTheToneItself() {
        let gain = ScaledSound.copyGain(for: ScaledSound.assumedRinger, peak: roomy)
        XCTAssertEqual(gain, 1, accuracy: 0.0001,
                       "Preview and real alarm then play the same file at the same phone level")
    }

    func testTheRealAlarmLandsWhereThePreviewDoes() {
        for ringer in [0.3, 0.5, 0.8] {
            for level in stride(from: 0.05, through: 1.0, by: 0.05) {
                let real = Double(ScaledSound.copyGain(for: level, peak: roomy, ringer: ringer))
                    * ScaledSound.phoneGain(ringer)
                XCTAssertEqual(real, ScaledSound.phoneGain(level), accuracy: 0.0001,
                               "level \(level), ringer \(ringer)")
            }
        }
    }

    func testALouderTaskAlwaysGetsALouderCopy() {
        let gains = stride(from: 0.05, through: 1.0, by: 0.05)
            .map { ScaledSound.copyGain(for: $0, peak: roomy) }
        XCTAssertEqual(gains, gains.sorted())
        XCTAssertEqual(Set(gains).count, gains.count)
    }

    func testTheRealAlarmIsNeverQuieterThanTheOldStraightScaling() {
        for level in stride(from: 0.01, through: 1.0, by: 0.01) {
            XCTAssertGreaterThanOrEqual(ScaledSound.copyGain(for: level, peak: roomy), Float(level),
                                        "\(Int(level * 100))%")
        }
    }

    func testABoostNeverClips() {
        for peak: Float in [0.3, 0.7, 1.0] {
            XCTAssertLessThanOrEqual(ScaledSound.copyGain(for: 1, peak: peak) * peak,
                                     ScaledSound.ceiling + 0.0001)
        }
    }

    func testZeroIsSilent() {
        XCTAssertEqual(ScaledSound.copyGain(for: 0, peak: roomy), 0)
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

    // MARK: Helpers

    private func peak(of url: URL) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData)[0]
        var loudest: Float = 0
        for i in 0..<Int(buffer.frameLength) { loudest = max(loudest, abs(channel[i])) }
        return loudest
    }
}
