import SwiftUI
import BorderlessCore
import BorderlessRelay
import BorderlessDisplay
import GlassesSceneKit

@main
struct BorderlessApp: App {
    var body: some Scene { WindowGroup { ConversationView() } }
}

struct ConversationView: View {
    @State private var model = RehearsalModel()
    @AppStorage("borderless.onboarding.complete") private var onboardingComplete = false
    @State private var showWelcome = false
    @State private var mode: ExperienceMode = .demo
    @AppStorage("borderless.glasses.mode") private var storedGlassesMode = GlassesMode.single.rawValue
    @AppStorage("borderless.glasses.single") private var storedWearerDisplay = GlassesDisplay.meta.rawValue
    @State private var onboardingGlasses = GlassesMode.single
    @State private var pendingChange: PendingChange?
    @State private var confirmModeChange = false
    @State private var confirmSettingsChange = false
    @State private var showSaveError = false
    @State private var showConnectionSetup = false
    @State private var showSettings = false
    @State private var showWelcomeAfterSettings = false
    @State private var showHistory = false
    @State private var savedConversations = SavedConversations()
    @AppStorage("borderless.history.keepLive") private var keepLiveConversations = true
    /// The history entry the running live conversation is kept under; a cleared conversation starts a new one.
    @State private var liveConversationID = UUID()
    @State private var previews = true
    @State private var filter = 0
    @State private var showCapture = false
    @State private var showLanguages = false
    @State private var localToken = DevelopmentServiceConfig.token ?? ""
    @State private var relayAddress = DevelopmentServiceConfig.address ?? "ws://127.0.0.1:8766"
    @State private var captureConsent = false
    @State private var captureSpeaker: RelayAudience = .guest
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image("BorderlessMark").resizable().scaledToFit().frame(width: 30, height: 30).accessibilityHidden(true)
                        Text("borderless").font(.title2.weight(.black)).tracking(-1)
                    }
                    Button { showLanguages = true } label: {
                        HStack(spacing: 4) {
                            Text(mode == .demo ? LanguageAvailability.activePair : LanguageAvailability.pair(host: model.hostLanguage, guest: model.guestLanguage))
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                        }.font(.footnote.weight(.medium)).foregroundStyle(BorderlessTheme.host)
                    }.buttonStyle(.plain).accessibilityLabel("Conversation languages")
                        .disabled(model.liveActive)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button { showHistory = true } label: { headerIcon("clock.arrow.circlepath") }
                        .accessibilityLabel("Conversation history")
                    Button { showSettings = true } label: { headerIcon("gearshape") }
                        .accessibilityLabel("Settings")
                    Button { previews.toggle() } label: { headerIcon("eyeglasses", filled: previews) }
                        .accessibilityLabel("Glasses previews")
                        .accessibilityIdentifier("glasses.previews.toggle")
                        .accessibilityValue(previews ? "On" : "Off")
                        .accessibilityAddTraits(previews ? .isSelected : [])
                }.buttonStyle(.plain)
            }
            VStack(spacing: 4) {
                Picker("Experience", selection: Binding(get: { mode }, set: requestMode)) {
                    Text("Demo").tag(ExperienceMode.demo)
                    Text("Live").tag(ExperienceMode.live)
                }.pickerStyle(.segmented)
                    .disabled(model.liveActive)
                Text(mode == .demo ? "Demo conversation · English ↔ Spanish" : "Live conversation · glasses optional")
                    .font(.caption2).foregroundStyle(BorderlessTheme.muted)
            }

            if previews {
                if model.glassesMode == .dual {
                    HStack(alignment: .top, spacing: 8) {
                        preview(wearer: .alex, display: .meta, title: "You · Meta", color: BorderlessTheme.host)
                        preview(wearer: .lin, display: .g2, title: "\(partnerLabel) · G2", color: BorderlessTheme.guest)
                    }
                } else {
                    singlePreview
                }
                HStack(spacing: 6) {
                    Label("Reply controls", systemImage: "hand.point.up.left").font(.caption).foregroundStyle(BorderlessTheme.muted)
                    Spacer()
                    Button { model.move(-1) } label: { Image(systemName: "chevron.up").frame(width: 18) }.accessibilityLabel("Previous reply")
                    Button { model.move(1) } label: { Image(systemName: "chevron.down").frame(width: 18) }.accessibilityLabel("Next reply")
                    Button("Select") { model.confirm() }.fontWeight(.semibold)
                }
                .buttonStyle(.bordered).controlSize(.small).disabled(model.session.replyToken == nil)
            }
            Picker("Conversation direction", selection: $filter) {
                Text("All").tag(0)
                Text(mode == .demo ? "ES → EN" : "\(partnerLabel) → You").tag(1)
                Text(mode == .demo ? "EN → ES" : "You → \(partnerLabel)").tag(2)
            }.pickerStyle(.segmented)
            FollowHistory(revision: revision + "-\(filter)") {
                if model.session.turns.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("A conversation, without the language barrier.").font(.title3.weight(.semibold))
                        Text(emptyStateHint).font(.subheadline).foregroundStyle(BorderlessTheme.muted)
                    }.padding(18)
                }
                ForEach(filteredTurns, id: \.id) { turn in
                    transcript(turn, wearer: nil, compact: false)
                }
                pendingTranscript(compact: false)
            }
            .accessibilityIdentifier("history.phone")
            .background(.background, in: RoundedRectangle(cornerRadius: BorderlessTheme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: BorderlessTheme.cardRadius).stroke(BorderlessTheme.line.opacity(0.8)))
            if let status = model.relayStatus {
                HStack(spacing: 10) {
                    if model.liveActive { ProgressView().controlSize(.small) }
                    Text(status).font(.callout).accessibilityIdentifier("live.status")
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(BorderlessTheme.host.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
            if let playback = model.playbackStatus {
                Text(playback).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("playback.status")
            }
            if model.pronunciationEnabled {
                HStack {
                    Text(model.pronunciationStatus).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Stop pronunciation") { model.stopPronunciation() }.font(.caption)
                }
            }
            HStack(spacing: 8) {
                if mode == .demo {
                    Button(demoPlayTitle, systemImage: model.playing ? "pause.fill" : "play.fill") {
                        if model.playing { model.pause() } else { model.play() }
                    }
                    .font(.headline).lineLimit(1).fixedSize()
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("rehearsal.play")
                    if !model.recordedAudioMode {
                        Button("Next") { model.pause(); model.advance() }
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.bordered)
                            .disabled(model.complete)
                    }
                    Spacer()
                    Button("Restart demo", systemImage: "arrow.counterclockwise") { model.reset() }
                        .font(.subheadline)
                        .foregroundStyle(BorderlessTheme.muted)
                } else if model.liveActive {
                    Button("Finish utterance") { model.finishUtterance() }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .disabled(model.microphone.state != .capturing)
                    Spacer()
                    Button("Stop & clear", role: .destructive) { model.stopLive() }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                } else {
                    if model.glassesMode == .single {
                        speakerButton(.host, title: "Me", language: model.hostLanguage)
                        speakerButton(.guest, title: "Them", language: model.guestLanguage)
                    } else {
                        Button("Start conversation", systemImage: "mic.fill") { showCapture = true }
                            .font(.headline)
                            .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                    if model.glassesMode == .single {
                        Button("Save", systemImage: "square.and.arrow.down") { saveConversation() }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.bordered)
                            .disabled(model.session.turns.isEmpty)
                    } else {
                        Button("Save", systemImage: "square.and.arrow.down") { saveConversation() }
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.bordered)
                            .disabled(model.session.turns.isEmpty)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(BorderlessTheme.card, in: Capsule())
            .overlay(Capsule().stroke(BorderlessTheme.line.opacity(0.8)))
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
        .background(BorderlessTheme.paper)
        .tint(BorderlessTheme.ink)
        .preferredColorScheme(.light)
        .simultaneousGesture(DragGesture(minimumDistance: 60).onEnded { value in
            if value.translation.width < -80 && abs(value.translation.height) < 50 { showHistory = true }
        })
        .onChange(of: mode) { _, _ in model.reset(); filter = 0 }
        .onChange(of: model.session.turns) { _, turns in keepLiveConversation(turns) }
        .onAppear {
            let arguments = ProcessInfo.processInfo.arguments
            showWelcome = arguments.contains("--show-onboarding") || (!onboardingComplete && !arguments.contains("--silent-audio-capture") && !arguments.contains("--skip-onboarding"))
            // Test and screenshot launches pick a mode without changing the saved choice.
            var glasses = GlassesMode(rawValue: storedGlassesMode) ?? .single
            var display = GlassesDisplay(rawValue: storedWearerDisplay) ?? .meta
            if arguments.contains("--dual-glasses") { glasses = .dual }
            // --single-glasses is the Meta wearer (its G2 twin is --single-g2), whatever an earlier run saved.
            if arguments.contains("--single-glasses") { glasses = .single; display = .meta }
            if arguments.contains("--single-g2") { glasses = .single; display = .g2 }
            onboardingGlasses = glasses
            model.setGlasses(mode: glasses, display: display)
        }
        .alert("Save this conversation before switching?", isPresented: $confirmModeChange) { modeChangeButtons }
        .alert("Conversation not saved", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: { Text(savedConversations.error ?? "Please try again. Your current conversation is still on screen.") }
        .sheet(isPresented: $showWelcome, onDismiss: {
            if pendingChange != nil { confirmModeChange = true }
        }) { welcome }
        .sheet(isPresented: $showSettings, onDismiss: {
            if showWelcomeAfterSettings {
                showWelcomeAfterSettings = false
                onboardingGlasses = model.glassesMode
                showWelcome = true
            }
        }) { settings }
        .sheet(isPresented: $showHistory) { history }
        .onChange(of: revision) { model.publishDisplays() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                model.tickDisplayPages()
            }
        }
        .onOpenURL { url in Task { _ = await model.meta.handle(url: url) } }
        .onDisappear { model.pause() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                model.enterBackground()
                localToken = ""
                captureConsent = false
            }
        }
        .sheet(isPresented: $showLanguages) {
            LanguageAvailabilityView(
                hostLanguage: Binding(get: { model.hostLanguage }, set: { model.setLanguages(host: $0, guest: model.guestLanguage) }),
                guestLanguage: Binding(get: { model.guestLanguage }, set: { model.setLanguages(host: model.hostLanguage, guest: $0) }))
                .disabled(model.liveActive)
        }
        .sheet(isPresented: $showCapture, onDismiss: {
            localToken = ""; captureConsent = false
        }) { captureSettings }
    }


    private enum ExperienceMode: String, CaseIterable { case demo, live }
    /// Both kinds of switch clear the conversation, so both offer save/discard/cancel.
    private enum PendingChange: Equatable {
        case experience(ExperienceMode)
        case glasses(GlassesMode, GlassesDisplay)
    }
    private var demoPlayTitle: String {
        if model.playing { return "Pause demo" }
        if model.complete { return "Replay demo" }
        return "Play demo"
    }
    private var emptyStateHint: String {
        if mode == .demo { return "Press Play demo to follow a conversation. No microphone needed." }
        if model.glassesMode == .single {
            return "Choose your languages. Before each person speaks, tap Me or Them: the phone does not tell voices apart."
        }
        return "Choose your languages, then start a conversation. You can use your phone alone or connect glasses."
    }
    private var partnerLabel: String {
        if mode == .demo { return "Sofía" }
        return model.glassesMode == .single ? "Them" : "Guest"
    }
    private func requestMode(_ requested: ExperienceMode) {
        guard requested != mode else { return }
        pendingChange = .experience(requested)
        if model.session.turns.isEmpty { finishModeChange() }
        else { model.pause(); confirmModeChange = true }
    }
    /// Only a change of who wears G2 clears the conversation; switching the
    /// single wearer's display applies at once.
    private func requestGlasses(_ glasses: GlassesMode, _ display: GlassesDisplay, fromSettings: Bool = false) {
        guard glasses != model.glassesMode || display != model.wearerDisplay else { return }
        pendingChange = .glasses(glasses, display)
        if glasses == model.glassesMode || model.session.turns.isEmpty { finishModeChange() }
        else if fromSettings { model.pause(); confirmSettingsChange = true }
        else { model.pause(); confirmModeChange = true }
    }
    private func finishModeChange() {
        guard let pendingChange else { return }
        switch pendingChange {
        case .experience(let requested):
            mode = requested
        case .glasses(let glasses, let display):
            storedGlassesMode = glasses.rawValue
            storedWearerDisplay = display.rawValue
            model.setGlasses(mode: glasses, display: display)
        }
        self.pendingChange = nil
    }
    @ViewBuilder private var modeChangeButtons: some View {
        Button("Save & switch") {
            if savedConversations.save(turns: model.session.turns, demo: mode == .demo, languages: conversationLanguages) {
                finishModeChange()
            }
            else { showSaveError = true }
        }
        Button("Discard & switch", role: .destructive) { finishModeChange() }
        Button("Cancel", role: .cancel) { pendingChange = nil }
    }
    private func startCapture(_ speaker: RelayAudience) {
        if model.conversationConsent, connectionReady, let endpoint = try? RelayEndpoint(validating: relayAddress) {
            model.startLive(localToken: captureToken, participant: speaker, consent: true, endpoint: endpoint)
        } else {
            captureSpeaker = speaker
            showCapture = true
        }
    }
    /// Explicit attribution: the phone cannot tell voices apart, so the person
    /// about to speak taps their own button.
    private func speakerButton(_ speaker: RelayAudience, title: String, language: String) -> some View {
        Button { startCapture(speaker) } label: {
            VStack(spacing: 1) {
                Label(title, systemImage: "mic.fill").font(.headline)
                Text(LanguageAvailability.name(language)).font(.caption2)
            }
            .frame(minWidth: 76)
        }
        .buttonStyle(.borderedProminent)
        .tint(speaker == .host ? BorderlessTheme.host : BorderlessTheme.guest)
        .accessibilityIdentifier(speaker == .host ? "capture.me" : "capture.them")
    }
    private var singlePreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Your glasses", selection: Binding(get: { model.wearerDisplay }, set: { requestGlasses(.single, $0) })) {
                Text("Meta Display").tag(GlassesDisplay.meta)
                Text("Even G2").tag(GlassesDisplay.g2)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .accessibilityIdentifier("single.display")
            .disabled(model.liveActive)
            preview(wearer: .alex, display: model.wearerDisplay,
                    title: model.wearerDisplay == .meta ? "You · Meta" : "You · G2", color: BorderlessTheme.host)
        }
    }
    private func headerIcon(_ systemImage: String, filled: Bool = false) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(filled ? BorderlessTheme.paper : BorderlessTheme.ink)
            .frame(width: 36, height: 36)
            .background(filled ? BorderlessTheme.ink : BorderlessTheme.card, in: Circle())
            .overlay(Circle().stroke(BorderlessTheme.line.opacity(filled ? 0 : 0.8)))
            .contentShape(Circle())
    }
    private var conversationLanguages: [String] { [model.hostLanguage, model.guestLanguage] }
    private func saveConversation() {
        if !savedConversations.save(turns: model.session.turns, demo: mode == .demo, languages: conversationLanguages) {
            showSaveError = true
        }
    }
    /// Live conversations are kept as each line finishes (Settings → Keep live conversations).
    private func keepLiveConversation(_ turns: [Turn]) {
        if turns.isEmpty { liveConversationID = UUID(); return }
        guard mode == .live, keepLiveConversations else { return }
        savedConversations.keep(liveConversation: liveConversationID, turns: turns, languages: conversationLanguages)
    }
    private var welcome: some View {
        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image("BorderlessMark").resizable().scaledToFit().frame(width: 56, height: 56)
                Text("Understand each other.").font(.largeTitle.weight(.black)).tracking(-0.5)
                VStack(alignment: .leading, spacing: 10) {
                    welcomePoint("See what was said in both languages.", systemImage: "bubble.left.and.bubble.right")
                    welcomePoint("Choose a reply, or speak naturally.", systemImage: "text.bubble")
                    welcomePoint("Use Borderless on your phone, with or without glasses.", systemImage: "iphone")
                }
                Text("Who wears glasses?").font(.headline).padding(.top, 8)
                glassesChoice(.single, title: "One pair · you",
                              detail: "You wear Ray-Ban Meta Display or Even G2 and read everyone in your language. Others just talk near your phone; tap Play on any line to say it out loud in theirs.",
                              systemImage: "eyeglasses")
                glassesChoice(.dual, title: "Two pairs · you and your guest",
                              detail: "Pair one Ray-Ban Meta Display and one Even G2 with this phone. Your private reply choices stay on the Meta display; your guest sees the conversation on G2.",
                              systemImage: "person.2")
                Text("Demo plays a recorded conversation. Live uses your microphone only after you start and agree. Conversations stay on screen unless you choose Save; saved text stays on this phone until you delete it.")
                    .font(.footnote).foregroundStyle(BorderlessTheme.muted)
            }.padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 12)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    Button { finishWelcome(.demo) } label: {
                        Text("Try the demo").font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button { finishWelcome(.live) } label: {
                        Text("Start a live conversation").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                    }
                }
                .controlSize(.large)
                .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 4)
                .background(BorderlessTheme.paper)
            }
            .background(BorderlessTheme.paper)
            .tint(BorderlessTheme.ink)
        }.interactiveDismissDisabled()
    }
    private func welcomePoint(_ text: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage).foregroundStyle(BorderlessTheme.host).frame(width: 24)
            Text(text)
        }.font(.callout)
    }
    private func finishWelcome(_ experience: ExperienceMode) {
        // Changing Demo/Live clears the conversation anyway; otherwise a
        // conversation on screen gets save/discard/cancel once the sheet closes.
        let clearing = experience != mode || model.session.turns.isEmpty
        mode = experience
        onboardingComplete = true
        if onboardingGlasses != model.glassesMode {
            pendingChange = .glasses(onboardingGlasses, model.wearerDisplay)
            if clearing { finishModeChange() } else { model.pause() }
        }
        showWelcome = false
    }
    private func glassesChoice(_ glasses: GlassesMode, title: String, detail: String, systemImage: String) -> some View {
        let chosen = onboardingGlasses == glasses
        return Button { onboardingGlasses = glasses } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage).font(.title3).foregroundStyle(BorderlessTheme.host).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.footnote).foregroundStyle(BorderlessTheme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(chosen ? BorderlessTheme.host : BorderlessTheme.line)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(chosen ? 0.95 : 0.5), in: RoundedRectangle(cornerRadius: BorderlessTheme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: BorderlessTheme.cardRadius)
                .stroke(chosen ? BorderlessTheme.host : BorderlessTheme.line, lineWidth: chosen ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.glasses.\(glasses.rawValue)")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
    private var settings: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Who wears glasses", selection: Binding(get: { model.glassesMode },
                                                                   set: { requestGlasses($0, model.wearerDisplay, fromSettings: true) })) {
                        Text("One pair").tag(GlassesMode.single)
                        Text("Two pairs").tag(GlassesMode.dual)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.glasses.mode")
                    if model.glassesMode == .single {
                        Picker(selection: Binding(get: { model.wearerDisplay },
                                                  set: { requestGlasses(.single, $0, fromSettings: true) })) {
                            Text("Meta Display").tag(GlassesDisplay.meta)
                            Text("Even G2").tag(GlassesDisplay.g2)
                        } label: { Label("Your glasses", systemImage: "eyeglasses") }
                    }
                } header: { Text("Glasses") } footer: {
                    Text(model.glassesMode == .single
                         ? "You wear the glasses and read everyone in your language. Others talk near your phone; Play reads any line aloud in the listener's language."
                         : "You wear Ray-Ban Meta Display with private reply ideas; your guest wears Even G2.")
                }
                .disabled(model.liveActive)
                Section {
                    Toggle(isOn: $previews) { Label("Show glasses previews", systemImage: "rectangle.on.rectangle") }
                    Toggle(isOn: Binding(get: { model.pronunciationEnabled }, set: { model.setPronunciationEnabled($0) })) {
                        Label("Hear selected reply privately", systemImage: "ear")
                    }
                    if model.pronunciationEnabled {
                        Button("Stop pronunciation", systemImage: "stop.circle") { model.stopPronunciation() }
                    }
                } header: { Text("Your experience") } footer: {
                    Text("Pronunciation plays only through personal audio after recording stops.")
                }
                Section {
                    Toggle(isOn: $keepLiveConversations) {
                        Label("Keep live conversations", systemImage: "clock.arrow.circlepath")
                    }
                    .accessibilityIdentifier("settings.keepLive")
                } header: { Text("History") } footer: {
                    Text("Live conversations are kept on this phone as they happen: text only, protected, never backed up. Delete any of them from History.")
                }
                Section {
                    Toggle(isOn: bandNavigation) { Label("Band navigation", systemImage: "hand.point.up.left") }
                        .disabled(model.meta.navigationStatus == .unavailable)
                } header: { Text("Glasses controls") } footer: { Text(model.navigationStatus) }
                Section {
                    Button("Show introduction", systemImage: "sparkles") { showWelcomeAfterSettings = true; showSettings = false }
                } header: { Text("About") } footer: {
                    Text("Demo uses generated voices and previously recorded Meta transcriptions and translations. It does not record you or make new API requests.")
                }
                #if DEBUG
                Section {
                    DisclosureGroup {
                        Button("Test local fixture relay") { model.testLocalRelay(); showSettings = false }
                    } label: { Label("Developer diagnostics", systemImage: "wrench.and.screwdriver") }
                }
                #endif
            }
            .borderlessSheet()
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } } }
            .alert("Save this conversation before switching?", isPresented: $confirmSettingsChange) { modeChangeButtons }
        }
    }
    /// One switch over the band: on while active or activating; the footer carries the status.
    private var bandNavigation: Binding<Bool> {
        Binding(get: { model.meta.navigationStatus == .active || model.meta.navigationStatus == .activating },
                set: { model.meta.setNavigationEnabled($0) })
    }
    private var history: some View {
        NavigationStack {
            List {
                Section {
                    if model.session.turns.isEmpty { Text("Your conversation will appear here.").foregroundStyle(BorderlessTheme.muted) }
                    else {
                        NavigationLink {
                            historyDetail(turns: model.session.turns, title: "Current conversation", playIDs: "current")
                        } label: {
                            Label("View current conversation (\(model.session.turns.count) lines)", systemImage: "text.bubble")
                        }
                        if mode == .demo || !keepLiveConversations {
                            Button("Save conversation on this phone", systemImage: "square.and.arrow.down") { saveConversation() }
                        } else {
                            Label("Kept on this phone as it happens", systemImage: "checkmark.circle")
                                .foregroundStyle(BorderlessTheme.muted)
                        }
                    }
                } header: { Text("This conversation") }
                Section {
                    if savedConversations.items.isEmpty { Text("Nothing saved yet.").foregroundStyle(BorderlessTheme.muted) }
                    ForEach(savedConversations.items) { item in
                        NavigationLink {
                            historyDetail(turns: item.turns, title: item.demo ? "Demo conversation" : "Live conversation",
                                          playIDs: "saved.\(item.id.uuidString)")
                        } label: { savedRow(item) }
                        .accessibilityIdentifier("history.saved.\(item.demo ? "demo" : "live")")
                    }.onDelete { savedConversations.delete(at: $0) }
                } header: { Text("Saved on this phone") } footer: {
                    Text(keepLiveConversations
                         ? "Live conversations are kept as they happen; save a demo here. Swipe to delete."
                         : "Only conversations you save are kept. Swipe a saved conversation to delete it.")
                }
                if let error = savedConversations.error { Section { Text(error).foregroundStyle(.red) } }
            }
            .borderlessSheet()
            .navigationTitle("Conversation history")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showHistory = false } } }
        }
    }
    private func savedRow(_ item: SavedConversations.Entry) -> some View {
        let pair = (item.languages ?? ["en", "es"]).map(LanguageAvailability.name).joined(separator: " ↔ ")
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: item.demo ? "play.circle" : "mic.circle")
                .foregroundStyle(BorderlessTheme.host).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.demo ? "Demo conversation" : "Live conversation").font(.body.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(item.date, format: .dateTime.month().day().hour().minute())
                        .font(.caption).foregroundStyle(BorderlessTheme.muted)
                }
                Text("\(pair) · \(item.turns.count) \(item.turns.count == 1 ? "line" : "lines")")
                    .font(.caption).foregroundStyle(BorderlessTheme.muted)
                Text(item.turns.first?.translation ?? "").font(.subheadline).lineLimit(1)
            }
        }
    }
    /// A kept conversation reads like the live one: who spoke, in which direction, and Play in the
    /// listener's language.
    private func historyDetail(turns: [Turn], title: String, playIDs: String) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(turns, id: \.id) { turn in
                    let playID = "\(playIDs).\(turn.id)"
                    let speaking = model.speakingTurnID == playID
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(turn.speaker == .alex ? "You" : "Guest") · \(turn.direction)").font(.caption.bold())
                            .foregroundStyle(turn.speaker == .alex ? BorderlessTheme.host : BorderlessTheme.guest)
                        Text(turn.source).foregroundStyle(BorderlessTheme.muted)
                        Text(turn.translation)
                        if !turn.translation.isEmpty {
                            Button { model.toggleSavedPlayback(turn, id: playID) } label: {
                                Label(speaking ? "Stop" : "Play in \(LanguageAvailability.name(turn.targetLanguage ?? (turn.speaker == .alex ? "es" : "en")))",
                                      systemImage: speaking ? "stop.fill" : "speaker.wave.2.fill")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(turn.speaker == .alex ? BorderlessTheme.guest : BorderlessTheme.host)
                            .disabled(model.liveActive)
                            .accessibilityIdentifier("history.play.\(turn.id)")
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: BorderlessTheme.cardRadius))
                }
            }.padding()
        }
        .background(BorderlessTheme.paper)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // A provisioned development credential remains available across sheet dismissals
    // and backgrounding. Manually entered credentials still clear on dismissal.
    private var captureToken: String {
        localToken.isEmpty ? (DevelopmentServiceConfig.token ?? "") : localToken
    }
    private var provisionedConnection: Bool {
        guard let address = DevelopmentServiceConfig.address, let token = DevelopmentServiceConfig.token else { return false }
        return (try? RelayEndpoint(validating: address)) != nil && (32...256).contains(token.count)
    }
    private var connectionReady: Bool {
        (try? RelayEndpoint(validating: relayAddress)) != nil && (32...256).contains(captureToken.count)
    }
    private var connectionIssue: String {
        if (try? RelayEndpoint(validating: relayAddress)) == nil { return "Enter a valid translation service address in connection setup." }
        return "Add the service access token in connection setup to enable live translation."
    }
    private var captureSettings: some View {
        let single = model.glassesMode == .single
        return NavigationStack {
            Form {
                if !connectionReady {
                    Section {
                        Label("Translation service setup needed", systemImage: "network")
                        Button("Set up translation service") { showConnectionSetup = true }
                    } footer: {
                        Text("Live translation needs a Borderless service address and access token. Set these up below before starting; your microphone stays off.")
                    }
                }
                if !provisionedConnection {
                    Section {
                        DisclosureGroup("Advanced connection setup", isExpanded: $showConnectionSetup) {
                            Text("Connect to your Borderless translation service. Your phone needs a secure service address and access token before live translation can start.")
                                .font(.footnote)
                            TextField("Relay address", text: $relayAddress)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .keyboardType(.URL)
                            SecureField("Service access token", text: $localToken)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                            Text("Use the relay's local authentication token. Provider keys remain on the relay. The token is kept only in this sheet's memory and cleared when it closes.")
                                .font(.caption).foregroundStyle(BorderlessTheme.muted)
                        }
                    }
                }
                Section {
                    Picker(selection: $captureSpeaker) {
                        Text("\(single ? "Them" : "Guest") · \(LanguageAvailability.name(model.guestLanguage))").tag(RelayAudience.guest)
                        Text("\(single ? "Me" : "You") · \(LanguageAvailability.name(model.hostLanguage))").tag(RelayAudience.host)
                    } label: { Label("Speaker", systemImage: "person.wave.2") }
                    Toggle(single ? "Everyone speaking agrees to sending this conversation's captures to Meta for translation"
                                  : "Both people agree to sending this capture to Meta for translation", isOn: $captureConsent)
                        .font(.subheadline)
                } header: { Text("One utterance") } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Uses the phone microphone for at most 60 seconds. Finish utterance sends the remaining audio; Stop & clear cancels forwarding and clears the conversation. No audio file is saved.")
                        if single {
                            Text("After this capture, Me and Them start the next one directly until you Stop & clear. Translation playback is off while the microphone is on.")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if !connectionReady {
                        Text(connectionIssue).font(.caption).foregroundStyle(BorderlessTheme.muted)
                    } else if !captureConsent {
                        Text("Confirm that both people agree before starting.").font(.caption).foregroundStyle(BorderlessTheme.muted)
                    }
                    Button {
                        guard let endpoint = try? RelayEndpoint(validating: relayAddress) else { return }
                        model.startLive(localToken: captureToken, participant: captureSpeaker, consent: captureConsent, endpoint: endpoint)
                        showCapture = false
                    } label: {
                        Label("Start live capture", systemImage: "mic.fill").font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .tint(BorderlessTheme.ink)
                    .disabled(!captureConsent || !connectionReady || model.liveActive)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 4)
                .background(BorderlessTheme.paper)
            }
            .borderlessSheet()
            .navigationTitle("Live capture")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showCapture = false } } }
        }
    }

    private var revision: String {
        "\(model.session.epoch)-\(model.session.actionRevision)-\(model.session.turns.count)-\(model.session.focused)-\(model.session.selected ?? -1)"
    }
    private var filteredTurns: [Turn] {
        model.session.turns.filter { filter == 0 || ($0.speaker == .lin ? filter == 1 : filter == 2) }
    }

    @ViewBuilder private func pendingTranscript(compact: Bool) -> some View {
        if let pending = model.session.pending {
            VStack(alignment: .leading, spacing: 5) {
                Text(pending.speaker == .alex ? "You · speaking" : "\(partnerLabel) · speaking")
                    .font(.caption2).foregroundStyle(pending.speaker == .alex ? BorderlessTheme.host : BorderlessTheme.guest)
                Text(pending.source.isEmpty ? "Listening…" : pending.source)
                    .font(compact ? .caption : .body)
                if !pending.source.isEmpty {
                    Text("Listening · translation follows")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(compact ? 12 : 16)
        }
    }

    private func connectionLabel(_ display: GlassesDisplay) -> String {
        if display == .meta { return model.metaStatus }
        if model.g2Enabled { return "Waiting for Even Hub" }
        return "Not connected"
    }

    /// The connect button sits beside the title and live status so the lens,
    /// not the controls, leads each card. A half-width card drops the display name.
    @ViewBuilder private func connectButton(_ display: GlassesDisplay) -> some View {
        if display == .meta {
            let title = model.meta.enabled ? "Disconnect" : "Connect"
            Button {
                if model.meta.enabled { model.meta.disable() }
                else { model.enableMeta() }
            } label: { ViewThatFits { Text("\(title) Meta"); Text(title) } }
            .accessibilityLabel("\(title) Meta")
            .accessibilityIdentifier("connect.meta")
        } else {
            let title = model.g2Enabled ? "Disconnect" : "Connect"
            Button { model.toggleG2() } label: { ViewThatFits { Text("\(title) G2"); Text(title) } }
                .accessibilityLabel("\(title) G2")
                .accessibilityIdentifier("connect.g2")
        }
    }

    /// `wearer` is whose view is shown; `display` is the pair it is fitted to.
    private func preview(wearer: Participant, display: GlassesDisplay, title: String, color: Color) -> some View {
        let scene = model.displayScene(wearer)
        let titleRow = HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.caption.bold()).lineLimit(1)
        }
        let status = Text(connectionLabel(display)).font(.caption2).foregroundStyle(BorderlessTheme.muted).lineLimit(2)
        let connect = connectButton(display)
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered).controlSize(.mini)
            .tint(color)
        return VStack(alignment: .leading, spacing: 8) {
            // Half-width cards (two pairs) give the button the status row, so both cards keep one layout.
            if model.glassesMode == .dual {
                VStack(alignment: .leading, spacing: 4) {
                    titleRow
                    HStack(spacing: 4) { status; Spacer(minLength: 4); connect }
                }
            } else {
                HStack(alignment: .center, spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) { titleRow; status }
                    Spacer(minLength: 4)
                    connect
                }
            }
            if display == .meta, model.meta.status == .registrationRequired {
                Button("Register with Meta AI") { model.meta.register() }
                    .font(.caption.weight(.semibold))
            }
            if display == .g2, model.g2Enabled {
                Text("Open Borderless in Even Hub, then return here.")
                    .font(.caption2).foregroundStyle(BorderlessTheme.muted)
            }
            RenderedLens(scene: scene, display: display)
                .frame(height: Self.lensFrameHeight)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(display == .meta ? "Simulated Meta screen" : "Simulated G2 screen")
                .accessibilityValue((["\(scene.cards.count) reply options"] + scene.lines.map(\.text) + scene.cards.flatMap { [$0.title, $0.detail] }).joined(separator: "\n"))
                .accessibilityIdentifier(display == .meta ? "preview.meta.screen" : "preview.g2.screen")
            FollowHistory(revision: revision) {
                if model.session.turns.isEmpty {
                    Text(wearer == .alex ? "Your translations and private reply ideas" : "Tus traducciones")
                        .font(.caption).padding(12)
                }
                ForEach(model.session.turns, id: \.id) { turn in
                    transcript(turn, wearer: wearer, compact: true)
                }
                pendingTranscript(compact: true)
            }
            .accessibilityIdentifier(display == .meta ? "history.meta" : "history.g2")
            .frame(height: 64)
            .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            DisclosureGroup {
                HStack {
                    Button { model.moveDisplayPage(-1, wearer: wearer) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel(display == .meta ? "Meta previous page" : "G2 previous page")
                    Spacer()
                    Text("\(model.displayPageIndex(wearer) + 1)/\(max(1, wearer == .alex ? model.hostPages.count : model.guestPages.count))")
                        .monospacedDigit()
                    Spacer()
                    Button { model.moveDisplayPage(1, wearer: wearer) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel(display == .meta ? "Meta next page" : "G2 next page")
                }.buttonStyle(.bordered).controlSize(.small)
                Button("Latest display page") { model.latestDisplayPage(wearer) }
            } label: {
                Text("Display render").foregroundStyle(BorderlessTheme.muted)
            }
            .font(.caption2.weight(.medium))
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(BorderlessTheme.card, in: RoundedRectangle(cornerRadius: BorderlessTheme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: BorderlessTheme.cardRadius).stroke(BorderlessTheme.line.opacity(0.8)))
    }
    /// Meta and G2 share one frame size so the pair reads alike; each lens sits
    /// inside at its own shape (square panel, wide strip).
    private static let lensFrameHeight: CGFloat = 126

    private func transcript(_ turn: Turn, wearer: Participant?, compact: Bool) -> some View {
        let color: Color = turn.speaker == .alex ? BorderlessTheme.host : BorderlessTheme.guest
        return VStack(alignment: .leading, spacing: compact ? 5 : 10) {
            Text("\(turn.speaker == .alex ? "You" : partnerLabel) · \(turn.direction)")
                .font(compact ? .system(size: 9, weight: .semibold) : .caption.weight(.semibold))
                .foregroundStyle(color)
            Text(turn.source).foregroundStyle(.secondary)
            Text(turn.translation).foregroundStyle(.primary)
            if !compact, !turn.translation.isEmpty { playButton(turn) }
            if wearer != .lin, turn.id == model.session.turns.last?.id,
               model.session.replyToken != nil {
                replies(compact: compact)
            }
            Divider().padding(.top, 8)
        }
        .font(compact ? .caption : .body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 10 : 18)
    }

    /// Tinted with the listener's colour: the host's lines play for the guest, and back.
    private func playButton(_ turn: Turn) -> some View {
        let speaking = model.speakingTurnID == turn.id
        let language = LanguageAvailability.name(model.listenerLanguage(for: turn))
        return Button { model.togglePlayback(turn.id) } label: {
            Label(speaking ? "Stop" : "Play in \(language)",
                  systemImage: speaking ? "stop.fill" : "speaker.wave.2.fill")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(turn.speaker == .alex ? BorderlessTheme.guest : BorderlessTheme.host)
        .disabled(model.liveActive)
        .accessibilityIdentifier("play.\(turn.id)")
    }

    private func replies(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your reply ideas").font(.caption2).foregroundStyle(BorderlessTheme.host)
            ForEach(Array(model.session.replies(for: .alex).enumerated()), id: \.offset) { index, reply in
                Button { model.choose(index) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top) {
                            Text(reply.text).fontWeight(.medium)
                            Spacer(minLength: 0)
                            if model.session.selected == index { Image(systemName: "checkmark.circle.fill") }
                        }
                        Text(reply.gloss).foregroundStyle(.secondary)
                    }
                    .font(compact ? .system(size: 11) : .subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                    .background(BorderlessTheme.host.opacity(model.session.focused == index ? 0.12 : 0.04),
                                in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(
                        BorderlessTheme.host.opacity(model.session.focused == index ? 0.6 : 0.1)))
                }.buttonStyle(.plain)
            }
            if model.session.selected != nil {
                Text("Say this reply when you’re ready")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct RenderedLens: View {
    let scene: GlassesScene
    let display: GlassesDisplay
    private var image: CGImage? {
        if display == .meta { return MetaRender.image(for: scene) }
        return G2Render.image(for: scene)
    }
    private let panel = RoundedRectangle(cornerRadius: 6)
    /// The shared frame is the wearer's view; the outlined panel is the lens's real shape.
    var body: some View {
        panel.fill(.black)
            .overlay { if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() } }
            .clipShape(panel)
            .overlay(panel.strokeBorder(.white.opacity(0.16)))
            .aspectRatio(display == .meta ? 1 : 2, contentMode: .fit)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BorderlessTheme.ink, in: RoundedRectangle(cornerRadius: 10))
    }
}


/// Saved conversation text only, on this phone: protected and excluded from backup. Provider credentials
/// and audio never enter history. Live conversations are kept as they happen when the Settings switch is
/// on; anything else is kept only when saved.
@MainActor @Observable
final class SavedConversations {
    struct Entry: Identifiable, Codable {
        let id: UUID
        var date: Date
        let demo: Bool
        var turns: [Turn]
        /// Host then guest; nil in files written before 2026-11-04.
        var languages: [String]?
    }
    private(set) var items: [Entry] = []
    private(set) var error: String?
    private let url: URL?
    private var loadFailed = false

    convenience init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        self.init(url: directory?.appendingPathComponent("BorderlessHistory.json"))
    }

    init(url: URL?) {
        self.url = url
        if let url, FileManager.default.fileExists(atPath: url.path) {
            do { items = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url)) }
            catch { loadFailed = true; self.error = "Saved conversations could not be opened. Your saved file has not been changed." }
        }
    }

    /// Only finished lines are kept; a line still being heard has no translation yet.
    static func finished(_ turns: [Turn]) -> [Turn] { turns.filter { !$0.translation.isEmpty } }

    @discardableResult func save(turns: [Turn], demo: Bool, languages: [String]? = nil) -> Bool {
        let turns = Self.finished(turns)
        guard !turns.isEmpty, !loadFailed else { return false }
        guard !items.contains(where: { $0.turns == turns }) else { return true }
        let updated = [Entry(id: UUID(), date: Date(), demo: demo, turns: turns, languages: languages)] + items
        return persist(updated)
    }

    /// Keeps the running live conversation under one entry, updated as each line finishes.
    @discardableResult func keep(liveConversation id: UUID, turns: [Turn], languages: [String]) -> Bool {
        let turns = Self.finished(turns)
        guard !turns.isEmpty, !loadFailed else { return false }
        var updated = items.filter { $0.id != id }
        if let existing = items.first(where: { $0.id == id }), existing.turns == turns { return true }
        updated.insert(Entry(id: id, date: Date(), demo: false, turns: turns, languages: languages), at: 0)
        return persist(updated)
    }
    func delete(at offsets: IndexSet) {
        guard !loadFailed else { return }
        var updated = items
        updated.remove(atOffsets: offsets)
        persist(updated)
    }
    @discardableResult private func persist(_ updated: [Entry]) -> Bool {
        guard !loadFailed else { return false }
        guard let url else { error = "This phone could not open local storage."; return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: url, options: [.atomic, .completeFileProtection])
            var resourceURL = url
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try resourceURL.setResourceValues(values)
            items = updated; error = nil
            return true
        } catch { self.error = "Could not save this change. Please try again. Your current conversation has not been cleared."; return false }
    }
}
