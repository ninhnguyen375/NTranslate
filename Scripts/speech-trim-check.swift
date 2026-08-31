// Self-check for SpeechTrim. The package test target needs swift-testing, which the current
// toolchain does not ship, so this runs standalone:
//
//   swiftc -parse-as-library Sources/translate/SpeechTrim.swift \
//     Scripts/speech-trim-check.swift -o /tmp/speech-trim-check \
//     && /tmp/speech-trim-check
import AVFoundation
import Foundation

@main enum SpeechTrimCheck {
    /// 1s clip: 0.30s silence, 0.40s tone, 0.30s silence.
    static func fillTone(_ samples: UnsafeMutablePointer<Float>, _ frameCount: AVAudioFrameCount, _ rate: Double) {
        for index in 0..<Int(frameCount) {
            let time = Double(index) / rate
            samples[index] = (time >= 0.30 && time < 0.70) ? Float(0.5 * sin(2 * .pi * 440 * time)) : 0
        }
    }

    static func main() throws {
        let rate = 44100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let frameCount = AVAudioFrameCount(rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]

        fillTone(samples, frameCount, rate)
        let raw = SpeechTrim.bounds(
            channels: buffer.floatChannelData!, channelCount: 1, frames: Int(frameCount), sampleRate: rate
        )!
        assert(abs(raw.lead - 0.27) < 0.02, "lead off: \(raw.lead)")
        assert(abs(raw.tail - 0.73) < 0.02, "tail off: \(raw.tail)")

        // A clip with nothing above the floor must play untrimmed.
        for index in 0..<Int(frameCount) { samples[index] = 0 }
        assert(SpeechTrim.bounds(
            channels: buffer.floatChannelData!, channelCount: 1, frames: Int(frameCount), sampleRate: rate
        ) == nil)

        // Same clip through a real encoded container, the shape the TTS endpoint returns.
        fillTone(samples, frameCount, rate)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("speech-trim-check.m4a")
        try? FileManager.default.removeItem(at: url)
        do {
            // Scoped so the writer finalises the container before the bytes are read back.
            let file = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1
            ])
            try file.write(from: buffer)
        }
        let encoded = SpeechTrim.bounds(of: try Data(contentsOf: url))!
        try? FileManager.default.removeItem(at: url)
        assert(abs(encoded.lead - 0.27) < 0.05, "encoded lead off: \(encoded.lead)")
        assert(abs(encoded.tail - 0.73) < 0.05, "encoded tail off: \(encoded.tail)")

        print("SpeechTrim OK — lead \(raw.lead), tail \(raw.tail)")
    }
}
