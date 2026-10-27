import Foundation
import AVFoundation

@main
enum AudioSilenceTrimmerTests {
    static func main() {
        testTrailingSilenceIsTrimmed()
        testPureToneIsNotTrimmed()
        testPureSilenceIsNotTrimmed()
        testShortSilenceIsNotTrimmed()
        testNonexistentFileReturnsGracefully()
        testInPlaceTrimming()
        print("AudioSilenceTrimmer tests passed")
    }

    private static let sampleRate: Double = 16000
    private static let outputSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32_000,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    private static func makeTestAudioFile(url: URL, toneDuration: Double, silenceDuration: Double) {
        try? FileManager.default.removeItem(at: url)
        let totalFrames = AVAudioFrameCount((toneDuration + silenceDuration) * sampleRate)
        let toneFrames = AVAudioFrameCount(toneDuration * sampleRate)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames)!
        buffer.frameLength = totalFrames

        let channel = buffer.floatChannelData![0]
        for i in 0..<Int(totalFrames) {
            channel[i] = i < Int(toneFrames) ? sin(Float(i) * 2.0 * .pi * 440.0 / Float(sampleRate)) * 0.5 : 0.0
        }

        do {
            let file = try AVAudioFile(forWriting: url, settings: outputSettings)
            try file.write(from: buffer)
        } catch {
            preconditionFailure("Failed to create test audio: \(error)")
        }
    }

    static func testTrailingSilenceIsTrimmed() {
        let tempDir = FileManager.default.temporaryDirectory
        let sourceURL = tempDir.appendingPathComponent("test_trim_src_\(UUID().uuidString).m4a")
        let destURL = tempDir.appendingPathComponent("test_trim_dst_\(UUID().uuidString).m4a")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destURL)
        }

        // 1.0s tone + 1.5s silence = 2.5s total
        makeTestAudioFile(url: sourceURL, toneDuration: 1.0, silenceDuration: 1.5)

        let result = AudioSilenceTrimmer.trimTrailingSilence(at: sourceURL, destinationURL: destURL)
        precondition(result.isTrimmed, "Expected audio to be trimmed")
        precondition(abs(result.originalDuration - 2.5) < 0.1, "Original duration mismatch: \(result.originalDuration)")
        // Expected final duration: 1.0s + 0.2s padding = ~1.2s
        precondition(abs(result.finalDuration - 1.2) < 0.1, "Final duration mismatch: \(result.finalDuration)")
        precondition(FileManager.default.fileExists(atPath: destURL.path), "Trimmed file not found")
    }

    static func testPureToneIsNotTrimmed() {
        let tempDir = FileManager.default.temporaryDirectory
        let sourceURL = tempDir.appendingPathComponent("test_tone_\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        makeTestAudioFile(url: sourceURL, toneDuration: 1.0, silenceDuration: 0.0)

        let result = AudioSilenceTrimmer.trimTrailingSilence(at: sourceURL)
        precondition(!result.isTrimmed, "Pure tone should not be trimmed")
    }

    static func testPureSilenceIsNotTrimmed() {
        let tempDir = FileManager.default.temporaryDirectory
        let sourceURL = tempDir.appendingPathComponent("test_silence_\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        makeTestAudioFile(url: sourceURL, toneDuration: 0.0, silenceDuration: 1.5)

        let result = AudioSilenceTrimmer.trimTrailingSilence(at: sourceURL)
        precondition(!result.isTrimmed, "Pure silence should return isTrimmed = false to allow upstream empty checks")
    }

    static func testShortSilenceIsNotTrimmed() {
        let tempDir = FileManager.default.temporaryDirectory
        let sourceURL = tempDir.appendingPathComponent("test_short_\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        // 1.0s tone + 0.1s silence (below minimumTrimDifferenceSeconds 0.25)
        makeTestAudioFile(url: sourceURL, toneDuration: 1.0, silenceDuration: 0.1)

        let result = AudioSilenceTrimmer.trimTrailingSilence(at: sourceURL)
        precondition(!result.isTrimmed, "Short trailing silence should not be trimmed")
    }

    static func testNonexistentFileReturnsGracefully() {
        let fakeURL = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).m4a")
        let result = AudioSilenceTrimmer.trimTrailingSilence(at: fakeURL)
        precondition(!result.isTrimmed)
        precondition(result.originalDuration == 0)
    }

    static func testInPlaceTrimming() {
        let tempDir = FileManager.default.temporaryDirectory
        let sourceURL = tempDir.appendingPathComponent("test_inplace_\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        makeTestAudioFile(url: sourceURL, toneDuration: 0.8, silenceDuration: 1.2)

        let result = AudioSilenceTrimmer.trimTrailingSilence(at: sourceURL)
        precondition(result.isTrimmed, "In-place trim should succeed")
        precondition(result.fileURL == sourceURL, "Should return source URL")
        precondition(abs(result.finalDuration - 1.0) < 0.1, "Final duration mismatch: \(result.finalDuration)")

        // Verify the source file actually became shorter
        if let readFile = try? AVAudioFile(forReading: sourceURL) {
            let dur = Double(readFile.length) / readFile.processingFormat.sampleRate
            precondition(abs(dur - 1.0) < 0.1, "File on disk duration mismatch: \(dur)")
        } else {
            preconditionFailure("Cannot read back in-place trimmed file")
        }
    }
}

