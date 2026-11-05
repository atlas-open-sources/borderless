import Foundation

public enum Participant: String, Codable, Sendable { case alex, lin }
public struct Reply: Codable, Equatable, Sendable {
    public let text: String
    public let gloss: String
    public let pronunciation: String?
    public init(text: String, gloss: String, pronunciation: String? = nil) {
        self.text = text; self.gloss = gloss; self.pronunciation = pronunciation
    }
}
public struct Turn: Codable, Equatable, Sendable {
    public let id: String
    public let speaker: Participant
    public let source: String
    public let translation: String
    public let replies: [Reply]
    public var sourceLanguage: String?
    public var targetLanguage: String?
    public var direction: String {
        if translation.isEmpty { return "Listening…" }
        if let sourceLanguage, let targetLanguage {
            return "\(sourceLanguage.uppercased()) → \(targetLanguage.uppercased())"
        }
        if sourceLanguage == "es" { return "ES → EN" }
        if sourceLanguage == "en" { return "EN → ES" }
        return speaker == .lin ? "ES → EN" : "EN → ES"
    }
    public var revision: Int?
    public var version: Int { revision ?? 1 }
    public init(id: String, speaker: Participant, source: String, translation: String,
                replies: [Reply] = [], revision: Int = 1, sourceLanguage: String? = nil, targetLanguage: String? = nil) {
        self.id = id; self.speaker = speaker; self.source = source
        self.translation = translation; self.replies = replies; self.revision = revision
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }
}
public struct ReplyToken: Equatable, Sendable {
    public let epoch: UInt64
    public let id: String
    public let revision: Int
}

/// One authoritative phone session; device connectivity is owned by adapters.
public struct Conversation: Sendable {
    public private(set) var epoch: UInt64 = 0
    public private(set) var active = false
    public private(set) var turns: [Turn] = []
    public private(set) var pending: Turn?
    public private(set) var focused = 0
    public private(set) var selected: Int?
    public private(set) var rejected = 0
    public private(set) var actionRevision: UInt64 = 0
    public static let maximumTurns = 256
    public init() {}

    @discardableResult public mutating func start(hostConsent: Bool, guestConsent: Bool) -> Bool {
        guard hostConsent && guestConsent else { return false }
        guard !active else { return true }
        epoch += 1; active = true
        return true
    }
    public mutating func stop() {
        epoch += 1; active = false; turns = []; pending = nil; clearSelection()
    }
    public mutating func withdrawConsent() { stop() }
    private mutating func clearSelection() { focused = 0; selected = nil }
    private mutating func accepts(_ incomingEpoch: UInt64) -> Bool {
        guard active && epoch == incomingEpoch else { rejected += 1; return false }
        return true
    }
    @discardableResult public mutating func receive(_ turn: Turn, epoch: UInt64, final: Bool) -> Bool {
        guard accepts(epoch) else { return false }
        guard !turn.id.isEmpty, turn.version > 0, turn.source.count <= 2_000,
              turn.translation.count <= 4_000,
              turn.replies.count <= 2,
              turn.replies.allSatisfy({ $0.text.count <= 1_000 && $0.gloss.count <= 1_000
                  && ($0.pronunciation?.count ?? 0) <= 1_000 }),
              turn.speaker == .lin || turn.replies.isEmpty else { rejected += 1; return false }
        if let existing = turns.first(where: { $0.id == turn.id }), existing.version >= turn.version {
            rejected += 1; return false
        }
        if let pending, pending.id == turn.id {
            // A final may complete the current revision; partials must advance it.
            guard turn.version >= pending.version,
                  final || turn.version > pending.version else {
                rejected += 1
                return false
            }
        }
        clearSelection()
        actionRevision &+= 1
        if !final { pending = turn; return true }
        // A slow translation for the previous utterance must not erase newer
        // provisional speech. The blank capture placeholder has no source text.
        if pending?.id == turn.id || pending?.source.isEmpty == true { pending = nil }
        if let index = turns.firstIndex(where: { $0.id == turn.id }) {
            // Later translations may depend on corrected context.
            turns.replaceSubrange(index..., with: [turn])
        } else {
            turns.append(turn)
            if turns.count > Self.maximumTurns { turns.removeFirst(turns.count - Self.maximumTurns) }
        }
        return true
    }
    /// A silent capture may end without any finalized turn. Never discard actual
    /// provisional text under a successful completion claim.
    @discardableResult public mutating func completeInput(epoch incomingEpoch: UInt64) -> Bool {
        guard accepts(incomingEpoch) else { return false }
        guard pending == nil || pending?.source.isEmpty == true else { rejected += 1; return false }
        if pending != nil { pending = nil; actionRevision &+= 1 }
        return true
    }

    public var replyToken: ReplyToken? {
        guard active, pending == nil, let turn = turns.last, turn.speaker == .lin,
              !turn.replies.isEmpty else { return nil }
        return ReplyToken(epoch: epoch, id: turn.id, revision: turn.version)
    }
    public func replies(for participant: Participant) -> [Reply] {
        guard participant == .alex, replyToken != nil else { return [] }
        return turns.last?.replies ?? []
    }
    public func replyActionID(at index: Int) -> String? {
        guard replyToken != nil, replies(for: .alex).indices.contains(index) else { return nil }
        return "reply-\(epoch)-\(actionRevision)-\(index)"
    }
    public func replyIndex(for actionID: String) -> Int? {
        replies(for: .alex).indices.first { replyActionID(at: $0) == actionID }
    }
    @discardableResult public mutating func navigate(_ delta: Int, token: ReplyToken) -> Bool {
        guard replyToken == token, [-1, 1].contains(delta) else { rejected += 1; return false }
        focused = min(max(0, focused + delta), replies(for: .alex).count - 1)
        selected = nil
        return true
    }
    @discardableResult public mutating func dismissSelection(token: ReplyToken) -> Bool {
        guard replyToken == token else { rejected += 1; return false }
        selected = nil
        return true
    }
    @discardableResult public mutating func confirm(token: ReplyToken) -> Bool {
        guard replyToken == token else { rejected += 1; return false }
        selected = focused
        return true
    }
}

/// Supply monotonic seconds. Reading older history never blocks new transcript ingestion.
public struct HistoryFollow: Sendable {
    public private(set) var following = true
    public private(set) var resumeAt: TimeInterval?
    public let delay: TimeInterval
    public init(delay: TimeInterval = 20) { self.delay = max(0, delay) }
    public mutating func scroll(atBottom: Bool, now: TimeInterval) {
        following = atBottom; resumeAt = atBottom ? nil : now + delay
    }
    public mutating func activity(now: TimeInterval) { if !following { resumeAt = now + delay } }
    public mutating func resume() { following = true; resumeAt = nil }
    @discardableResult public mutating func tick(now: TimeInterval) -> Bool {
        guard !following, let resumeAt, now >= resumeAt else { return false }
        resume(); return true
    }
}
