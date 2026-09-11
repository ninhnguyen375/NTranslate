// Raises quiet TTS clips to a consistent playback level. Speech engines leave a lot of
// headroom, and AVAudioPlayer.volume cannot go above 1.0, so the only way to match other
// apps is to amplify the samples before they reach the player.
import AVFoundation

enum SpeechGain {
    /// Peak after a 1.0 volume normalize. Just under full scale so AAC/WAV round-trips do not clip.
    static let targetPeak: Float = 0.98
    /// Below this the clip is treated as silence and left untouched.
    static let minPeak: Float = 0.01

    /// Peak-normalizes, then applies `volume` (1.0 = full normalize, 2.0 = +6 dB extra).
    /// Samples are hard-clipped to ±1. Returns the peak that was measured before gain.
    @discardableResult
    static func apply(
        channels: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        frames: Int,
        volume: Float
    ) -> Float {
        guard frames > 0, channelCount > 0 else { return 0 }
        var peak: Float = 0
        for channel in 0..<channelCount {
            let samples = channels[channel]
            for index in 0..<frames {
                peak = max(peak, abs(samples[index]))
            }
        }
        guard peak >= minPeak else { return peak }
        let gain = (targetPeak / peak) * max(volume, 0)
        guard abs(gain - 1) >= 0.01 else { return peak }
        for channel in 0..<channelCount {
            let samples = channels[channel]
            for index in 0..<frames {
                let scaled = samples[index] * gain
                samples[index] = max(-1, min(1, scaled))
            }
        }
        return peak
    }

    /// Returns a louder copy of `data` for playback only. The original clip stays in the cache
    /// and history store so a later volume change does not require re-fetching speech.
    static func boosted(_ data: Data, volume: Float) -> Data {
        let clamped = min(max(volume, 0.5), 3.0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return data }
        defer { try? FileManager.default.removeItem(at: url) }
        guard let file = try? AVAudioFile(forReading: url) else { return data }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              (try? file.read(into: buffer)) != nil,
              let channels = buffer.floatChannelData
        else { return data }
        let peak = apply(
            channels: channels,
            channelCount: Int(format.channelCount),
            frames: Int(buffer.frameLength),
            volume: clamped
        )
        guard peak >= minPeak else { return data }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("ntranslate-gain-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: out) }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: format.isInterleaved == false,
        ]
        // `AVAudioFile.write(from:)` raises an uncatchable ObjC exception on a format
        // mismatch, so reject before writing rather than wrapping the call in try.
        // The writer must leave scope before the bytes are read: deinit flushes the header.
        do {
            let writer = try AVAudioFile(forWriting: out, settings: settings)
            guard buffer.format.isEqual(writer.processingFormat) else { return data }
            try writer.write(from: buffer)
        } catch {
            return data
        }
        guard let boosted = try? Data(contentsOf: out), !boosted.isEmpty else { return data }
        return boosted
    }
}
