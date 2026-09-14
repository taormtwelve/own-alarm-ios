import XCTest
import AVFoundation
@testable import OwnAlarm

/// The system plays alarm sounds at the Ringer & Alerts volume with no volume
/// parameter, so per-task volume survives only if the scaled copies are right.
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

    func testTheNameIsTheCopysFileName() throws {
        XCTAssertEqual(try XCTUnwrap(ScaledSound.fileName(for: siren, volume: 0.42)),
                       ScaledSound.name(for: siren, volume: 0.42))
    }

    func testDiscardingKeepsOnlyTheCopiesInUse() throws {
        let used = try XCTUnwrap(ScaledSound.fileName(for: siren, volume: 0.61))
        let unused = try XCTUnwrap(ScaledSound.fileName(for: siren, volume: 0.62))

        ScaledSound.discardCopies(except: [used])

        let exists = { FileManager.default.fileExists(atPath: ScaledSound.directory.appendingPathComponent($0).path) }
        XCTAssertTrue(exists(used))
        XCTAssertFalse(exists(unused), "Tried once, never saved: gone")
    }

    // MARK: The formula

    func testFullVolumeIsTheLoudestTheToneCanGo() {
        for peak: Float in [0.2, 0.62, 1.0] {
            XCTAssertEqual(ScaledSound.copyGain(for: 1, peak: peak) * peak, ScaledSound.ceiling,
                           accuracy: 0.0001, "peak \(peak)")
        }
    }

    func testEveryLevelIsThatShareOfFullVolume() {
        // 50% is half as loud as 100%, 30% is 30% — of the Ringer & Alerts volume,
        // since the copy plays at that volume.
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
