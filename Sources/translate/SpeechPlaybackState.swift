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
    case pause
    case resume
}

struct SpeechPlaybackState: Equatable, Sendable {
    private enum Phase: Equatable, Sendable {
        case idle
        case loading(SpeechIdentity, generation: Int)
        case playing(SpeechIdentity)
        case paused(SpeechIdentity)
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

    mutating func pause(_ identity: SpeechIdentity) -> Bool {
        guard phase == .playing(identity) else { return false }
        phase = .paused(identity)
        return true
    }

    mutating func resume(_ identity: SpeechIdentity) -> Bool {
        guard phase == .paused(identity) else { return false }
        phase = .playing(identity)
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

    func action(for identity: SpeechIdentity) -> SpeechButtonAction {
        switch phase {
        case let .loading(active, _) where active == identity:
            return .loading
        case let .playing(active) where active == identity:
            return .pause
        case let .paused(active) where active == identity:
            return .resume
        default:
            return .play
        }
    }
}
