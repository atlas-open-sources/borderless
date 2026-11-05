import Foundation
import BorderlessCore

/// Timestamped outputs retained from the actual speech/translation pipeline.
/// This archive replays provider results; it does not perform fresh inference.
struct AudioConversationRecording: Decodable {
    struct Event: Decodable {
        let at: Double
        let turn: Turn
        let final: Bool
    }
    struct Cue: Decodable {
        let at: Double
        let kind: String
        let turnID: String?
        let index: Int?
        let text: String?
    }
    let cues: [Cue]?
    let duration: Double
    let events: [Event]

    func validate() throws {
        guard duration.isFinite, duration > 0, duration <= 180,
              !events.isEmpty, events.count <= 2_000 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for cue in cues ?? [] {
            guard cue.at.isFinite, cue.at >= 0, cue.at <= duration,
                  cue.kind == "select" || cue.kind == "freeSpeech" else { throw CocoaError(.fileReadCorruptFile) }
            if cue.kind == "select" {
                guard let index = cue.index, (0..<2).contains(index),
                      let event = events.last(where: { $0.final && $0.at <= cue.at }),
                      event.turn.id == cue.turnID, event.turn.replies.indices.contains(index),
                      event.turn.replies[index].text == cue.text else { throw CocoaError(.fileReadCorruptFile) }
            }
        }
        var previous = 0.0
        for event in events {
            guard event.at.isFinite, event.at >= previous, event.at <= duration,
                  event.turn.speaker == .lin || event.turn.replies.isEmpty,
                  event.final || event.turn.replies.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            previous = event.at
        }
    }
}
