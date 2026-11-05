import XCTest
import AVFoundation
import BorderlessCore
import BorderlessAudio
import BorderlessRelay
import MetaDATAdapter
@testable import Borderless

final class RehearsalTests: XCTestCase {
    @MainActor func testRelayRefusalIsShownAsTheRelaySaysIt() {
        let refusal = RelayRefusal(code: "daily_cap", message: "Today's live translation allowance is used up. Try again tomorrow.")
        XCTAssertEqual(RehearsalModel.liveFailureMessage(refusal),
                       "Today's live translation allowance is used up. Try again tomorrow. The microphone is off.")
        XCTAssertFalse(RehearsalModel.liveFailureMessage(URLError(.cannotConnectToHost)).contains("Tailscale"))
    }

    @MainActor func testDebugSpeechWAVYieldsItsPCMDataChunk() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "debug-speech-guest-es", withExtension: "wav"))
        let pcm = try XCTUnwrap(WAVFileCapture.pcmSamples(in: Data(contentsOf: url)))
        XCTAssertGreaterThan(pcm.count, 24_000 * 2, "at least a second of 24 kHz mono PCM16")
        XCTAssertTrue(pcm.count.isMultiple(of: 2))
        XCTAssertNil(WAVFileCapture.pcmSamples(in: Data("not a wave file".utf8)))
    }

    func testInstallIdentityIsStable() {
        XCTAssertEqual(InstallIdentity.id, InstallIdentity.id)
    }

    @MainActor func testLiveConversationIsKeptUnderOneEntryAsLinesFinish() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SavedConversations(url: url)
        let id = UUID()
        let hello = Turn(id: "c:1", speaker: .lin, source: "Hola", translation: "Hello", replies: [],
                         sourceLanguage: "es", targetLanguage: "en")
        let pending = Turn(id: "c:2", speaker: .alex, source: "Good", translation: "", replies: [])
        XCTAssertFalse(store.keep(liveConversation: id, turns: [pending], languages: ["en", "es"]), "an unfinished line alone is not kept")
        XCTAssertTrue(store.keep(liveConversation: id, turns: [hello, pending], languages: ["en", "es"]))
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].turns, [hello], "only finished lines are kept")
        let reply = Turn(id: "c:2", speaker: .alex, source: "Good", translation: "Bien", replies: [],
                         sourceLanguage: "en", targetLanguage: "es")
        XCTAssertTrue(store.keep(liveConversation: id, turns: [hello, reply], languages: ["en", "es"]))
        XCTAssertEqual(store.items.count, 1, "the running conversation updates its own entry")
        XCTAssertEqual(store.items[0].turns.count, 2)
        XCTAssertTrue(store.save(turns: [hello, reply], demo: false), "saving what is already kept is a no-op")
        XCTAssertEqual(store.items.count, 1)

        let reopened = SavedConversations(url: url)
        XCTAssertEqual(reopened.items.first?.languages, ["en", "es"])
        XCTAssertEqual(reopened.items.first?.turns.last?.translation, "Bien")
        XCTAssertFalse(reopened.items.first?.demo ?? true)
    }

    @MainActor func testRecordedChoicesAndLanguageSwitch() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "audio-conversation", withExtension: "json"))
        let recording = try JSONDecoder().decode(AudioConversationRecording.self, from: Data(contentsOf: url))
        try recording.validate()
        let cues = try XCTUnwrap(recording.cues)
        XCTAssertEqual(cues.filter { $0.kind == "select" }.count, 2)
        XCTAssertEqual(cues.filter { $0.kind == "freeSpeech" }.count, 1)
        let hosts = recording.events.filter { $0.final && $0.turn.speaker == .alex }
        XCTAssertEqual(hosts.map { $0.turn.sourceLanguage }, ["es", "en", "es"])
        XCTAssertTrue(hosts[1].turn.source.lowercased().contains("oat"))
        XCTAssertTrue(hosts[1].turn.translation.lowercased().contains("avena"))
        XCTAssertTrue(hosts.allSatisfy { $0.turn.replies.isEmpty })
        let model = RehearsalModel(turns: [])
        model.saySomethingElse()
        XCTAssertTrue(model.session.turns.isEmpty)
        XCTAssertNotNil(model.speakingCue)
    }

    @MainActor func testRecordedQuestionsAndBothRepliesRemainTogether() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "audio-conversation", withExtension: "json"))
        let recording = try JSONDecoder().decode(AudioConversationRecording.self, from: Data(contentsOf: url))
        for event in recording.events where event.final && !event.turn.replies.isEmpty {
            let model = RehearsalModel(turns: [event.turn])
            model.setGlasses(mode: .dual, display: .meta)
            model.advance()
            model.publishDisplays()
            await model.waitForDisplayLayout()
            let scene = model.displayScene(.alex)
            let lines = (scene.lines.map(\.text) + scene.cards.flatMap { [$0.title, $0.detail] }).joined(separator: "\n")
            XCTAssertTrue(lines.contains(event.turn.source))
            XCTAssertTrue(lines.contains(event.turn.translation))
            for reply in event.turn.replies {
                XCTAssertTrue(lines.contains(reply.text))
                XCTAssertTrue(lines.contains(reply.gloss))
            }
            XCTAssertEqual(scene.cards.count, 2)
            XCTAssertTrue(scene.actions.isEmpty)
            let guest = model.guestPages.flatMap(\.lines).map(\.text).joined(separator: "")
            XCTAssertTrue(guest.contains(event.turn.source))
            XCTAssertTrue(guest.contains(event.turn.translation))
            XCTAssertTrue(model.guestPages.allSatisfy { $0.actions.isEmpty })
        }
    }

    @MainActor func testPronunciationIsOptInAndSpeaksOnlySelectedSpanishText() {
        let voice = FakePronunciation()
        let turn = Turn(id: "speech", speaker: .lin, source: "Hola", translation: "Hello",
                        replies: [Reply(text: "Bien", gloss: "Well", pronunciation: "byen"),
                                  Reply(text: "Muy bien", gloss: "Very well", pronunciation: "moo-ee byen")])
        let model = RehearsalModel(turns: [turn], pronunciation: voice)
        model.advance()
        XCTAssertFalse(model.pronunciationEnabled)
        model.choose(0)
        XCTAssertTrue(voice.spoken.isEmpty)
        model.setPronunciationEnabled(true)
        model.move(1)
        XCTAssertTrue(voice.spoken.isEmpty)
        model.handleNavigation(.select)
        XCTAssertEqual(voice.spoken, ["es-ES:Muy bien"])
        model.choose(0)
        XCTAssertEqual(voice.spoken, ["es-ES:Muy bien", "es-ES:Bien"])
        model.choose(-1)
        model.choose(99)
        XCTAssertEqual(voice.spoken.count, 2)
        let beforeDisable = voice.stops
        model.setPronunciationEnabled(false)
        XCTAssertGreaterThan(voice.stops, beforeDisable)
        model.choose(1)
        XCTAssertEqual(voice.spoken.count, 2)
        let beforeReset = voice.stops
        model.reset()
        XCTAssertGreaterThan(voice.stops, beforeReset)
    }

    @MainActor func testPronunciationRejectsCaptureAndPublicOutputRoutes() {
        XCTAssertTrue(PronunciationPlayer.personalOutputsOnly([.headphones]))
        XCTAssertTrue(PronunciationPlayer.personalOutputsOnly([.bluetoothA2DP]))
        XCTAssertFalse(PronunciationPlayer.personalOutputsOnly([]))
        XCTAssertFalse(PronunciationPlayer.personalOutputsOnly([.builtInSpeaker]))
        XCTAssertFalse(PronunciationPlayer.personalOutputsOnly([.headphones, .builtInSpeaker]))
        XCTAssertFalse(PronunciationPlayer.personalOutputsOnly([.airPlay]))
        let voice = FakePronunciation()
        let capture = SyntheticCapture()
        let turn = Turn(id: "speech", speaker: .lin, source: "Hola", translation: "Hello",
                        replies: [Reply(text: "Bien", gloss: "Well")])
        let model = RehearsalModel(turns: [turn], microphone: capture, pronunciation: voice)
        model.advance()
        model.setPronunciationEnabled(true)
        capture.state = .capturing
        model.confirm()
        XCTAssertTrue(voice.spoken.isEmpty)
        XCTAssertEqual(model.pronunciationStatus, "Finish microphone capture before playing pronunciation.")
    }

    @MainActor func testBandNavigationIsPrivateAndHistoryIndependent() async {
        let turn = Turn(id: "guest", speaker: .lin, source: "Hola", translation: "Hello",
                        replies: [Reply(text: "Bien", gloss: "Well"), Reply(text: "Mal", gloss: "Not well")])
        let previous = Turn(id: "earlier", speaker: .alex, source: "Good morning", translation: "Buenos días")
        let model = RehearsalModel(turns: [previous, turn])
        model.advance()
        model.advance()
        model.publishDisplays()
        await model.waitForDisplayLayout()
        let guestPage = model.displayPageIndex(.lin)
        model.handleNavigation(.down)
        model.handleNavigation(.select)
        await model.waitForDisplayLayout()
        XCTAssertEqual(model.session.selected, 1)
        XCTAssertEqual(model.session.turns.count, 2)
        XCTAssertTrue(model.session.replies(for: .lin).isEmpty)
        let latest = model.displayPageIndex(.alex)
        XCTAssertGreaterThan(latest, 0)
        model.handleNavigation(.left)
        await model.waitForDisplayLayout()
        XCTAssertEqual(model.displayPageIndex(.alex), latest - 1)
        XCTAssertEqual(model.displayPageIndex(.lin), guestPage)
        model.handleNavigation(.back)
        await model.waitForDisplayLayout()
        XCTAssertNil(model.session.selected)
        XCTAssertEqual(model.displayPageIndex(.alex), model.hostPages.count - 1)
        model.reset()
        model.handleNavigation(.select)
        model.handleNavigation(.down)
        XCTAssertTrue(model.session.turns.isEmpty)
        XCTAssertNil(model.session.selected)
    }

    @MainActor func testResetRejectsInFlightDisplayLayout() async {
        let turn = Turn(id: "long", speaker: .lin, source: String(repeating: "hola ", count: 350),
                        translation: String(repeating: "hello ", count: 300))
        let model = RehearsalModel(turns: [turn])
        model.advance()
        model.publishDisplays()
        model.reset()
        await model.waitForDisplayLayout()
        XCTAssertTrue(model.displayScene(.alex).lines.isEmpty)
        XCTAssertTrue(model.displayScene(.lin).lines.isEmpty)
    }

    func testPhysicalPageCursorFollowsIndependentlyAndResumes() {
        var host = DisplayPageCursor()
        var guest = DisplayPageCursor()
        XCTAssertEqual(host.index(count: 5), 4)
        host.move(-1, count: 5, now: 0)
        XCTAssertEqual(host.index(count: 6), 3)
        XCTAssertEqual(guest.index(count: 6), 5)
        XCTAssertFalse(host.tick(now: 19))
        XCTAssertTrue(host.tick(now: 20))
        XCTAssertEqual(host.index(count: 6), 5)
        guest.move(-1, count: 6, now: 25)
        guest.move(1, count: 6, now: 26)
        XCTAssertEqual(guest.index(count: 7), 6)
    }

    @MainActor func testLiveCaptureRequiresConsentAndValidLocalToken() {
        let capture = SyntheticCapture()
        let relay = SyntheticRelay()
        let model = RehearsalModel(turns: [], microphone: capture, relayFactory: { _ in relay })
        model.startLive(localToken: "short", participant: .guest, consent: true)
        XCTAssertFalse(model.liveActive)
        XCTAssertTrue(model.session.turns.isEmpty)
        model.startLive(localToken: String(repeating: "x", count: 32), participant: .guest, consent: false)
        XCTAssertFalse(model.liveActive)
        XCTAssertTrue(model.session.turns.isEmpty)
        XCTAssertEqual(capture.permissionRequests, 0)
        XCTAssertEqual(capture.starts, 0)
    }

    @MainActor func testOneClickAndPrivateSelection() {
        let guest = Turn(id: "one", speaker: .lin, source: "Hola", translation: "Hello",
                         replies: [Reply(text: "Bien", gloss: "Well"), Reply(text: "Mal", gloss: "Not well")])
        let host = Turn(id: "two", speaker: .alex, source: "Thanks", translation: "Gracias")
        let model = RehearsalModel(turns: [guest, host])
        model.advance()
        XCTAssertEqual(model.session.turns.count, 1)
        model.choose(1)
        XCTAssertEqual(model.session.selected, 1)
        XCTAssertEqual(model.session.turns.count, 1)
        XCTAssertTrue(model.session.replies(for: .lin).isEmpty)
        model.advance()
        XCTAssertNil(model.session.selected)
        XCTAssertTrue(model.session.replies(for: .alex).isEmpty)
        model.reset()
        XCTAssertTrue(model.session.turns.isEmpty)
        XCTAssertEqual(model.cursor, 0)
    }
}

@MainActor
private final class SyntheticCapture: CaptureSource {
    var state: PhoneMicrophone.State = .idle
    var permissionRequests = 0
    var starts = 0
    var stops = 0
    var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    func requestPermission() async -> Bool { permissionRequests += 1; return true }
    func start(maximumSeconds: Int) throws -> AsyncThrowingStream<Data, Error> {
        XCTAssertEqual(maximumSeconds, 60)
        starts += 1
        state = .capturing
        let pair = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(8))
        continuation = pair.continuation
        return pair.stream
    }
    func stop() {
        stops += 1
        state = .idle
        continuation?.finish()
        continuation = nil
    }
    func emit() { continuation?.yield(Data([0, 0])) }
}

private actor SyntheticRelay: LiveRelay {
    private var events: [RelayEvent] = [.started]
    private var waiting: CheckedContinuation<RelayEvent, Error>?
    private var connectionGate: CheckedContinuation<Void, Never>?
    private let holdConnect: Bool
    private let completion: Turn?
    private(set) var contexts: [[RelayContextTurn]] = []
    private(set) var connects = 0
    private(set) var sent = 0
    private(set) var closed = false
    private(set) var stopCalls = 0
    init(completion: Turn? = nil, holdConnect: Bool = false, holdHandshake: Bool = false) {
        if holdHandshake { events = [] }
        self.completion = completion
        self.holdConnect = holdConnect
    }
    func connect(localToken: String, participant: RelayAudience, consent: Bool, context: [RelayContextTurn], languagePair: [String]) async throws {
        contexts.append(context)
        connects += 1
        if holdConnect { await withCheckedContinuation { connectionGate = $0 } }
    }
    func releaseConnection() { connectionGate?.resume(); connectionGate = nil }
    func sendPCM(_ bytes: Data) async throws {
        guard !closed else { throw RelayFailure.inactive }
        sent += 1
    }
    func finishInput() async throws {
        guard !closed else { throw RelayFailure.inactive }
        if let completion {
            emit(.turn(.host, completion)); emit(.completed); emit(.stopped)
        }
    }
    func next() async throws -> RelayEvent {
        guard !closed else { throw RelayFailure.inactive }
        if !events.isEmpty { return events.removeFirst() }
        return try await withCheckedThrowingContinuation { waiting = $0 }
    }
    func emit(_ event: RelayEvent) {
        if let waiting { self.waiting = nil; waiting.resume(returning: event) }
        else { events.append(event) }
    }
    func stop() {
        stopCalls += 1
        closed = true
        waiting?.resume(throwing: RelayFailure.inactive); waiting = nil
        events = []
    }
}

extension RehearsalTests {
    @MainActor func testNewCaptureCarriesSpokenContextAndResetRemovesIt() async {
        let audio = SyntheticCapture()
        let first = SyntheticRelay(completion: guestTurn())
        let second = SyntheticRelay()
        let third = SyntheticRelay()
        var relays = [first, second, third]
        let model = RehearsalModel(turns: [], microphone: audio, relayFactory: { _ in relays.removeFirst() })
        let token = String(repeating: "x", count: 32)
        model.startLive(localToken: token, participant: .guest, consent: true)
        await eventually { audio.starts == 1 }
        model.finishUtterance()
        await eventually { !model.liveActive }
        model.startLive(localToken: token, participant: .host, consent: true)
        await eventually { audio.starts == 2 }
        XCTAssertNil(model.session.replyToken, "New capture invalidates prior reply actions immediately")
        let context = await second.contexts.first
        XCTAssertEqual(context, [RelayContextTurn(speaker: .guest, source: "¿Cómo estás?")])
        model.reset()
        model.startLive(localToken: token, participant: .guest, consent: true)
        await eventually { audio.starts == 3 }
        let freshContext = await third.contexts.first
        XCTAssertEqual(freshContext, [])
        model.stopLive()
        await eventually { await third.closed }
    }

    @MainActor private func eventually(_ condition: @escaping @MainActor () async -> Bool,
                                      file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Synthetic orchestration did not reach expected state", file: file, line: line)
    }

    @MainActor private func guestTurn(_ id: String = "synthetic-live") -> Turn {
        Turn(id: id, speaker: .lin, source: "¿Cómo estás?", translation: "How are you?",
             replies: [Reply(text: "Bien", gloss: "Well", pronunciation: "byen")])
    }

    @MainActor func testStalledHandshakeTimesOutWithoutStartingMicrophone() async {
        let audio = SyntheticCapture()
        let relay = SyntheticRelay(holdHandshake: true)
        let model = RehearsalModel(turns: [], microphone: audio, connectionTimeout: .milliseconds(50),
                                  relayFactory: { _ in relay })
        model.startLive(localToken: String(repeating: "x", count: 32), participant: .guest, consent: true)
        await eventually { !model.liveActive }
        XCTAssertEqual(audio.starts, 0)
        XCTAssertTrue(model.relayStatus?.contains("Cannot reach the translation service") == true)
        let closed = await relay.closed
        XCTAssertTrue(closed)
    }

    @MainActor func testNormalLiveCompletionRetainsPrivateReplies() async {
        let audio = SyntheticCapture()
        let relay = SyntheticRelay(completion: guestTurn())
        let model = RehearsalModel(turns: [], microphone: audio, relayFactory: { _ in relay })
        model.startLive(localToken: String(repeating: "x", count: 32), participant: .guest, consent: true)
        await eventually { audio.starts == 1 }
        audio.emit()
        await eventually { await relay.sent == 1 }
        model.finishUtterance()
        await eventually { !model.liveActive }
        XCTAssertEqual(model.session.turns.count, 1)
        XCTAssertNotNil(model.session.replyToken)
        XCTAssertEqual(model.session.replies(for: .alex).count, 1)
        model.enterBackground()
        XCTAssertEqual(model.session.turns.count, 1, "Completed history survives companion handoff")
        XCTAssertTrue(model.liveHistory)
        XCTAssertTrue(model.session.replies(for: .lin).isEmpty)
        let closed = await relay.closed
        XCTAssertTrue(closed)
        XCTAssertEqual(audio.state, .idle)
        model.reset()
    }

    @MainActor func testSilentLiveCompletionClearsListeningPlaceholder() async {
        let audio = SyntheticCapture()
        let relay = SyntheticRelay()
        let model = RehearsalModel(turns: [], microphone: audio, relayFactory: { _ in relay })
        model.startLive(localToken: String(repeating: "x", count: 32), participant: .guest, consent: true)
        await eventually { audio.starts == 1 }
        XCTAssertNotNil(model.session.pending)
        await relay.emit(.completed)
        await relay.emit(.stopped)
        model.finishUtterance()
        await eventually { !model.liveActive }
        XCTAssertNil(model.session.pending)
        XCTAssertTrue(model.session.turns.isEmpty)
    }

    @MainActor func testLivePartialAppearsBeforeTranslationAndInvalidatesReplies() async {
        let audio = SyntheticCapture()
        let relay = SyntheticRelay()
        let model = RehearsalModel(turns: [], microphone: audio, relayFactory: { _ in relay })
        model.startLive(localToken: String(repeating: "x", count: 32), participant: .guest, consent: true)
        await eventually { audio.starts == 1 }
        let pending = Turn(id: "speech", speaker: .lin, source: "Hola", translation: "", revision: 2)
        await relay.emit(.partial(.host, pending))
        await eventually { model.session.pending?.source == "Hola" }
        XCTAssertTrue(model.session.turns.isEmpty)
        XCTAssertNil(model.session.replyToken)
        model.publishDisplays()
        await model.waitForDisplayLayout()
        XCTAssertTrue(model.displayScene(.alex).lines.contains { $0.text == "Hola" })
        XCTAssertTrue(model.displayScene(.lin).actions.isEmpty)
        await relay.emit(.turn(.host, Turn(id: "speech", speaker: .lin, source: "Hola",
                                          translation: "Hello", revision: 2)))
        await eventually { model.session.turns.count == 1 }
        XCTAssertNil(model.session.pending)
        model.stopLive()
        await eventually { await relay.closed }
    }

    @MainActor func testBackgroundCancelsActiveCapture() async {
        let audio = SyntheticCapture()
        let relay = SyntheticRelay()
        let model = RehearsalModel(turns: [], microphone: audio, relayFactory: { _ in relay })
        model.startLive(localToken: String(repeating: "x", count: 32), participant: .guest, consent: true)
        await eventually { audio.starts == 1 }
        model.enterBackground()
        await eventually { await relay.closed }
        XCTAssertFalse(model.liveActive)
        XCTAssertEqual(audio.state, .idle)
        XCTAssertTrue(model.session.turns.isEmpty)
    }

    @MainActor func testExplicitStopCancelsBothDirectionsAndRejectsQueuedFrames() async {
        let audio = SyntheticCapture()
        let relay = SyntheticRelay()
        let model = RehearsalModel(turns: [], microphone: audio, relayFactory: { _ in relay })
        model.startLive(localToken: String(repeating: "x", count: 32), participant: .guest, consent: true)
        await eventually { audio.starts == 1 }
        audio.emit()
        await eventually { await relay.sent == 1 }
        await relay.emit(.turn(.host, guestTurn()))
        await eventually { model.session.turns.count == 1 }
        let oldProducer = audio.continuation
        model.stopLive()
        oldProducer?.yield(Data([0, 0]))
        await relay.emit(.turn(.host, guestTurn("late")))
        await eventually { await relay.closed }
        let sent = await relay.sent
        XCTAssertEqual(sent, 1)
        XCTAssertTrue(model.session.turns.isEmpty)
        XCTAssertNil(model.session.replyToken)
        XCTAssertFalse(model.liveActive)
        XCTAssertEqual(audio.state, .idle)
    }

    @MainActor func testRelayFailureClosesCaptureAndClearsDeliveredContent() async {
        let audio = SyntheticCapture()
        let relay = SyntheticRelay()
        let model = RehearsalModel(turns: [], microphone: audio, relayFactory: { _ in relay })
        model.startLive(localToken: String(repeating: "x", count: 32), participant: .guest, consent: true)
        await eventually { audio.starts == 1 }
        await relay.emit(.turn(.host, guestTurn()))
        await eventually { model.session.replyToken != nil }
        await relay.emit(.failed(nil))
        await eventually { !model.liveActive }
        XCTAssertTrue(model.session.turns.isEmpty)
        XCTAssertEqual(audio.state, .idle)
        let closed = await relay.closed
        XCTAssertTrue(closed)
    }

    @MainActor func testLatePriorCaptureCannotMutateOrStopNewCapture() async {
        let audio = SyntheticCapture()
        let old = SyntheticRelay(holdConnect: true)
        let current = SyntheticRelay()
        var factoryCalls = 0
        let model = RehearsalModel(turns: [], microphone: audio, relayFactory: { _ in
            factoryCalls += 1
            return factoryCalls == 1 ? old : current
        })
        let token = String(repeating: "x", count: 32)
        model.startLive(localToken: token, participant: .guest, consent: true)
        await eventually { await old.connects == 1 }
        model.stopLive()
        model.startLive(localToken: token, participant: .guest, consent: true)
        await eventually { audio.starts == 1 }
        await current.emit(.turn(.host, guestTurn("current")))
        await eventually { model.session.turns.first?.id == "current" }
        await old.releaseConnection()
        await old.emit(.turn(.host, guestTurn("stale")))
        // Wait for explicit Stop and the cancelled old operation's final cleanup.
        await eventually { await old.stopCalls >= 2 }
        XCTAssertTrue(model.liveActive)
        XCTAssertEqual(audio.state, .capturing)
        XCTAssertEqual(model.session.turns.map(\.id), ["current"])
        model.stopLive()
        await eventually { await current.closed }
    }
}

/// Single-glasses mode: attribution, glasses routing, Play language and capture gating.
extension RehearsalTests {
    @MainActor func testPlaySpeaksEachLineInTheListenersLanguage() {
        let speech = FakeSpeech()
        let guest = Turn(id: "guest", speaker: .lin, source: "Hola", translation: "Hello")
        let host = Turn(id: "host", speaker: .alex, source: "Thanks", translation: "Gracias")
        // Recorded demo: the host reads a suggested Spanish reply aloud.
        let reading = Turn(id: "reading", speaker: .alex, source: "Sí, vamos", translation: "Yes, let's go",
                           sourceLanguage: "es")
        let model = RehearsalModel(turns: [guest, host, reading], speech: speech)
        for _ in 0..<3 { model.advance() }
        XCTAssertTrue(speech.spoken.isEmpty, "Never automatic")
        model.togglePlayback("guest")
        XCTAssertEqual(model.speakingTurnID, "guest")
        model.togglePlayback("guest")
        XCTAssertNil(model.speakingTurnID, "Play toggles to Stop")
        model.togglePlayback("host")
        model.togglePlayback("reading")
        model.togglePlayback("missing")
        XCTAssertEqual(speech.spoken, ["en:Hello", "es:Gracias", "es:Sí, vamos"])
        XCTAssertEqual(model.listenerLanguage(for: guest), "en")
        XCTAssertEqual(model.listenerLanguage(for: host), "es")
        XCTAssertEqual(model.speakingTurnID, "reading")
        model.reset()
        XCTAssertNil(model.speakingTurnID, "Reset stops playback of a line that no longer exists")
    }

    @MainActor func testCaptureStopsPlaybackFirstAndPlaybackIsRefusedWhileCapturing() async {
        let audio = SyntheticCapture()
        let first = SyntheticRelay(completion: guestTurn())
        let second = SyntheticRelay()
        var relays = [first, second]
        let speech = FakeSpeech()
        let model = RehearsalModel(turns: [], microphone: audio, speech: speech,
                                   relayFactory: { _ in relays.removeFirst() })
        let token = String(repeating: "x", count: 32)
        XCTAssertEqual(model.glassesMode, .single)
        XCTAssertFalse(model.conversationConsent)
        model.startLive(localToken: token, participant: .guest, consent: true)
        XCTAssertTrue(model.conversationConsent)
        await eventually { audio.starts == 1 }
        XCTAssertEqual(model.session.pending?.speaker, .lin, "Them maps onto a guest capture")
        XCTAssertEqual(model.relayStatus, "Listening to Them · Spanish · 60 seconds maximum")
        model.finishUtterance()
        await eventually { !model.liveActive }
        model.togglePlayback("synthetic-live")
        XCTAssertEqual(speech.spoken, ["en:How are you?"])
        XCTAssertEqual(model.speakingTurnID, "synthetic-live")
        model.startLive(localToken: token, participant: .host, consent: true)
        XCTAssertNil(model.speakingTurnID, "Playback stops before the capture begins")
        XCTAssertEqual(audio.starts, 1, "and the microphone opens only afterwards")
        await eventually { audio.starts == 2 }
        XCTAssertEqual(model.session.pending?.speaker, .alex, "Me maps onto a host capture")
        model.togglePlayback("synthetic-live")
        XCTAssertEqual(speech.spoken.count, 1, "No playback while the microphone is on")
        XCTAssertNotNil(model.speechNotice)
        model.stopLive()
        XCTAssertFalse(model.conversationConsent, "Stop & clear ends conversation consent")
        await eventually { await second.closed }
    }

    @MainActor func testSingleGlassesRoutesTheHostViewToTheChosenDisplay() async {
        let speech = FakeSpeech()
        let turn = Turn(id: "guest", speaker: .lin, source: "Hola", translation: "Hello",
                        replies: [Reply(text: "Bien", gloss: "Well"), Reply(text: "Mal", gloss: "Not well")])
        let model = RehearsalModel(turns: [turn], speech: speech)
        model.setGlasses(mode: .single, display: .g2)
        model.advance()
        model.publishDisplays()
        await model.waitForDisplayLayout()
        let g2 = model.hostPages.flatMap(\.lines).map(\.text).joined(separator: "\n")
        XCTAssertTrue(g2.contains("Hello"), "The wearer reads the guest in their own language")
        XCTAssertTrue(g2.contains("Bien"), "The single wearer keeps reply ideas")
        XCTAssertTrue(model.hostPages.allSatisfy { $0.cards.isEmpty }, "Fitted as G2 text rows")
        XCTAssertTrue(model.displayScene(.lin).lines.isEmpty, "No guest display in single mode")

        model.togglePlayback("guest")
        model.setGlasses(mode: .single, display: .meta)
        await model.waitForDisplayLayout()
        XCTAssertEqual(model.session.turns.count, 1, "Changing the wearer's display keeps the conversation")
        XCTAssertEqual(model.displayScene(.alex).cards.count, 2)
        XCTAssertEqual(model.speakingTurnID, "guest")

        model.setGlasses(mode: .dual, display: .meta)
        await model.waitForDisplayLayout()
        XCTAssertTrue(model.session.turns.isEmpty, "G2 changes owner: never carry host content to it")
        XCTAssertNil(model.speakingTurnID)
        XCTAssertTrue(model.displayScene(.alex).lines.isEmpty)
        XCTAssertTrue(model.displayScene(.lin).lines.isEmpty)

        // A layout begun in one mode never lands after a switch.
        model.advance()
        model.publishDisplays()
        model.setGlasses(mode: .single, display: .g2)
        await model.waitForDisplayLayout()
        XCTAssertTrue(model.hostPages.flatMap(\.lines).isEmpty)
        XCTAssertTrue(model.guestPages.flatMap(\.lines).isEmpty)
    }
}

@MainActor
private final class FakeSpeech: TranslationSpeaking {
    var speakingID: String?
    var status: String?
    var spoken: [String] = []
    var stops = 0
    func speak(_ text: String, language: String, id: String) { spoken.append("\(language):\(text)"); speakingID = id }
    func stop() { stops += 1; speakingID = nil }
}

@MainActor
private final class FakePronunciation: PronunciationPlaying {
    var status = "Ready"
    var spoken: [String] = []
    var stops = 0
    func speak(_ text: String, language: String) { spoken.append("\(language):\(text)") }
    func stop() { stops += 1 }
}
