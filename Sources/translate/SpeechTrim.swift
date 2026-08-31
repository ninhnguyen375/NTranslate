// Finds the first and last audible moment in a TTS clip so playback can skip the silent padding
// most speech engines leave at the head and tail.
import AVFoundation

enum SpeechTrim {
    struct Bounds: Equatable, Sendable {
        let lead: TimeInterval
        let tail: TimeInterval
    }

    /// RMS below this counts as silence (~-45 dBFS). Raise it if the engine leaves audible hiss.
    static let silenceFloor: Float = 0.0056
    /// Kept on both sides so a soft consonant at the very start is not clipped off.
    static let pad: TimeInterval = 0.03
    /// Below this, seeking or stopping early is not worth it.
    static let minimumGain: TimeInterval = 0.05
    private static let windowSeconds = 0.02

    /// Seeks a prepared player past its leading silence, decoding the clip inline. Only for
    /// callers with no chance to analyse ahead of time; short clips cost a few milliseconds.
    static func seekPastLeadingSilence(_ player: AVAudioPlayer, data: Data) {
        guard let bounds = bounds(of: data), bounds.lead >= minimumGain else { return }
        player.currentTime = bounds.lead
    }

    /// Decodes the clip and returns its audible span, or nil when the clip is undecodable or
    /// entirely silent. Blocking: call off the main thread.
    static func bounds(of data: Data) -> Bounds? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let rate = format.sampleRate
        let frameCount = AVAudioFrameCount(file.length)
        guard rate > 0, frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              (try? file.read(into: buffer)) != nil,
              let channels = buffer.floatChannelData
        else { return nil }
        return bounds(
            channels: channels,
            channelCount: Int(format.channelCount),
            frames: Int(buffer.frameLength),
            sampleRate: rate
        )
    }

    static func bounds(
        channels: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        frames: Int,
        sampleRate: Double
    ) -> Bounds? {
        guard frames > 0, channelCount > 0 else { return nil }
        let window = max(1, Int(sampleRate * windowSeconds))
        var firstAudible = -1
        var lastAudible = -1
        var start = 0
        while start < frames {
            let end = min(start + window, frames)
            var sum: Float = 0
            for channel in 0..<channelCount {
                let samples = channels[channel]
                for index in start..<end {
                    let sample = samples[index]
                    sum += sample * sample
                }
            }
            let rms = (sum / Float((end - start) * channelCount)).squareRoot()
            if rms > silenceFloor {
                if firstAudible < 0 { firstAudible = start }
                lastAudible = end
            }
            start = end
        }
        guard firstAudible >= 0 else { return nil }
        let duration = Double(frames) / sampleRate
        let lead = max(0, Double(firstAudible) / sampleRate - pad)
        let tail = min(duration, Double(lastAudible) / sampleRate + pad)
        guard tail > lead else { return nil }
        return Bounds(lead: lead, tail: tail)
    }
}
