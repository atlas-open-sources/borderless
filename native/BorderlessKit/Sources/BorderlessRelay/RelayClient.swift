import Foundation
import BorderlessCore

public enum RelayFailure: Error { case invalidMessage, inactive, invalidAudio, consentRequired, invalidEndpoint }
/// The relay's own reason for ending a session (busy, rate_limited, daily_cap, …), safe to show as is.
public struct RelayRefusal: Error, Equatable, Sendable {
    public let code: String
    public let message: String
    public init(code: String, message: String) { self.code = code; self.message = message }
}
public enum RelayAudience: String, Codable, Sendable { case host, guest }
public enum RelayEvent: Sendable {
    case started, completed, stopped
    case turn(RelayAudience, Turn)
    case partial(RelayAudience, Turn)
    /// Nil when the relay sent no usable reason (older relays send none).
    case failed(RelayRefusal?)
}

/// Wire decoding is separate from transport so recorded fixtures can exercise it.
public enum RelayCodec {
    private struct Envelope: Decodable {
        let type: String
        let audience: RelayAudience?
        let turn: WireTurn?
        let code: String?
        let message: String?
    }
    private struct WireTurn: Decodable {
        let id: Int
        let revision: Int
        let speaker: RelayAudience
        let source: String
        let translation: String
        let replies: [Reply]
        let status: String
        let source_language: String?
        let target_language: String?
    }
    public static func decode(_ data: Data, captureID: UUID) throws -> RelayEvent {
        guard data.count <= 65_536 else { throw RelayFailure.invalidMessage }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        switch envelope.type {
        case "started": return .started
        case "completed": return .completed
        case "stopped": return .stopped
        case "error": return .failed(refusal(code: envelope.code, message: envelope.message))
        case "turn", "partial":
            let partial = envelope.type == "partial"
            guard let wire = envelope.turn, let audience = envelope.audience,
                  wire.status == (partial ? "pending" : "ready"),
                  wire.source_language == nil || ConversationLanguages.names[wire.source_language!] != nil, wire.revision > 0,
                  wire.target_language == nil || (wire.source_language != nil &&
                    wire.target_language != wire.source_language && ConversationLanguages.names[wire.target_language!] != nil),
                  !wire.source.isEmpty, wire.source.count <= 2_000,
                  (partial ? wire.translation.isEmpty : !wire.translation.isEmpty),
                  wire.translation.count <= 2_000,
                  !partial || wire.replies.isEmpty,
                  wire.replies.count <= 2,
                  audience == .host || wire.replies.isEmpty,
                  wire.speaker == .guest || wire.replies.isEmpty,
                  wire.replies.allSatisfy({ !$0.text.isEmpty && $0.text.count <= 300 &&
                      !$0.gloss.isEmpty && $0.gloss.count <= 300 &&
                      ($0.pronunciation?.count ?? 0) <= 300 }) else {
                throw RelayFailure.invalidMessage
            }
            let turn = Turn(id: "\(captureID.uuidString):\(wire.id)",
                            speaker: wire.speaker == .host ? .alex : .lin,
                            source: wire.source, translation: wire.translation,
                            replies: wire.replies, revision: wire.revision, sourceLanguage: wire.source_language, targetLanguage: wire.target_language)
            if partial { return .partial(audience, turn) }
            return .turn(audience, turn)
        default: throw RelayFailure.invalidMessage
        }
    }

    private static let refusalCodeLength = 1...32
    private static let refusalMessageLength = 1...200

    private static func refusal(code: String?, message: String?) -> RelayRefusal? {
        guard let code, let message, refusalCodeLength.contains(code.count),
              code.allSatisfy({ ("a"..."z").contains($0) || $0 == "_" }),
              refusalMessageLength.contains(message.count) else { return nil }
        return RelayRefusal(code: code, message: message)
    }
}

/// Simulator development adapter. Provider credentials never enter this actor.
/// Caller supplies paced PCM and pulls events; no recording or automatic retry.
public actor RelayClient {
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var captureID = UUID()
    private var generation: UInt64 = 0
    private var inputEnded = false
    private let endpoint: RelayEndpoint
    private let installID: UUID?
    /// `installID` lets the hosted relay rate-limit per install; it is random and names no one.
    public init(endpoint: RelayEndpoint = .simulator, installID: UUID? = nil) {
        self.endpoint = endpoint
        self.installID = installID
    }

    public func connect(localToken: String, participant: RelayAudience, consent: Bool,
                        context: [RelayContextTurn] = [], languagePair: [String] = ["en", "es"]) async throws {
        guard ConversationLanguages.validPair(languagePair) else { throw RelayFailure.invalidMessage }
        guard consent else { throw RelayFailure.consentRequired }
        guard localToken.count >= 32, localToken.count <= 256 else { throw RelayFailure.invalidMessage }
        try RelayContextTurn.validate(context)
        stop()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 65
        configuration.timeoutIntervalForResource = 360
        let session = URLSession(configuration: configuration, delegate: RelaySessionDelegate(), delegateQueue: nil)
        self.session = session
        let task = session.webSocketTask(with: endpoint.url)
        task.maximumMessageSize = 65_536
        socket = task
        captureID = UUID()
        inputEnded = false
        let version = generation
        task.resume()
        do {
            struct Handshake: Encodable {
                let type = "start"
                let token: String
                let participant: RelayAudience
                let consent = true
                let context: [RelayContextTurn]
                let language_pair: [String]
                let install_id: String?
            }
            let handshake = Handshake(token: localToken, participant: participant, context: context,
                                      language_pair: languagePair, install_id: installID?.uuidString)
            let data = try JSONEncoder().encode(handshake)
            guard data.count <= 32_768 else { throw RelayFailure.invalidMessage }
            try await task.send(.string(String(decoding: data, as: UTF8.self)))
            guard generation == version else { throw RelayFailure.inactive }
        } catch {
            if generation == version { stop() }
            throw error
        }
    }
    public func sendPCM(_ bytes: Data) async throws {
        guard let socket, !inputEnded else { throw RelayFailure.inactive }
        guard !bytes.isEmpty, bytes.count <= 4_800, bytes.count.isMultiple(of: 2) else {
            throw RelayFailure.invalidAudio
        }
        let version = generation
        try await socket.send(.data(bytes))
        guard generation == version else { throw RelayFailure.inactive }
    }
    public func finishInput() async throws {
        guard let socket, !inputEnded else { throw RelayFailure.inactive }
        inputEnded = true
        try await socket.send(.string("{\"type\":\"end\"}"))
    }
    public func next() async throws -> RelayEvent {
        guard let socket else { throw RelayFailure.inactive }
        let version = generation
        let id = captureID
        do {
            let message = try await socket.receive()
            guard version == generation else { throw RelayFailure.inactive }
            let data: Data
            switch message {
            case .string(let text): data = Data(text.utf8)
            case .data(let bytes): data = bytes
            @unknown default: throw RelayFailure.invalidMessage
            }
            let event = try RelayCodec.decode(data, captureID: id)
            switch event {
            case .stopped, .failed: stop()
            default: break
            }
            return event
        } catch {
            if version == generation { stop() }
            throw error
        }
    }
    public func stop() {
        generation += 1
        socket?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        socket = nil
        session = nil
        inputEnded = true
    }
}
