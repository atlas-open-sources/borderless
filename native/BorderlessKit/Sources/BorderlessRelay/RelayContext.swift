import Foundation
import BorderlessCore

/// Only spoken source text crosses capture boundaries, never private reply ideas.
public struct RelayContextTurn: Encodable, Sendable, Equatable {
    public let speaker: RelayAudience
    public let source: String
    public init(speaker: RelayAudience, source: String) {
        self.speaker = speaker
        self.source = source
    }

    public static func recent(_ turns: [Turn]) -> [RelayContextTurn] {
        var result: [RelayContextTurn] = []
        var characters = 0
        for turn in turns.suffix(6).reversed() {
            let count = turn.source.unicodeScalars.count
            guard count <= 2_000, characters + count <= 6_000,
                  !turn.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { break }
            result.append(.init(speaker: turn.speaker == .alex ? .host : .guest, source: turn.source))
            characters += count
        }
        return result.reversed()
    }

    static func validate(_ turns: [RelayContextTurn]) throws {
        guard turns.count <= 6,
              turns.reduce(0, { $0 + $1.source.unicodeScalars.count }) <= 6_000,
              turns.allSatisfy({ !$0.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && $0.source.unicodeScalars.count <= 2_000 }) else {
            throw RelayFailure.invalidMessage
        }
    }
}
