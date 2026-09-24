import AVFoundation
import Foundation

@main
struct PronunciationCheck {
    static func main() {
        // LLM path: chat completion whose content is JSON wrapped in a ```json fence.
        let content = "```json\n{\"heard\":\"I taught\",\"score\":45,\"errors\":[{\"word\":\"thought\",\"heard\":\"taught\",\"issue\":\"Sai âm /θ/.\",\"tip\":\"Đưa lưỡi ra.\"},{\"word\":\"booked\",\"heard\":\"\",\"issue\":\"x\",\"tip\":\"y\"}]}\n```"
        let chat = try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
        let llm = try! PronunciationResult.parseLLM(chat)
        assert(llm.score == 45 && llm.header == "Score 45")
        assert(llm.words[1].isOmitted)
        assert(llm.feedbackLines == ["thought: Sai âm /θ/. Đưa lưỡi ra.", "booked: missing"], "\(llm.feedbackLines)")
        // "he" must not match inside "The"; later words search after earlier ones.
        let words = ["the", "weather", "he"].map { PronunciationResult.Word(text: $0, errorType: "Mispronunciation") }
        let ranges = PronunciationHighlight.ranges(of: words, in: "The weather, he said.")
        assert(ranges.map { $0.0 } == [NSRange(location: 0, length: 3), NSRange(location: 4, length: 7), NSRange(location: 13, length: 2)], "\(ranges.map { $0.0 })")
        // Loudness gate: a whisper-level clip is rejected, normal speech level passes.
        func clip(amplitude: Float) -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("level-\(amplitude).wav")
            let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600)!
            buffer.frameLength = 1600
            for i in 0..<1600 { buffer.floatChannelData![0][i] = amplitude * sin(Float(i) * 0.3) }
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16]
            try! AVAudioFile(forWriting: url, settings: settings).write(from: buffer)
            return url
        }
        assert(AudioLevel.quietError(clip(amplitude: 0.01)) != nil)
        assert(AudioLevel.quietError(clip(amplitude: 0.3)) == nil)
        assert(AudioLevel.quietError(URL(fileURLWithPath: "/nonexistent.wav")) == nil)
        print("pronunciation-check OK")
    }
}
