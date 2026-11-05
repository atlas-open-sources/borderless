import Foundation
import AVFoundation
import Observation
import BorderlessCore
import BorderlessRelay
import BorderlessAudio
import BorderlessG2
import MetaDATAdapter
import BorderlessDisplay
import GlassesSceneKit

/// Single: one wearer (the host) on Meta or G2; everyone else talks near the phone.
/// Dual: host on Meta, guest on G2.
enum GlassesMode: String, CaseIterable, Sendable { case single, dual }

@MainActor @Observable
final class RehearsalModel {
    private(set) var session = Conversation()
    private(set) var playing = false
    private(set) var error: String?
    private(set) var cursor = 0
    let meta = MetaConnection()
    private(set) var g2Enabled = false
    private let g2 = G2Companion()
    private let connectionTimeout: Duration
    private(set) var relayStatus: String?
    private var relay: (any LiveRelay)?
    let microphone: any CaptureSource
    private let relayFactory: @MainActor (RelayEndpoint) -> any LiveRelay
    private(set) var liveActive = false
    private var liveTask: Task<Void, Never>?
    private var liveGeneration: UInt64 = 0
    private(set) var liveHistory = false
    private(set) var hostLanguage = "en"
    private(set) var guestLanguage = "es"

    func setLanguages(host: String, guest: String) {
        guard !liveActive, ConversationLanguages.validPair([host, guest]),
              host != hostLanguage || guest != guestLanguage else { return }
        reset()
        hostLanguage = host
        guestLanguage = guest
    }

    private(set) var glassesMode: GlassesMode = .single
    private(set) var wearerDisplay: GlassesDisplay = .meta

    /// Changing who owns G2 clears the conversation: host reply ideas must never
    /// reach a display that now belongs to a guest. Switching the single wearer's
    /// display keeps the transcript and disconnects the pair no longer worn.
    func setGlasses(mode: GlassesMode, display: GlassesDisplay) {
        guard !liveActive, mode != glassesMode || display != wearerDisplay else { return }
        let ownerChanged = mode != glassesMode
        glassesMode = mode
        wearerDisplay = display
        if mode == .single {
            if display == .meta, g2Enabled { toggleG2() }
            if display == .g2, meta.enabled { meta.disable() }
        }
        hostCursor.resume(); guestCursor.resume()
        if ownerChanged { reset() } else { publishDisplays() }
    }

    /// Displayed name of the other speaker: the recorded demo's Sofía, or a neutral live label.
    var partnerName: String {
        if !liveHistory { return "Sofía" }
        return glassesMode == .single ? "Them" : "Guest"
    }

    private(set) var hostPages: [GlassesScene] = [.empty]
    private(set) var guestPages: [GlassesScene] = [.empty]
    private var hostCursor = DisplayPageCursor()
    private var guestCursor = DisplayPageCursor()
    private var guestProjection = GuestProjection(Conversation())
    private var wearerProjection: WearerProjection?
    private var displayEpoch: UInt64?
    private var viewportTask: Task<Void, Never>?
    private var requestedViewport: ViewportRequest?
    private var viewportGeneration: UInt64 = 0
    private var playback: Task<Void, Never>?
    private let turns: [Turn]
    private var audioRecording: AudioConversationRecording?
    private var audioPlayer: AVAudioPlayer?
    private var audioEventIndex = 0
    private var audioCueIndex = 0
    private(set) var speakingCue: String?

    func saySomethingElse() {
        speakingCue = "Say something else · speak in English or Spanish"
    }
    private var audioElapsed: TimeInterval = 0
    private var audioStartedAt: TimeInterval?
    let recordedAudioMode: Bool
    private let pronunciation: any PronunciationPlaying
    private(set) var pronunciationEnabled = false
    private(set) var pronunciationNotice: String?
    var pronunciationStatus: String { pronunciationNotice ?? pronunciation.status }

    func setPronunciationEnabled(_ enabled: Bool) {
        pronunciationEnabled = enabled
        pronunciationNotice = nil
        if !enabled { pronunciation.stop() }
    }

    func stopPronunciation() {
        pronunciation.stop()
        pronunciationNotice = nil
    }

    private let speech: any TranslationSpeaking
    private(set) var speechNotice: String?
    var speakingTurnID: String? { speech.speakingID }
    var playbackStatus: String? { speechNotice ?? speech.status }

    /// The person a line is for: the guest hears the host's lines, the host the guest's.
    /// The recorded demo is always English–Spanish, independently of the live choice.
    func listenerLanguage(for turn: Turn) -> String {
        let host = liveHistory ? hostLanguage : "en"
        let guest = liveHistory ? guestLanguage : "es"
        return turn.speaker == .alex ? guest : host
    }

    /// A host reading a suggested reply aloud already spoke the listener's
    /// language; replay their own words rather than the back-translation.
    func playbackText(for turn: Turn) -> String {
        turn.sourceLanguage == listenerLanguage(for: turn) ? turn.source : turn.translation
    }

    /// Never automatic. Playback and capture exclude each other: Play is refused
    /// while a capture is connecting, listening or draining, and every capture
    /// start stops playback before the microphone opens, so the phone never
    /// records its own voice as a new utterance.
    func togglePlayback(_ turnID: String) {
        if speech.speakingID == turnID { stopSpeech(); return }
        guard let turn = session.turns.first(where: { $0.id == turnID }) else { return }
        speak(playbackText(for: turn), language: listenerLanguage(for: turn), id: turnID)
    }

    /// A saved line from history speaks its translation in the language it was translated into.
    func toggleSavedPlayback(_ turn: Turn, id: String) {
        if speech.speakingID == id { stopSpeech(); return }
        let language = turn.targetLanguage ?? (turn.speaker == .alex ? "es" : "en")
        speak(turn.translation, language: language, id: id)
    }

    private func speak(_ text: String, language: String, id: String) {
        guard !liveActive, microphone.state != .capturing else {
            speechNotice = "Finish the capture first. Playback never runs while the microphone is on."
            return
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // The demo's recorded voices would talk over the translation.
        if playing { pause() }
        pronunciation.stop()
        speechNotice = nil
        speech.speak(text, language: language, id: id)
    }

    func stopSpeech() {
        speech.stop()
        speechNotice = nil
    }

    /// Single-glasses live: consent covers this conversation's captures until
    /// Stop & clear, Restart, a mode change or backgrounding.
    private(set) var conversationConsent = false


    var experienceLabel: String {
        if liveHistory { return "Live translation" }
        if recordedAudioMode { return "Recorded audio · Meta transcription" }
        return "Fictional rehearsal"
    }

    init(turns: [Turn]? = nil, microphone: (any CaptureSource)? = nil,
         pronunciation: (any PronunciationPlaying)? = nil, speech: (any TranslationSpeaking)? = nil,
         connectionTimeout: Duration = .seconds(12),
         relayFactory: @escaping @MainActor (RelayEndpoint) -> any LiveRelay = {
             RelayClient(endpoint: $0, installID: InstallIdentity.id)
         }) {
        self.connectionTimeout = connectionTimeout
        let arguments = ProcessInfo.processInfo.arguments
        self.recordedAudioMode = turns == nil && !arguments.contains("--fictional-rehearsal")
        self.microphone = microphone ?? Self.defaultCapture()
        self.pronunciation = pronunciation ?? PronunciationPlayer()
        // UI tests and screenshot runs never make a sound.
        let silent = arguments.contains("--silent-audio-capture") || arguments.contains("--silent-speech")
        self.speech = speech ?? (silent ? SilentTranslationSpeaker() : TranslationSpeaker())
        self.relayFactory = relayFactory
        if let turns {
            self.turns = turns
        } else if recordedAudioMode {
            self.turns = []
            do {
                guard let timeline = Bundle.main.url(forResource: "audio-conversation", withExtension: "json"),
                      let audio = Bundle.main.url(forResource: "audio-conversation", withExtension: "wav") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let recording = try JSONDecoder().decode(AudioConversationRecording.self, from: Data(contentsOf: timeline))
                try recording.validate()
                let player = try AVAudioPlayer(contentsOf: audio)
                player.volume = ProcessInfo.processInfo.arguments.contains("--silent-audio-capture") ? 0 : 1
                player.prepareToPlay()
                self.audioRecording = recording
                self.audioPlayer = player
            } catch {
                self.error = "The recorded audio conversation could not be loaded."
            }
        } else {
            struct Fixture: Decodable { let turns: [Turn] }
            do {
                guard let url = Bundle.main.url(forResource: "spanish", withExtension: "json") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                self.turns = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).turns
            } catch {
                self.turns = []
                self.error = "The rehearsal could not be loaded."
            }
        }
    }

    var metaStatus: String {
        switch meta.status {
        case .off: return "Not connected"
        case .registrationRequired: return "Registration required"
        case .waitingForDevice: return "Waiting for glasses"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .stopping: return "Disconnecting"
        case .failed(let message): return message
        }
    }

    var navigationStatus: String {
        switch meta.navigationStatus {
        case .unavailable: return "Band navigation requires the experimental build"
        case .off: return "Band navigation off"
        case .activating: return "Activating band navigation"
        case .active: return "Band navigation active"
        case .failed(let message): return message
        }
    }

    func enableMeta() {
        meta.onAction = { [weak self] action in
            guard let self, let index = self.session.replyIndex(for: action) else { return }
            self.choose(index)
        }
        meta.onNavigation = { [weak self] input in self?.handleNavigation(input) }
        meta.enable()
        publishDisplays()
    }

    var complete: Bool {
        if let audioRecording {
            return audioElapsed >= audioRecording.duration && audioEventIndex == audioRecording.events.count
        }
        return cursor == turns.count && !turns.isEmpty
    }

    func play() {
        stopPronunciation()
        stopSpeech()
        if recordedAudioMode { playRecordedAudio(); return }
        guard !liveActive, !playing, !turns.isEmpty else { return }
        if complete || liveHistory { reset() }
        // Fictional fixture consent never authorizes a microphone or upload.
        session.start(hostConsent: true, guestConsent: true)
        playing = true
        playback = Task { [weak self] in
            while let self, self.playing, !Task.isCancelled, self.cursor < self.turns.count {
                self.advance()
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
            }
            self?.playing = false
        }
    }

    func advance() {
        stopPronunciation()
        guard !recordedAudioMode else { return }
        guard !liveActive, cursor < turns.count else { return }
        if liveHistory { reset() }
        session.start(hostConsent: true, guestConsent: true)
        let turn = turns[cursor]
        if session.receive(turn, epoch: session.epoch, final: true) { cursor += 1 }
    }

    func pause() {
        stopPronunciation()
        if let audioStartedAt {
            audioElapsed += ProcessInfo.processInfo.systemUptime - audioStartedAt
            self.audioStartedAt = nil
        }
        audioPlayer?.pause()
        if liveActive { stopLive() }
        playback?.cancel(); playback = nil; playing = false
        if let relay { Task { await relay.stop() } }
        relay = nil
    }

    private func playRecordedAudio() {
        guard !liveActive, !playing, let recording = audioRecording, let player = audioPlayer else { return }
        if complete || liveHistory { reset() }
        session.start(hostConsent: true, guestConsent: true)
        player.currentTime = min(audioElapsed, player.duration)
        guard player.play() else {
            error = "Recorded audio could not start."
            return
        }
        audioStartedAt = ProcessInfo.processInfo.systemUptime
        playing = true
        // A timestamp for aligning the silent simulator capture with the source WAV.
        print("BORDERLESS_AUDIO_REPLAY_START unix=\(Date().timeIntervalSince1970) offset=\(audioElapsed)")
        playback = Task { [weak self] in
            while let self, self.playing, !Task.isCancelled {
                let elapsed = self.audioElapsed + ProcessInfo.processInfo.systemUptime - (self.audioStartedAt ?? ProcessInfo.processInfo.systemUptime)
                let previousEventIndex = self.audioEventIndex
                while self.audioEventIndex < recording.events.count,
                      recording.events[self.audioEventIndex].at <= elapsed {
                    let event = recording.events[self.audioEventIndex]
                    self.speakingCue = nil
                    guard self.session.receive(event.turn, epoch: self.session.epoch, final: event.final) else {
                        self.error = "Recorded transcript sequence could not be replayed."
                        self.pause()
                        return
                    }
                    if event.final { self.cursor += 1 }
                    self.audioEventIndex += 1
                }
                let cues = recording.cues ?? []
                while self.audioCueIndex < cues.count, cues[self.audioCueIndex].at <= elapsed {
                    let cue = cues[self.audioCueIndex]
                    if cue.kind == "select", self.session.turns.last?.id == cue.turnID, let index = cue.index {
                        self.choose(index)
                        self.speakingCue = "Read your selected reply aloud in Spanish"
                        self.publishDisplays()
                    } else if cue.kind == "freeSpeech" { self.saySomethingElse() }
                    self.audioCueIndex += 1
                }
                if self.audioEventIndex != previousEventIndex { self.publishDisplays() }
                if elapsed >= recording.duration {
                    self.audioElapsed = recording.duration
                    self.audioStartedAt = nil
                    self.playing = false
                    player.stop()
                    return
                }
                do { try await Task.sleep(for: .milliseconds(20)) }
                catch { return }
            }
        }
    }

    /// Development transport only: localhost is the device running this app.
    /// No microphone work happens until the user explicitly presses Start.
    func startLive(localToken: String, participant: RelayAudience, consent: Bool,
                   endpoint: RelayEndpoint = .simulator) {
        guard consent, (32...256).contains(localToken.count), !liveActive else {
            relayStatus = "Both people must consent and a local relay token is required."
            return
        }
        // Before any microphone work: the phone must not hear its own playback.
        stopSpeech()
        pause()
        if !liveHistory { reset() }
        liveHistory = true
        conversationConsent = true
        liveGeneration &+= 1
        let generation = liveGeneration
        let context = RelayContextTurn.recent(session.turns)
        let client = relayFactory(endpoint)
        relay = client
        liveActive = true
        relayStatus = "Requesting microphone permission…"
        liveTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.liveGeneration == generation { self.microphone.stop() }
            }
            do {
                guard await self.microphone.requestPermission() else {
                    throw AudioCaptureError.permissionRequired
                }
                try Task.checkCancellation()
                guard self.liveGeneration == generation else { return }
                self.relayStatus = "Connecting to translation service…"
                try await self.connectLive(client, token: localToken, participant: participant, context: context)
                try Task.checkCancellation()
                guard self.liveGeneration == generation else { return }
                self.session.start(hostConsent: consent, guestConsent: consent)
                let epoch = self.session.epoch
                let frames = try self.microphone.start(maximumSeconds: 60)
                _ = self.session.receive(Turn(id: "capture-\(generation)",
                    speaker: participant == .host ? .alex : .lin, source: "", translation: ""),
                    epoch: epoch, final: false)
                self.publishDisplays()
                self.relayStatus = "Listening to \(participant == .host ? "You · \(LanguageAvailability.name(self.hostLanguage))" : "\(self.partnerName) · \(LanguageAvailability.name(self.guestLanguage))") · 60 seconds maximum"
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try await self.forwardAudio(frames, to: client, generation: generation)
                    }
                    group.addTask {
                        try await self.receiveLive(from: client, generation: generation, epoch: epoch)
                    }
                    do { while try await group.next() != nil {} }
                    catch {
                        group.cancelAll()
                        if self.liveGeneration == generation { self.microphone.stop() }
                        await client.stop()
                        throw error
                    }
                }
                if self.liveGeneration == generation {
                    self.relayStatus = "Capture finished · choose the next speaker to continue"
                }
            } catch {
                if self.liveGeneration == generation, !Task.isCancelled {
                    self.session.stop()
                    self.conversationConsent = false
                    self.publishDisplays()
                    if let audio = error as? AudioCaptureError {
                        self.relayStatus = "Capture stopped: \(audio)."
                    } else {
                        self.relayStatus = Self.liveFailureMessage(error)
                    }
                }
            }
            await client.stop()
            if self.liveGeneration == generation {
                self.liveActive = false
                self.relay = nil
                self.liveTask = nil
            }
        }
    }

    /// A stalled private network must resolve visibly before any microphone starts.
    private func connectLive(_ client: any LiveRelay, token: String, participant: RelayAudience,
                             context: [RelayContextTurn]) async throws {
        var expired = false
        let timeout = Task { @MainActor in
            do { try await Task.sleep(for: connectionTimeout) } catch { return }
            expired = true
            await client.stop()
        }
        defer { timeout.cancel() }
        do {
            try await client.connect(localToken: token, participant: participant, consent: true,
                                     context: context, languagePair: [hostLanguage, guestLanguage])
            let first = try await client.next()
            if case .failed(let refusal?) = first { throw refusal }
            guard case .started = first else { throw RelayFailure.invalidMessage }
            if expired { throw URLError(.timedOut) }
        } catch {
            if expired { throw URLError(.timedOut) }
            throw error
        }
    }

    /// The phone microphone, or in Debug a bundled WAV chosen with `--capture-wav=<name>` (device runs that
    /// must never capture or play sound in the room).
    private static func defaultCapture() -> any CaptureSource {
        #if DEBUG
        if let wav = WAVFileCapture.fromLaunchArguments() { return wav }
        #endif
        return PhoneMicrophone()
    }

    static func liveFailureMessage(_ error: Error) -> String {
        if let refusal = error as? RelayRefusal {
            return "\(refusal.message) The microphone is off."
        }
        if let network = error as? URLError {
            switch network.code {
            case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet:
                return "Cannot reach the translation service. Check this phone's internet connection and try again. The microphone is off."
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate:
                return "The translation service could not establish a secure connection. Check your network connection and try again."
            default: break
            }
        }
        return "Translation stopped. Check your connection and try again."
    }

    private func forwardAudio(_ frames: AsyncThrowingStream<Data, Error>, to client: any LiveRelay,
                              generation: UInt64) async throws {
        for try await frame in frames {
            try Task.checkCancellation()
            guard liveGeneration == generation else { throw CancellationError() }
            try await client.sendPCM(frame)
        }
        try Task.checkCancellation()
        guard liveGeneration == generation else { throw CancellationError() }
        try await client.finishInput()
    }

    private func receiveLive(from client: any LiveRelay, generation: UInt64, epoch: UInt64) async throws {
        var completed = false
        while true {
            let event = try await client.next()
            try Task.checkCancellation()
            guard liveGeneration == generation else { throw CancellationError() }
            switch event {
            case .turn(.host, let turn):
                _ = session.receive(turn, epoch: epoch, final: true)
            case .partial(.host, let turn):
                _ = session.receive(turn, epoch: epoch, final: false)
            case .completed:
                guard session.completeInput(epoch: epoch) else { throw RelayFailure.invalidMessage }
                completed = true
                relayStatus = "Translation complete"
            case .stopped:
                guard completed else { throw RelayFailure.invalidMessage }
                return
            case .failed(let refusal): throw refusal ?? RelayFailure.invalidMessage
            default: break
            }
        }
    }

    /// Finish just this utterance; queued audio drains and translation can finish.
    func finishUtterance() {
        guard liveActive else { return }
        microphone.stop()
        relayStatus = "Finishing translation…"
    }

    /// Revocation: cancel forwarding, close relay, stop hardware and clear display content.
    func stopLive() {
        stopPronunciation()
        stopSpeech()
        conversationConsent = false
        liveGeneration &+= 1
        liveTask?.cancel(); liveTask = nil
        microphone.stop()
        if let relay { Task { await relay.stop() } }
        relay = nil
        liveActive = false
        liveHistory = false
        session.stop()
        relayStatus = "Capture stopped and conversation cleared"
        publishDisplays()
    }

    func testLocalRelay() {
        reset()
        let client = RelayClient()
        relay = client
        relayStatus = "Connecting to synthetic local relay…"
        session.start(hostConsent: true, guestConsent: true)
        playing = true
        playback = Task { [weak self] in
            do {
                try await client.connect(localToken: "borderless-synthetic-benchmark-token-only",
                                         participant: .guest, consent: true)
                guard case .started = try await client.next() else { throw RelayFailure.invalidMessage }
                try await client.sendPCM(Data([0, 0]))
                try await client.finishInput()
                var completed = false
                var stopped = false
                while !stopped {
                    let event = try await client.next()
                    try Task.checkCancellation()
                    guard let self else { break }
                    switch event {
                    case .turn(.host, let turn):
                        _ = self.session.receive(turn, epoch: self.session.epoch, final: true)
                    case .partial(.host, let turn):
                        _ = self.session.receive(turn, epoch: self.session.epoch, final: false)
                    case .completed:
                        guard self.session.completeInput(epoch: self.session.epoch) else {
                            throw RelayFailure.invalidMessage
                        }
                        completed = true
                    case .stopped:
                        guard completed else { throw RelayFailure.invalidMessage }
                        stopped = true
                    case .failed(let refusal): throw refusal ?? RelayFailure.invalidMessage
                    default: break
                    }
                }
                if let self, !Task.isCancelled {
                    self.cursor = self.turns.count
                    self.relayStatus = "Local relay · \(self.session.turns.count) turns received"
                }
            } catch {
                if !Task.isCancelled { self?.relayStatus = "Local fixture relay unavailable. On-device Play still works." }
            }
            await client.stop()
            if !Task.isCancelled { self?.playing = false }
        }
    }
    func enterBackground() {
        // Active capture is cancelled, but completed conversation history survives
        // opening a companion app or locking the phone.
        if liveActive { stopLive() }
        else { pause() }
        stopSpeech()
        conversationConsent = false
        meta.setNavigationEnabled(false)
    }

    func reset() {
        stopSpeech()
        conversationConsent = false
        pause(); session.stop(); cursor = 0; relayStatus = nil; liveHistory = false
        audioElapsed = 0; audioStartedAt = nil; audioEventIndex = 0
        audioCueIndex = 0; speakingCue = nil
        audioPlayer?.currentTime = 0
        publishDisplays()
    }

    func toggleG2() {
        if g2Enabled {
            g2.stop()
            g2Enabled = false
        } else {
            do {
                try g2.start()
                g2Enabled = true
                publishDisplays()
            } catch {
                self.error = "G2 companion could not start. Its local port may be in use."
            }
        }
    }

    func publishDisplays() {
        if displayEpoch != session.epoch {
            hostCursor.resume(); guestCursor.resume()
            displayEpoch = session.epoch
        }
        viewportGeneration &+= 1
        guard session.active else {
            requestedViewport = nil
            hostPages = [.empty]; guestPages = [.empty]
            guestProjection = GuestProjection(session)
            wearerProjection = nil
            sendCurrentPages()
            return
        }
        // The mode travels with the snapshot; a layout begun before a mode
        // change is discarded by the generation check below.
        requestedViewport = ViewportRequest(session: session, mode: glassesMode,
                                            display: wearerDisplay, guestName: partnerName)
        guard viewportTask == nil else { return }
        // One worker, latest pending snapshot only. Text measurement never blocks UI.
        viewportTask = Task { [weak self] in
            guard let self else { return }
            while let request = self.requestedViewport {
                self.requestedViewport = nil
                let generation = self.viewportGeneration
                let layout = await Task.detached(priority: .userInitiated) { request.layout() }.value
                if generation == self.viewportGeneration {
                    self.hostPages = layout.host
                    self.guestProjection = layout.guest
                    self.guestPages = layout.guest.pages
                    self.wearerProjection = layout.wearer
                    self.sendCurrentPages()
                }
            }
            self.viewportTask = nil
        }
    }

    private struct ViewportRequest: Sendable {
        let session: Conversation
        let mode: GlassesMode
        let display: GlassesDisplay
        let guestName: String

        nonisolated func layout() -> (host: [GlassesScene], guest: GuestProjection, wearer: WearerProjection?) {
            let nobody = GuestProjection(Conversation())
            switch (mode, display) {
            case (.dual, _):
                return (ConversationViewport.pages(session, wearer: .alex, guestName: guestName),
                        GuestProjection(session), nil)
            case (.single, .meta):
                return (ConversationViewport.pages(session, wearer: .alex, guestName: guestName), nobody, nil)
            case (.single, .g2):
                let wearer = WearerProjection(session, guestName: guestName)
                return (wearer.pages, nobody, wearer)
            }
        }
    }

    func displayPageIndex(_ wearer: Participant) -> Int {
        if wearer == .alex { return hostCursor.index(count: hostPages.count) }
        return guestCursor.index(count: guestPages.count)
    }

    func waitForDisplayLayout() async { await viewportTask?.value }

    func displayScene(_ wearer: Participant) -> GlassesScene {
        let pages = wearer == .alex ? hostPages : guestPages
        guard !pages.isEmpty else { return .empty }
        return pages[displayPageIndex(wearer)]
    }

    func moveDisplayPage(_ delta: Int, wearer: Participant) {
        let now = ProcessInfo.processInfo.systemUptime
        if wearer == .alex { hostCursor.move(delta, count: hostPages.count, now: now) }
        else { guestCursor.move(delta, count: guestPages.count, now: now) }
        sendCurrentPages()
    }

    func latestDisplayPage(_ wearer: Participant) {
        if wearer == .alex { hostCursor.resume() } else { guestCursor.resume() }
        sendCurrentPages()
    }

    func tickDisplayPages() {
        let now = ProcessInfo.processInfo.systemUptime
        let hostChanged = hostCursor.tick(now: now)
        let guestChanged = guestCursor.tick(now: now)
        if hostChanged || guestChanged { sendCurrentPages() }
    }

    /// Each physical display receives exactly one projection; the pair not worn is blanked.
    private func sendCurrentPages() {
        switch (glassesMode, wearerDisplay) {
        case (.dual, _):
            g2.publish(guestProjection, page: displayPageIndex(.lin))
            meta.submit(MetaRender.scene(for: displayScene(.alex)))
        case (.single, .meta):
            g2.publish(GuestProjection(Conversation()))
            meta.submit(MetaRender.scene(for: displayScene(.alex)))
        case (.single, .g2):
            g2.publish(wearerProjection ?? WearerProjection(Conversation()), page: displayPageIndex(.alex))
            meta.submit(MetaRender.scene(for: .empty))
        }
    }

    /// Up/down chooses private replies; left/right always browses history.
    /// With no replies, up/down also browses history. Back returns to latest.
    func handleNavigation(_ input: MetaNavigation) {
        guard session.active else { return }
        switch input {
        case .up:
            if session.replyToken != nil { move(-1) }
            else { moveDisplayPage(-1, wearer: .alex) }
        case .down:
            if session.replyToken != nil { move(1) }
            else { moveDisplayPage(1, wearer: .alex) }
        case .left: moveDisplayPage(-1, wearer: .alex)
        case .right: moveDisplayPage(1, wearer: .alex)
        case .select: confirm()
        case .back:
            stopPronunciation()
            if let token = session.replyToken { session.dismissSelection(token: token) }
            latestDisplayPage(.alex)
        }
        publishDisplays()
    }

    func move(_ delta: Int) {
        stopPronunciation()
        guard let token = session.replyToken else { return }
        hostCursor.resume()
        session.navigate(delta, token: token)
    }

    func confirm() {
        guard let token = session.replyToken else { return }
        hostCursor.resume()
        guard session.confirm(token: token), pronunciationEnabled else { return }
        guard !liveActive, microphone.state != .capturing else {
            pronunciationNotice = "Finish microphone capture before playing pronunciation."
            pronunciation.stop()
            return
        }
        guard !playing else {
            pronunciationNotice = "Pause the conversation replay before playing pronunciation."
            pronunciation.stop()
            return
        }
        let replies = session.replies(for: .alex)
        guard let selected = session.selected, replies.indices.contains(selected) else { return }
        pronunciationNotice = nil
        if liveHistory && LanguageAvailability.experimental(host: hostLanguage, guest: guestLanguage) {
            pronunciationNotice = "Pronunciation is not yet tested for this language pair."
            return
        }
        speech.stop()
        pronunciation.speak(replies[selected].text, language: liveHistory ? guestLanguage : "es-ES")
    }

    func choose(_ index: Int) {
        guard session.replies(for: .alex).indices.contains(index) else { return }
        while session.focused != index { move(index > session.focused ? 1 : -1) }
        confirm()
    }
}
