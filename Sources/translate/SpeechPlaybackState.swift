import Foundation

enum SpeechKind: Equatable, Hashable, Sendable {
    case source
    case result
}

struct SpeechIdentity: Equatable, Hashable, Sendable {
    let kind: SpeechKind
    let text: String
    let model: String
    let recordID: UUID?

    init(kind: SpeechKind, text: String, model: String, recordID: UUID? = nil) {
        self.kind = kind
        self.text = text
        self.model = model
        self.recordID = recordID
    }
}

enum SpeechButtonAction: Equatable, Sendable {
    case play
    case loading

    /// A button only shows loading when the audio being fetched is its own speed; otherwise it
    /// offers to start playback at that speed.
    func applies(whenSlow buttonIsSlow: Bool, activeIsSlow: Bool) -> SpeechButtonAction {
        buttonIsSlow == activeIsSlow ? self : .play
    }
}

struct SpeechPlaybackState: Equatable, Sendable {
    private enum Phase: Equatable, Sendable {
        case idle
        case loading(SpeechIdentity, generation: Int)
        case playing(SpeechIdentity)
    }

    private var phase: Phase = .idle
    private var generation = 0

    mutating func beginLoading(_ identity: SpeechIdentity) -> Int {
        generation += 1
        phase = .loading(identity, generation: generation)
        return generation
    }

    mutating func beginPlaying(_ identity: SpeechIdentity) {
        generation += 1
        phase = .playing(identity)
    }

    func accepts(generation: Int, identity: SpeechIdentity) -> Bool {
        phase == .loading(identity, generation: generation)
    }

    mutating func markPlaying(generation: Int, identity: SpeechIdentity) -> Bool {
        guard accepts(generation: generation, identity: identity) else { return false }
        phase = .playing(identity)
        return true
    }

    mutating func finishLoading(generation: Int, identity: SpeechIdentity) -> Bool {
        guard accepts(generation: generation, identity: identity) else { return false }
        phase = .idle
        return true
    }

    mutating func invalidateRequests() {
        generation += 1
        if case .loading = phase {
            phase = .idle
        }
    }

    mutating func reset() {
        generation += 1
        phase = .idle
    }

    /// Playing audio keeps the button on play: clicking it again restarts from the beginning.
    func action(for identity: SpeechIdentity) -> SpeechButtonAction {
        if case let .loading(active, _) = phase, active == identity { return .loading }
        return .play
    }
}
