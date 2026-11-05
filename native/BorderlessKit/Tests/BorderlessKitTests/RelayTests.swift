import Foundation
import Testing
import BorderlessRelay
import BorderlessCore

@Test func captureContextIsBoundedSpokenTextOnly() throws {
    let turns = (0..<8).map { Turn(id: String($0), speaker: .lin,
        source: String(repeating: "a", count: 2_000), translation: "Private derived translation",
        replies: [Reply(text: "private option", gloss: "private meaning")]) }
    let context = RelayContextTurn.recent(turns)
    #expect(context.count == 3)
    let json = String(decoding: try JSONEncoder().encode(context), as: UTF8.self)
    #expect(!json.contains("private"))
    #expect(!json.contains("translation"))
    #expect(!json.contains("replies"))
}

@Test func oversizedContextRejectedBeforeNetwork() async {
    let client = RelayClient()
    await #expect(throws: (any Error).self) {
        try await client.connect(localToken: String(repeating: "x", count: 32), participant: .host,
                                 consent: true, context: [.init(speaker: .guest, source: String(repeating: "a", count: 2_001))])
    }
}

@Test func relayEndpointRequiresSecureRemoteTransport() throws {
    #expect(try RelayEndpoint(validating: "ws://127.0.0.1:8766") == .simulator)
    #expect(try RelayEndpoint(validating: "wss://relay.example.test/translate").url.scheme == "wss")
    for address in ["ws://192.168.1.2:8766", "http://localhost:8766", "ws://127.0.0.1:9999",
                    "wss://user:secret@example.test", "wss://example.test?token=secret",
                    "wss://example.test/#secret", "wss:///", "file:///relay"] {
        #expect(throws: (any Error).self) { try RelayEndpoint(validating: address) }
    }
}

private func wire(audience: String = "host", speaker: String = "guest", replies: Bool = true) throws -> Data {
    let choices: [[String: String]] = replies ? [["text": "Bien", "gloss": "Well", "pronunciation": "bee-en"]] : []
    return try JSONSerialization.data(withJSONObject: ["type": "turn", "audience": audience,
        "turn": ["id": 0, "revision": 2, "speaker": speaker, "source": "Hola",
                 "translation": "Hello", "status": "ready", "replies": choices]])
}
@Test func wireCaptureIdentityAndPrivacy() throws {
    let id = UUID()
    guard case .turn(let audience, let turn) = try RelayCodec.decode(wire(), captureID: id) else {
        Issue.record("Expected turn"); return
    }
    #expect(audience == .host)
    #expect(turn.id == "\(id.uuidString):0")
    #expect(turn.speaker == .lin)
    #expect(turn.version == 2)
    #expect(throws: (any Error).self) { try RelayCodec.decode(wire(audience: "guest"), captureID: id) }
    #expect(throws: (any Error).self) { try RelayCodec.decode(wire(speaker: "host"), captureID: id) }
    guard case .turn(.guest, let guest) = try RelayCodec.decode(wire(audience: "guest", replies: false), captureID: id) else {
        Issue.record("Expected guest turn"); return
    }
    #expect(guest.replies.isEmpty)
}
@Test func relayRejectsMissingConsentWithoutNetwork() async throws {
    let client = RelayClient()
    await #expect(throws: (any Error).self) {
        try await client.connect(localToken: String(repeating: "x", count: 40), participant: .host, consent: false)
    }
    await #expect(throws: (any Error).self) { try await client.sendPCM(Data([0, 0])) }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["BORDERLESS_FIXTURE_RELAY"] == "1"))
func realFixtureRelayRoundTrip() async throws {
    let client = RelayClient()
    try await client.connect(localToken: "borderless-synthetic-benchmark-token-only", participant: .guest, consent: true,
                             context: [.init(speaker: .host, source: "Would you like a coffee?")])
    guard case .started = try await client.next() else {
        Issue.record("Relay must acknowledge before client starts audio"); await client.stop(); return
    }
    try await client.sendPCM(Data([0, 0]))
    try await client.finishInput()
    var hostTurns = 0
    var guestTurns = 0
    var stopped = false
    var completed = false
    var pendingIDs: [RelayAudience: String] = [:]
    var partialCount = 0
    while !stopped {
        switch try await client.next() {
        case .partial(let audience, let turn):
            #expect(pendingIDs[audience] == nil)
            #expect(turn.translation.isEmpty && turn.replies.isEmpty)
            #expect(!turn.source.isEmpty)
            pendingIDs[audience] = turn.id
            partialCount += 1
        case .turn(let audience, let turn):
            #expect(pendingIDs.removeValue(forKey: audience) == turn.id)
            if audience == .host { hostTurns += 1 }
            else { guestTurns += 1; #expect(turn.replies.isEmpty) }
        case .completed: completed = true
        case .stopped: stopped = true
        case .failed: Issue.record("Fixture service rejected native client"); stopped = true
        default: break
        }
    }
    #expect(completed)
    #expect(pendingIDs.isEmpty)
    #expect(partialCount == 10)
    #expect(hostTurns == 5)
    #expect(guestTurns == 5)
    await client.stop()
}

@Test func partialWireHasNoTranslationOrPrivateReplies() throws {
    let capture = UUID()
    var turn: [String: Any] = ["id": 4, "revision": 2, "speaker": "guest", "source": "Hola",
                               "translation": "", "replies": [], "status": "pending"]
    func packet(_ turn: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["type": "partial", "audience": "host", "turn": turn])
    }
    guard case .partial(.host, let pending) = try RelayCodec.decode(packet(turn), captureID: capture) else {
        Issue.record("Expected partial"); return
    }
    #expect(pending.source == "Hola" && pending.translation.isEmpty && pending.replies.isEmpty)
    turn["translation"] = "Hello"
    #expect(throws: (any Error).self) { try RelayCodec.decode(packet(turn), captureID: capture) }
    turn["translation"] = ""
    turn["replies"] = [["text": "Bien", "gloss": "Well"]]
    #expect(throws: (any Error).self) { try RelayCodec.decode(packet(turn), captureID: capture) }
}

/// Explicit paid opt-in, generated PCM only. No microphone or provider key in Swift.
@Test(.enabled(if: ProcessInfo.processInfo.environment["BORDERLESS_LIVE_CANARY"] == "1"))
func nativeProviderSpeechRoundTrip() async throws {
    let env = ProcessInfo.processInfo.environment
    let path = try #require(env["BORDERLESS_CANARY_PCM"])
    let token = try #require(env["BORDERLESS_CANARY_TOKEN"])
    let pcm = try Data(contentsOf: URL(fileURLWithPath: path))
    #expect(!pcm.isEmpty && pcm.count <= 240_000 && pcm.count % 2 == 0)
    let client = RelayClient()
    do {
        try await client.connect(localToken: token, participant: .guest, consent: true)
        guard case .started = try await client.next() else { throw RelayFailure.invalidMessage }
        for offset in stride(from: 0, to: pcm.count, by: 4_800) {
            try await client.sendPCM(pcm.subdata(in: offset..<min(offset + 4_800, pcm.count)))
            try await Task.sleep(for: .milliseconds(100))
        }
        try await client.finishInput()
        var host: Turn?
        var guest: Turn?
        var completed = false
        var stopped = false
        var partials = 0
        while !stopped {
            switch try await client.next() {
            case .partial(_, let turn):
                #expect(turn.replies.isEmpty && turn.translation.isEmpty)
                partials += 1
            case .turn(.host, let turn): host = turn
            case .turn(.guest, let turn): guest = turn
            case .completed: completed = true
            case .stopped: stopped = true
            case .failed: throw RelayFailure.invalidMessage
            default: break
            }
        }
        let finalHost = try #require(host)
        let finalGuest = try #require(guest)
        #expect(completed && partials > 0)
        #expect(finalHost.id == finalGuest.id)
        #expect(!finalHost.translation.isEmpty)
        #expect(finalHost.replies.count == 2 && finalGuest.replies.isEmpty)
        #expect(finalHost.replies.allSatisfy { !($0.pronunciation ?? "").isEmpty })
        await client.stop()
    } catch {
        await client.stop()
        throw error
    }
}

@Test func hostCanSpeakSpanishAndSwitchToEnglish() throws {
    for (language, expected) in [("es", "ES → EN"), ("en", "EN → ES")] {
        let data = try JSONSerialization.data(withJSONObject: ["type": "turn", "audience": "guest",
            "turn": ["id": 0, "revision": 1, "speaker": "host", "source": "Spoken words",
                     "translation": "Translated words", "status": "ready", "source_language": language,
                     "replies": []]])
        guard case .turn(.guest, let turn) = try RelayCodec.decode(data, captureID: UUID()) else {
            Issue.record("Expected host speech on guest display"); return
        }
        #expect(turn.speaker == .alex)
        #expect(turn.direction == expected)
        #expect(turn.replies.isEmpty)
    }
}

@Test func experimentalLanguagesDecodeWithActualDirection() throws {
    let data = Data(#"{"type":"turn","audience":"host","turn":{"id":1,"revision":1,"speaker":"host","source":"こんにちは","translation":"Bonjour","status":"ready","replies":[],"source_language":"ja","target_language":"fr"}}"#.utf8)
    guard case .turn(_, let turn) = try RelayCodec.decode(data, captureID: UUID()) else {
        Issue.record("Expected turn"); return
    }
    #expect(turn.direction == "JA → FR")
    #expect(ConversationLanguages.names.count == 25)
    #expect(ConversationLanguages.validPair(["fr", "ja"]))
    #expect(!ConversationLanguages.validPair(["fr", "fr"]))
    #expect(!ConversationLanguages.validPair(["xx", "en"]))
}

@Test func invalidLanguagePairRejectedBeforeNetwork() async {
    let client = RelayClient()
    await #expect(throws: (any Error).self) {
        try await client.connect(localToken: String(repeating: "x", count: 32), participant: .host,
                                 consent: true, languagePair: ["en", "en"])
    }
}

@Test func relayRefusalCarriesItsCodeAndMessage() throws {
    let id = UUID()
    let busy = Data(#"{"type":"error","code":"busy","message":"The translation service is busy. Try again in a minute."}"#.utf8)
    guard case .failed(let refusal) = try RelayCodec.decode(busy, captureID: id) else {
        Issue.record("expected a failure"); return
    }
    #expect(refusal == RelayRefusal(code: "busy", message: "The translation service is busy. Try again in a minute."))
}

@Test func relayErrorWithoutAUsableReasonStaysGeneric() throws {
    let id = UUID()
    let cases = [
        #"{"type":"error"}"#,
        #"{"type":"error","code":"Busy!","message":"x"}"#,
        #"{"type":"error","code":"busy","message":""}"#,
        "{\"type\":\"error\",\"code\":\"busy\",\"message\":\"\(String(repeating: "a", count: 201))\"}",
    ]
    for json in cases {
        guard case .failed(let refusal) = try RelayCodec.decode(Data(json.utf8), captureID: id) else {
            Issue.record("expected a failure for \(json)"); continue
        }
        #expect(refusal == nil)
    }
}
