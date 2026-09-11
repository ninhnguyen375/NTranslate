// Self-check for SpeechGain. The package test target needs swift-testing, which the current
// toolchain does not ship, so this runs standalone:
//
//   swiftc -parse-as-library Sources/translate/SpeechGain.swift \
//     Scripts/speech-gain-check.swift -o /tmp/speech-gain-check \
//     && /tmp/speech-gain-check
import AVFoundation
import Foundation

@main enum SpeechGainCheck {
    static func fillTone(
        _ samples: UnsafeMutablePointer<Float>,
        _ frameCount: Int,
        amplitude: Float
    ) {
        for index in 0..<frameCount {
            samples[index] = amplitude * sin(Float(index) * 0.1)
        }
    }

    static func peak(_ samples: UnsafeMutablePointer<Float>, _ frameCount: Int) -> Float {
        var peak: Float = 0
        for index in 0..<frameCount {
            peak = max(peak, abs(samples[index]))
        }
        return peak
    }

    static func main() throws {
        let frames = 2048
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let samples = buffer.floatChannelData![0]
        let channels = buffer.floatChannelData!

        // Quiet TTS-like clip: peak-normalize at volume 1.0 should reach the target peak.
        fillTone(samples, frames, amplitude: 0.25)
        let quietPeak = SpeechGain.apply(channels: channels, channelCount: 1, frames: frames, volume: 1.0)
        assert(abs(quietPeak - 0.25) < 0.01, "reported peak off: \(quietPeak)")
        assert(abs(peak(samples, frames) - SpeechGain.targetPeak) < 0.02, "normalized peak off: \(peak(samples, frames))")

        // Already-loud clip at volume 1.0 stays at the target, not boosted into clipping.
        fillTone(samples, frames, amplitude: SpeechGain.targetPeak)
        _ = SpeechGain.apply(channels: channels, channelCount: 1, frames: frames, volume: 1.0)
        assert(abs(peak(samples, frames) - SpeechGain.targetPeak) < 0.02, "loud clip drifted: \(peak(samples, frames))")

        // Extra volume after normalize must not exceed 1.0.
        fillTone(samples, frames, amplitude: 0.4)
        _ = SpeechGain.apply(channels: channels, channelCount: 1, frames: frames, volume: 2.0)
        assert(peak(samples, frames) <= 1.0 + 0.001, "boost clipped past 1: \(peak(samples, frames))")
        assert(peak(samples, frames) > 0.95, "2x boost should sit near full scale: \(peak(samples, frames))")

        // Near-silence is left alone so we do not amplify noise.
        for index in 0..<frames { samples[index] = 0.0001 }
        _ = SpeechGain.apply(channels: channels, channelCount: 1, frames: frames, volume: 3.0)
        assert(peak(samples, frames) < 0.001, "silence was amplified: \(peak(samples, frames))")

        // Encoded quiet clip must come back near full scale after a 1.0 boost.
        fillTone(samples, frames, amplitude: 0.25)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("speech-gain-check.m4a")
        try? FileManager.default.removeItem(at: url)
        do {
            let file = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1
            ])
            try file.write(from: buffer)
        }
        let boosted = SpeechGain.boosted(try Data(contentsOf: url), volume: 1.0)
        try? FileManager.default.removeItem(at: url)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("speech-gain-check.wav")
        try? FileManager.default.removeItem(at: out)
        try boosted.write(to: out)
        let decoded = try AVAudioFile(forReading: out)
        assert(decoded.length > 0, "boosted file has no frames")
        let decodedBuffer = AVAudioPCMBuffer(
            pcmFormat: decoded.processingFormat,
            frameCapacity: AVAudioFrameCount(decoded.length)
        )!
        try decoded.read(into: decodedBuffer)
        try? FileManager.default.removeItem(at: out)
        let decodedPeak = peak(decodedBuffer.floatChannelData![0], Int(decodedBuffer.frameLength))
        assert(abs(decodedPeak - SpeechGain.targetPeak) < 0.08, "encoded boost peak off: \(decodedPeak)")

        print("SpeechGain OK")
    }
}
