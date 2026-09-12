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

    func testThirtyPercentIsThirtyPercentAsLoud() throws {
        let original = try peak(of: XCTUnwrap(siren.fileURL))
        let name = try XCTUnwrap(ScaledSound.fileName(for: siren, volume: 0.3))
        let scaled = try peak(of: ScaledSound.directory.appendingPathComponent(name))

        XCTAssertEqual(scaled, original * 0.3, accuracy: 0.02)
    }

    func testFullVolumeKeepsTheOriginalLevel() throws {
        let original = try peak(of: XCTUnwrap(siren.fileURL))
        let name = try XCTUnwrap(ScaledSound.fileName(for: siren, volume: 1.0))
        let scaled = try peak(of: ScaledSound.directory.appendingPathComponent(name))

        XCTAssertEqual(scaled, original, accuracy: 0.02)
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
