// Offline speech through AVSpeechSynthesizer, shaped to the same `Data` contract the HTTP
// speech provider returns so cache, trim, playback, and history stay unchanged.
import AVFoundation
import Foundation

enum NativeSpeechEngine {
    /// Model strings for the native provider carry this prefix, which is what tells
    /// `Translator.speak` to synthesize locally instead of calling the speech API. Keeping the
    /// provider inside the model string also means a cached clip cannot be mistaken for one made
    /// by the other provider: they hash to different `SpeechIdentity` values.
    static let modelPrefix = "native/"

    /// A language with no installed voice still needs a model string, because the model is part
    /// of the speech cache key. This marker makes synthesis fail with a message naming the
    /// language instead of quietly falling back to the network the user opted out of.
    static let unavailableMarker = "unavailable:"

    /// macOS exposes no public API to install a system voice — AVFAudio can only list what is
    /// already there — so the most an app can do is open the pane where the user installs one.
    /// Verified on macOS 26, where that pane is Accessibility > Read & Speak.
    static let voiceSettingsURLString =
        "x-apple.systempreferences:com.apple.preference.universalaccess?spokenContent"

    static let voiceSettingsPath = "System Settings > Accessibility > Read & Speak"

    enum EngineError: LocalizedError {
        case noVoice(String)
        case silentVoice
        case unsupportedAudioFormat

        var errorDescription: String? {
            switch self {
            case let .noVoice(language):
                return "macOS has no \(language) voice installed. Add one in \(voiceSettingsPath), or switch Speech Provider back to API."
            case .silentVoice:
                return "The macOS voice produced no audio. Try a different voice in \(voiceSettingsPath)."
            case .unsupportedAudioFormat:
                return "The macOS voice returned audio in an unexpected format."
            }
        }
    }

    /// Best installed voice for a config language name such as "Vietnamese", preferring the
    /// highest quality present. Enhanced and premium voices are a manual download in System
    /// Settings, so this returns whatever the user actually has.
    ///
    /// Ties are broken by the user's own preferred regions and then by language tag. A language
    /// like Chinese ships several same-quality regional voices, and picking among them at random
    /// would both pick the wrong script (zh-TW where zh-CN is meant) and make the resulting model
    /// string — a speech cache key — unstable between launches.
    static func voice(for language: String) -> AVSpeechSynthesisVoice? {
        let english = Locale(identifier: "en_US")
        let preferred = Locale.preferredLanguages
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            let code = String(voice.language.prefix(2))
            guard let name = english.localizedString(forLanguageCode: code) else { return false }
            return name.caseInsensitiveCompare(language) == .orderedSame
        }
        return candidates.min { lhs, rhs in
            let lhsRank = (-lhs.quality.rawValue, preferred.contains(lhs.language) ? 0 : 1, lhs.language)
            let rhsRank = (-rhs.quality.rawValue, preferred.contains(rhs.language) ? 0 : 1, rhs.language)
            return lhsRank < rhsRank
        }
    }

    static func voiceIdentifier(for language: String) -> String? {
        voice(for: language)?.identifier
    }

    /// Settings shows this so the user can see which voice a language resolved to, and that a
    /// compact voice is why it sounds worse than the API one.
    static func voiceDescription(for language: String) -> String? {
        guard let voice = voice(for: language) else { return nil }
        let quality: String
        switch voice.quality {
        case .enhanced: quality = "Enhanced"
        case .premium: quality = "Premium"
        default: quality = "Compact"
        }
        // Some voices already carry the tier in their name, e.g. "Zoe (Premium)".
        guard !voice.name.localizedCaseInsensitiveContains(quality) else { return voice.name }
        return "\(voice.name) (\(quality))"
    }

    static func model(for language: String) -> String {
        modelPrefix + (voiceIdentifier(for: language) ?? unavailableMarker + language)
    }

    static func voiceIdentifier(fromModel model: String) -> String? {
        guard model.hasPrefix(modelPrefix) else { return nil }
        return String(model.dropFirst(modelPrefix.count))
    }

    /// Synthesizes to AAC rather than the raw PCM `write` hands back. Raw PCM is roughly 27x
    /// larger, and this audio is persisted into the history store.
    static func synthesize(
        text: String,
        model: String,
        completion: @escaping @Sendable (Result<Data, Error>) -> Void
    ) {
        guard let voiceID = voiceIdentifier(fromModel: model) else {
            completion(.failure(EngineError.unsupportedAudioFormat))
            return
        }
        if voiceID.hasPrefix(unavailableMarker) {
            completion(.failure(EngineError.noVoice(String(voiceID.dropFirst(unavailableMarker.count)))))
            return
        }
        guard let voice = AVSpeechSynthesisVoice(identifier: voiceID) else {
            completion(.failure(EngineError.noVoice(voiceID)))
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ntranslate-\(UUID().uuidString).m4a")
        // `write` delivers buffers on its own queue and needs a live run loop, so the caller is
        // never blocked waiting for it.
        let synthesizer = AVSpeechSynthesizer()
        let box = WriterBox(url: url, synthesizer: synthesizer, completion: completion)
        synthesizer.write(utterance) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            box.accept(pcm)
        }
        // Some voices accept the identifier but never yield a buffer (personal and certain Siri
        // voices). Without this the completion would never fire and the speak button would sit
        // in "Loading" for the rest of the session. Measured throughput is ~290 chars/s, so the
        // allowance scales with the text and still trips long before a user would keep waiting.
        let deadline = 10.0 + Double(text.count) / 100.0
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + deadline) {
            box.failIfUnfinished()
        }
    }
}

/// Holds the output file across `write` callbacks and reports exactly once. It also retains the
/// synthesizer, which AVFoundation does not do for the duration of a write.
private final class WriterBox: @unchecked Sendable {
    private let url: URL
    private let completion: @Sendable (Result<Data, Error>) -> Void
    private let lock = NSLock()
    private var synthesizer: AVSpeechSynthesizer?
    private var file: AVAudioFile?
    private var failure: Error?
    private var finished = false

    init(
        url: URL,
        synthesizer: AVSpeechSynthesizer,
        completion: @escaping @Sendable (Result<Data, Error>) -> Void
    ) {
        self.url = url
        self.synthesizer = synthesizer
        self.completion = completion
    }

    func accept(_ pcm: AVAudioPCMBuffer) {
        // Reporting happens outside the lock: the caller decodes the clip inside `completion`,
        // and doing that here would block AVFoundation's synthesis queue.
        guard let outcome = consume(pcm) else { return }
        completion(outcome)
    }

    func failIfUnfinished() {
        guard let outcome = timeOut() else { return }
        completion(outcome)
    }

    private func consume(_ pcm: AVAudioPCMBuffer) -> Result<Data, Error>? {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return nil }
        // A zero-length buffer is how `write` signals the end of the utterance.
        guard pcm.frameLength > 0 else { return finish() }
        if file == nil {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: pcm.format.sampleRate,
                AVNumberOfChannelsKey: pcm.format.channelCount,
                AVEncoderBitRateKey: 48000,
            ]
            do { file = try AVAudioFile(forWriting: url, settings: settings) }
            catch { failure = error; return finish() }
        }
        // `AVAudioFile.write(from:)` raises an Objective-C exception on a format mismatch, which
        // Swift cannot catch, so the mismatch is rejected before it can terminate the app.
        guard let file, pcm.format.isEqual(file.processingFormat) else {
            failure = NativeSpeechEngine.EngineError.unsupportedAudioFormat
            return finish()
        }
        do { try file.write(from: pcm) } catch { failure = error; return finish() }
        return nil
    }

    private func timeOut() -> Result<Data, Error>? {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return nil }
        failure = NativeSpeechEngine.EngineError.silentVoice
        return finish()
    }

    /// Must be called with `lock` held.
    private func finish() -> Result<Data, Error> {
        finished = true
        file = nil  // closing the file is what flushes the AAC trailer
        synthesizer = nil  // breaks synthesizer -> write closure -> box -> synthesizer
        let data = try? Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)
        if let failure { return .failure(failure) }
        guard let data, !data.isEmpty else {
            return .failure(NativeSpeechEngine.EngineError.silentVoice)
        }
        return .success(data)
    }
}
