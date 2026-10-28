import Foundation
import AVFoundation
import Darwin

/// 在送往雲端辨識前，安全裁除音訊尾端多餘的靜音與環境底噪。
///
/// 這是解決 Whisper 在音訊尾端因低信噪比／空白而產生 YouTube 宣傳語幻覺
/// （「請訂閱」、「請按讚、分享、開啟小鈴鐺」）的關鍵防線。
///
/// 特性：
/// 1. 決定性、純本地處理，使用 macOS 內建 AVFoundation，無外部相依。
/// 2. 倒推掃描音訊能量，尋找最後一個發音點。
/// 3. 保留可配置的氣音緩衝（預設 200ms），確保最後一個字不被吃掉。
/// 4. 只有當尾端多餘靜音達到可觀長度（預設 250ms 以上）時才裁切；過短的差異不重寫檔案，避免不必要的 I/O。
/// 5. 任何處理失敗均優雅退回原音檔，絕不阻斷使用者的轉錄流程。
enum AudioSilenceTrimmer {
    /// 靜音能量門檻（dBFS）。低於此門檻視為無效底噪。
    /// -42 dBFS 經實測能有效過濾一般室內冷氣、風扇與環境底噪，同時保留正常中文發音尾音。
    static let defaultThresholdDB: Float = -42.0

    /// 保留的尾部平滑緩衝時間（秒）。
    static let defaultPaddingSeconds: Double = 0.20

    /// 最小裁切門檻（秒）。只有尾端靜音超過此長度才進行裁切。
    static let minimumTrimDifferenceSeconds: Double = 0.25

    struct Result: Equatable {
        let isTrimmed: Bool
        let originalDuration: TimeInterval
        let finalDuration: TimeInterval
        let fileURL: URL
    }

    /// 偵測並裁切尾端靜音。若成功裁切且未指定 destinationURL，會寫入同目錄下的暫存檔並替換原檔。
    @discardableResult
    static func trimTrailingSilence(
        at sourceURL: URL,
        destinationURL: URL? = nil,
        thresholdDB: Float = defaultThresholdDB,
        paddingSeconds: Double = defaultPaddingSeconds,
        minimumTrimDifference: Double = minimumTrimDifferenceSeconds,
        replaceFile: (URL, URL) throws -> Void = AudioSilenceTrimmer.replaceAtomically
    ) -> Result {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return Result(isTrimmed: false, originalDuration: 0, finalDuration: 0, fileURL: sourceURL)
        }

        do {
            let file = try AVAudioFile(forReading: sourceURL)
            let format = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            guard frameCount > 0, format.sampleRate > 0 else {
                return Result(isTrimmed: false, originalDuration: 0, finalDuration: 0, fileURL: sourceURL)
            }

            let originalDuration = Double(frameCount) / format.sampleRate
            let linearThreshold = pow(10.0, thresholdDB / 20.0)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                return Result(isTrimmed: false, originalDuration: originalDuration, finalDuration: originalDuration, fileURL: sourceURL)
            }
            try file.read(into: buffer)

            guard let channelData = buffer.floatChannelData else {
                return Result(isTrimmed: false, originalDuration: originalDuration, finalDuration: originalDuration, fileURL: sourceURL)
            }

            let totalFrames = Int(buffer.frameLength)
            let channelCount = Int(format.channelCount)
            var lastAudibleFrame = -1

            // 倒推掃描
            for frame in stride(from: totalFrames - 1, through: 0, by: -1) {
                var maxAmplitude: Float = 0.0
                for ch in 0..<channelCount {
                    let amp = abs(channelData[ch][frame])
                    if amp > maxAmplitude { maxAmplitude = amp }
                }
                if maxAmplitude >= linearThreshold {
                    lastAudibleFrame = frame
                    break
                }
            }

            // 完全沒聲音時，維持原檔讓上游去回報「沒有辨識到語音」
            guard lastAudibleFrame >= 0 else {
                return Result(isTrimmed: false, originalDuration: originalDuration, finalDuration: originalDuration, fileURL: sourceURL)
            }

            let paddingFrames = Int(format.sampleRate * paddingSeconds)
            let targetFrames = min(totalFrames, lastAudibleFrame + paddingFrames)

            let diffSeconds = Double(totalFrames - targetFrames) / format.sampleRate
            guard diffSeconds >= minimumTrimDifference else {
                return Result(isTrimmed: false, originalDuration: originalDuration, finalDuration: originalDuration, fileURL: sourceURL)
            }

            guard let trimmedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(targetFrames)) else {
                return Result(isTrimmed: false, originalDuration: originalDuration, finalDuration: originalDuration, fileURL: sourceURL)
            }
            trimmedBuffer.frameLength = AVAudioFrameCount(targetFrames)
            for ch in 0..<channelCount {
                memcpy(trimmedBuffer.floatChannelData![ch], channelData[ch], targetFrames * MemoryLayout<Float>.size)
            }

            let targetURL = destinationURL ?? sourceURL.deletingLastPathComponent().appendingPathComponent("trimmed-\(UUID().uuidString).m4a")

            // Only the internally owned temporary output is cleaned on failure.
            defer {
                if destinationURL == nil { try? FileManager.default.removeItem(at: targetURL) }
            }

            let outputSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderBitRateKey: 32_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            try? FileManager.default.removeItem(at: targetURL)
            // Finalize the AAC container before publishing it at the source URL.
            try autoreleasepool {
                let outFile = try AVAudioFile(forWriting: targetURL, settings: outputSettings)
                try outFile.write(from: trimmedBuffer)
            }

            let finalDuration = Double(targetFrames) / format.sampleRate

            if destinationURL == nil {
                // Same-directory rename is atomic and leaves the original intact on failure.
                try replaceFile(targetURL, sourceURL)
                return Result(isTrimmed: true, originalDuration: originalDuration, finalDuration: finalDuration, fileURL: sourceURL)
            } else {
                return Result(isTrimmed: true, originalDuration: originalDuration, finalDuration: finalDuration, fileURL: targetURL)
            }
        } catch {
            return Result(isTrimmed: false, originalDuration: 0, finalDuration: 0, fileURL: sourceURL)
        }
    }

    static func replaceAtomically(_ temporaryURL: URL, _ sourceURL: URL) throws {
        let result = temporaryURL.path.withCString { temporaryPath in
            sourceURL.path.withCString { sourcePath in
                Darwin.rename(temporaryPath, sourcePath)
            }
        }
        guard result == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

}

