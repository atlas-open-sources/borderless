import BorderlessCore
import GlassesSceneKit

/// Maps the same authoritative session to both manufacturers' existing renderers.
/// The app owns history, viewport selection and device lifecycle. This scene is a
/// bounded logical window; each renderer still applies its physical row budget.
public enum ConversationScene {
    public static func make(_ session: Conversation, for wearer: Participant,
                            connected: Bool = true, through turnID: String? = nil,
                            maximumTurns: Int = 2) -> GlassesScene {
        guard session.active && connected else { return .empty }
        let end: Int
        if let turnID {
            guard let index = session.turns.firstIndex(where: { $0.id == turnID }) else { return .empty }
            end = index + 1
        } else { end = session.turns.count }
        let start = max(0, end - max(1, min(maximumTurns, 4)))
        let history = Array(session.turns[start..<end])
        var lines: [GlassesScene.Line] = history.flatMap { turn in
            let own = turn.speaker == wearer
            let name: String
            if own { name = "You" }
            else if turn.speaker == .lin { name = "Sofía" }
            else { name = "Partner" }
            var result = [GlassesScene.Line(name, role: .heading)]
            result.append(.init(turn.source, role: .secondary))
            result.append(.init(turn.translation))
            return result
        }
        let isLatest = turnID == nil || turnID == session.turns.last?.id
        if isLatest, let pending = session.pending {
            lines.append(.init(pending.source.isEmpty ? "Listening…" : pending.source, role: .status))
        }
        let replies = isLatest ? session.replies(for: wearer) : []
        let cards = replies.enumerated().compactMap { index, reply -> GlassesScene.Card? in
            guard let id = session.replyActionID(at: index) else { return nil }
            return .init(id: id, title: reply.text, detail: reply.gloss,
                         focused: index == (session.selected ?? session.focused))
        }
        return GlassesScene(lines: lines, actions: [], cards: cards)
    }
}
