import XCTest

final class RehearsalUITests: XCTestCase {
    /// Explicitly selected attended physical test; never included in ordinary CI.
    @MainActor func testAttendedPhoneOnlyLiveCapture() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BORDERLESS_ATTENDED_DEVICE"] == "1")
        let app = XCUIApplication()
        app.launchArguments = ["--skip-onboarding", "--dual-glasses"]
        app.launch()
        XCTAssertTrue(app.buttons["Live"].waitForExistence(timeout: 10))
        app.buttons["Live"].tap()
        app.descendants(matching: .any)["glasses.previews.toggle"].firstMatch.tap()
        app.buttons["Start conversation"].tap()
        let consent = app.switches["Both people agree to sending this capture to Meta for translation"]
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Start live capture"].isEnabled)
        app.buttons["Start live capture"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 2) {
            let allow = springboard.alerts.buttons["Allow"]
            if allow.exists { allow.tap() }
        }
        let listening = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Listening to'")).firstMatch
        let reached = listening.waitForExistence(timeout: 20)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Physical phone-only live start"
        capture.lifetime = .keepAlways
        add(capture)
        print("LIVE_UI " + app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | "))
        if app.buttons["Stop & clear"].exists { app.buttons["Stop & clear"].tap() }
        XCTAssertTrue(reached, "Phone-only capture must reach Listening without glasses")
    }

    @MainActor func testPronunciationSettingDefaultsOff() {
        let app = XCUIApplication()
        app.launchArguments = ["--silent-audio-capture", "--dual-glasses"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Demo conversation · English ↔ Spanish"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        let option = app.descendants(matching: .any)["Hear selected reply privately"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Playing Spanish pronunciation through your personal audio output."].exists)
    }

    @MainActor func testRecordedAudioConversation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--audio-conversation", "--silent-audio-capture", "--dual-glasses"]
        if app.launchArguments.isEmpty { app.launchArguments = ["--fictional-rehearsal", "--silent-audio-capture", "--dual-glasses"] }
        app.launch()
        let play = app.buttons["rehearsal.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Demo conversation · English ↔ Spanish"].exists)
        print("BORDERLESS_AUDIO_TEST_PLAY_TAP unix=\(Date().timeIntervalSince1970)")
        play.tap()
        // A headless simulator has no window compositor. Sampling screenshots
        // keeps its recorded display current while exercising the actual UI.
        var sawCompleteQuestion = false
        let deadline = Date().addingTimeInterval(180)
        while play.label != "Replay demo" && Date() < deadline {
            let host = app.otherElements["preview.meta.screen"].value as? String ?? ""
            if host.contains("2 reply options") && host.contains("Madrid") {
                sawCompleteQuestion = true
            }
            _ = app.screenshot()
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertEqual(play.label, "Replay demo")
        XCTAssertTrue(sawCompleteQuestion, "Meta must retain the question and both complete answers")
        XCTAssertFalse(app.staticTexts["Recorded transcript sequence could not be replayed."].exists)
        XCTAssertFalse(app.scrollViews["history.g2"].staticTexts["Your reply ideas"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Actual audio transcription replay - generated voices, Meta results"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor func testLocalRelayConversationAndPrivateSelection() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BORDERLESS_TEST_RELAY"] == "1",
                          "Requires the explicitly started synthetic loopback relay")
        let app = XCUIApplication()
        if app.launchArguments.isEmpty { app.launchArguments = ["--fictional-rehearsal", "--silent-audio-capture", "--dual-glasses"] }
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        app.buttons["Developer diagnostics"].tap()
        app.buttons["Test local fixture relay"].tap()
        XCTAssertTrue(app.staticTexts["Local relay · 5 turns received"].waitForExistence(timeout: 10))
        let phone = app.scrollViews["history.phone"]
        let guest = app.scrollViews["history.g2"]
        XCTAssertTrue(phone.staticTexts["Perfect, let's go."].exists)
        XCTAssertFalse(guest.staticTexts["Your reply ideas"].exists)
        app.buttons["Next reply"].tap()
        app.buttons["Select"].tap()
        let cue = "Say this reply when you’re ready"
        XCTAssertTrue(phone.staticTexts[cue].exists)
        XCTAssertFalse(guest.staticTexts[cue].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Native loopback relay conversation - synthetic"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor func testFullOneClickRehearsal() {
        let app = XCUIApplication()
        if app.launchArguments.isEmpty { app.launchArguments = ["--fictional-rehearsal", "--silent-audio-capture", "--dual-glasses"] }
        app.launch()
        let play = app.buttons["rehearsal.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        XCTAssertTrue(app.staticTexts["Hello, how are you?"].firstMatch.waitForExistence(timeout: 3))
        let finished = NSPredicate(format: "label == 'Replay demo'")
        expectation(for: finished, evaluatedWith: play)
        waitForExpectations(timeout: 30)
        let phone = app.scrollViews["history.phone"]
        let guest = app.scrollViews["history.g2"]
        XCTAssertTrue(phone.staticTexts["Perfect, let's go."].exists)
        XCTAssertFalse(guest.staticTexts["Your reply ideas"].exists)
        app.buttons["Next reply"].tap()
        app.buttons["Select"].tap()
        let cue = "Say this reply when you’re ready"
        XCTAssertTrue(phone.staticTexts[cue].exists)
        XCTAssertFalse(guest.staticTexts[cue].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Full fictional rehearsal complete - simulated displays"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor func testOnboardingDemoLiveAndPreviewToggle() {
        let app = XCUIApplication()
        app.launchArguments = ["--show-onboarding", "--silent-audio-capture", "--dual-glasses"]
        app.launch()
        XCTAssertTrue(app.buttons["Try the demo"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Start live capture"].exists)
        app.buttons["Try the demo"].tap()
        XCTAssertTrue(app.buttons["Play demo"].waitForExistence(timeout: 3))
        let previews = app.descendants(matching: .any)["glasses.previews.toggle"].firstMatch
        previews.tap()
        XCTAssertFalse(app.otherElements["preview.meta.screen"].exists)
        previews.tap()
        XCTAssertTrue(app.otherElements["preview.meta.screen"].exists)
        app.buttons["Live"].tap()
        XCTAssertTrue(app.buttons["Start conversation"].exists)
        XCTAssertFalse(app.buttons["rehearsal.play"].exists)
        app.buttons["Demo"].tap()
        XCTAssertTrue(app.buttons["Play demo"].exists)
    }

    @MainActor func testModeSwitchProtectsCurrentConversationAndExplainsLiveSetup() {
        let app = XCUIApplication()
        app.launchArguments = ["--fictional-rehearsal", "--silent-audio-capture", "--dual-glasses"]
        app.launch()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 10))
        app.buttons["Next"].tap()
        app.buttons["Live"].tap()
        XCTAssertTrue(app.buttons["Save & switch"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Hello, how are you?"].firstMatch.exists)
        XCTAssertTrue(app.buttons["rehearsal.play"].exists)
        app.buttons["Live"].tap()
        app.buttons["Discard & switch"].tap()
        app.buttons["Start conversation"].tap()
        XCTAssertTrue(app.buttons["Start live capture"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Start live capture"].isEnabled)
        if app.staticTexts["Translation service setup needed"].exists {
            app.buttons["Set up translation service"].tap()
            XCTAssertTrue(app.secureTextFields["Service access token"].exists)
        } else {
            XCTAssertFalse(app.secureTextFields["Service access token"].exists)
        }
    }

    @MainActor func testLiveSetupSurvivesSheetDismissalWithoutStartingMicrophone() {
        let app = XCUIApplication()
        app.launchArguments = ["--silent-audio-capture", "--dual-glasses"]
        app.launch()
        XCTAssertTrue(app.buttons["Live"].waitForExistence(timeout: 10))
        app.buttons["Live"].tap()
        app.buttons["Start conversation"].tap()
        XCTAssertTrue(app.buttons["Start live capture"].waitForExistence(timeout: 3))
        let needsSetup = app.staticTexts["Translation service setup needed"].exists
        XCTAssertFalse(app.buttons["Start live capture"].isEnabled)
        if !needsSetup { XCTAssertFalse(app.secureTextFields["Service access token"].exists) }
        app.buttons["Cancel"].tap()
        app.buttons["Start conversation"].tap()
        XCTAssertTrue(app.buttons["Start live capture"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["Translation service setup needed"].exists, needsSetup,
                       "Dismissing setup must not remove a provisioned service credential")
        XCTAssertFalse(app.buttons["Start live capture"].isEnabled, "Consent is still required on every capture")
    }

    @MainActor func testExplicitSavedHistorySurvivesRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--fictional-rehearsal", "--silent-audio-capture", "--dual-glasses"]
        app.launch()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 10))
        app.buttons["Next"].tap()
        app.buttons["Conversation history"].tap()
        app.buttons["Save conversation on this phone"].tap()
        XCTAssertTrue(app.staticTexts["Demo conversation"].firstMatch.waitForExistence(timeout: 3))
        app.terminate()
        app.launch()
        app.buttons["Conversation history"].tap()
        XCTAssertTrue(app.staticTexts["Demo conversation"].firstMatch.waitForExistence(timeout: 3))
        app.staticTexts["Demo conversation"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Hello, how are you?"].waitForExistence(timeout: 3))
    }

    @MainActor func testPhysicalRenderPageControls() {
        let app = XCUIApplication()
        if app.launchArguments.isEmpty { app.launchArguments = ["--fictional-rehearsal", "--silent-audio-capture", "--dual-glasses"] }
        app.launch()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["preview.meta.screen"].exists)
        XCTAssertTrue(app.otherElements["preview.g2.screen"].exists)
        app.buttons["Next"].tap()
        app.buttons.matching(identifier: "Display render").element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Meta previous page"].waitForExistence(timeout: 3))
        app.buttons["Meta previous page"].tap()
        app.buttons["Meta next page"].tap()
        app.buttons["Latest display page"].firstMatch.tap()
        let physical = XCTAttachment(screenshot: app.screenshot())
        physical.name = "Fitted Meta render and page controls"
        physical.lifetime = .keepAlways
        add(physical)
    }

    @MainActor func testBandSelectionStaysPrivateAndDoesNotSendATurn() {
        let app = XCUIApplication()
        if app.launchArguments.isEmpty { app.launchArguments = ["--fictional-rehearsal", "--silent-audio-capture", "--dual-glasses"] }
        app.launch()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 10))
        app.buttons["Next"].tap()
        app.buttons["Next reply"].tap()
        app.buttons["Select"].tap()
        let phone = app.scrollViews["history.phone"]
        let meta = app.scrollViews["history.meta"]
        let guest = app.scrollViews["history.g2"]
        let cue = "Say this reply when you’re ready"
        XCTAssertTrue(phone.staticTexts[cue].exists)
        XCTAssertTrue(meta.staticTexts[cue].exists)
        XCTAssertFalse(guest.staticTexts[cue].exists)
        XCTAssertFalse(guest.staticTexts["Your reply ideas"].exists)
        XCTAssertFalse(app.staticTexts["You · EN → ES"].firstMatch.exists)
        app.buttons["Next"].tap()
        XCTAssertFalse(app.staticTexts[cue].firstMatch.exists)
    }

    @MainActor func testIndependentHistoryDetachesAndResumesAfterIdle() {
        let app = XCUIApplication()
        if app.launchArguments.isEmpty { app.launchArguments = ["--fictional-rehearsal", "--silent-audio-capture", "--dual-glasses"] }
        app.launch()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 10))
        for _ in 0..<5 { app.buttons["Next"].tap() }
        let phone = app.scrollViews["history.phone"]
        let meta = app.scrollViews["history.meta"]
        let guest = app.scrollViews["history.g2"]
        XCTAssertTrue(phone.exists)
        XCTAssertTrue(meta.exists)
        XCTAssertTrue(guest.exists)
        XCTAssertFalse(guest.staticTexts["Your reply ideas"].exists)
        XCTAssertTrue(phone.staticTexts["Perfect, let's go."].exists)

        phone.swipeDown()
        let latest = app.buttons.matching(identifier: "Latest ↓")
        XCTAssertTrue(latest.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(latest.count, 1, "Only the surface scrolled by the user should detach")
        let resumed = NSPredicate(format: "exists == false")
        expectation(for: resumed, evaluatedWith: latest.firstMatch)
        waitForExpectations(timeout: 24)
        let visible = NSPredicate(format: "hittable == true")
        expectation(for: visible, evaluatedWith: phone.staticTexts["Wait a moment."])
        waitForExpectations(timeout: 3)

        meta.swipeDown()
        XCTAssertTrue(latest.firstMatch.waitForExistence(timeout: 3))
        latest.firstMatch.tap()
        XCTAssertFalse(latest.firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Independent histories after idle resume"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor func testImmediatePlayAndStandaloneHistory() {
        let app = XCUIApplication()
        if app.launchArguments.isEmpty { app.launchArguments = ["--fictional-rehearsal", "--silent-audio-capture", "--dual-glasses"] }
        app.launch()
        let play = app.buttons["rehearsal.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        XCTAssertTrue(app.staticTexts["Hello, how are you?"].firstMatch.waitForExistence(timeout: 3))
        play.tap()
        XCTAssertTrue(app.staticTexts["Your reply ideas"].firstMatch.exists)
        let initial = XCTAttachment(screenshot: app.screenshot())
        initial.name = "Native phone and glasses rehearsal"
        initial.lifetime = .keepAlways
        add(initial)
        app.descendants(matching: .any)["glasses.previews.toggle"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Hello, how are you?"].exists)
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["You · EN → ES"].firstMatch.exists)
        let standalone = XCTAttachment(screenshot: app.screenshot())
        standalone.name = "Standalone translation history"
        standalone.lifetime = .keepAlways
        add(standalone)
        app.buttons["Restart demo"].tap()
        XCTAssertTrue(app.staticTexts["A conversation, without the language barrier."].exists)
    }
}

/// Single-glasses mode. Speech is silent under --silent-audio-capture; the
/// kept screenshots feed the App Store set.
final class SingleGlassesUITests: XCTestCase {
    @MainActor private func keep(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor private func wait(_ element: XCUIElement, _ format: String, timeout: TimeInterval = 5) {
        expectation(for: NSPredicate(format: format), evaluatedWith: element)
        waitForExpectations(timeout: timeout)
    }

    @MainActor func testOnboardingOffersOneOrTwoPairsAndSingleLiveAttributesSpeakers() {
        let app = XCUIApplication()
        app.launchArguments = ["--show-onboarding", "--silent-audio-capture", "--fictional-rehearsal", "--single-glasses"]
        app.launch()
        let single = app.buttons["onboarding.glasses.single"]
        let dual = app.buttons["onboarding.glasses.dual"]
        XCTAssertTrue(single.waitForExistence(timeout: 10))
        XCTAssertTrue(dual.exists)
        XCTAssertTrue(single.isSelected)
        keep(app, "onboarding-glasses-choice")
        dual.tap()
        XCTAssertTrue(dual.isSelected)
        single.tap()
        app.buttons["Try the demo"].tap()
        XCTAssertTrue(app.buttons["Play demo"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["preview.meta.screen"].exists)
        XCTAssertFalse(app.otherElements["preview.g2.screen"].exists, "One pair shows one preview")
        app.buttons["Live"].tap()
        XCTAssertTrue(app.buttons["capture.me"].exists)
        XCTAssertTrue(app.buttons["capture.them"].exists)
        XCTAssertFalse(app.buttons["Start conversation"].exists)
        app.buttons["capture.them"].tap()
        let consent = app.switches["Everyone speaking agrees to sending this conversation's captures to Meta for translation"]
        XCTAssertTrue(consent.waitForExistence(timeout: 5), "Them opens the capture sheet before any consent")
        XCTAssertEqual(consent.value as? String, "0")
        keep(app, "single-live-capture-sheet")
        // The sheet is a lazy Form; its Start row sits below the fold.
        let start = app.buttons["Start live capture"]
        for _ in 0..<3 where !start.exists { app.swipeUp() }
        XCTAssertTrue(start.exists)
        XCTAssertFalse(start.isEnabled, "Consent is still required first")
        app.buttons["Cancel"].tap()
    }

    @MainActor func testPlayTogglesAndG2ShowsTheWearersView() {
        let app = XCUIApplication()
        app.launchArguments = ["--fictional-rehearsal", "--silent-audio-capture", "--single-g2"]
        app.launch()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 10))
        app.buttons["Next"].tap()
        let g2 = app.otherElements["preview.g2.screen"]
        XCTAssertTrue(g2.exists)
        XCTAssertFalse(app.otherElements["preview.meta.screen"].exists)
        wait(g2, "value CONTAINS 'Hello, how are you?'")
        XCTAssertTrue((g2.value as? String ?? "").contains("Estoy bien"), "The single wearer reads reply ideas on G2")
        let play = app.buttons["play.t1"]
        XCTAssertTrue(play.exists)
        XCTAssertEqual(play.label, "Play in English")
        play.tap()
        wait(play, "label == 'Stop'")
        play.tap()
        wait(play, "label == 'Play in English'")
        app.buttons["Next"].tap()
        XCTAssertTrue(app.buttons["play.t2"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["play.t2"].label, "Play in Spanish")
        app.buttons["Meta Display"].tap()
        XCTAssertTrue(app.otherElements["preview.meta.screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Hello, how are you?"].firstMatch.exists, "Switching displays keeps the conversation")
    }

    @MainActor func testSettingsGlassesSwitchProtectsTheConversation() {
        let app = XCUIApplication()
        app.launchArguments = ["--fictional-rehearsal", "--silent-audio-capture", "--single-glasses"]
        app.launch()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 10))
        app.buttons["Next"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Two pairs"].waitForExistence(timeout: 3))
        app.buttons["Two pairs"].tap()
        XCTAssertTrue(app.buttons["Save & switch"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["One pair"].isSelected)
        app.buttons["Two pairs"].tap()
        XCTAssertTrue(app.buttons["Discard & switch"].waitForExistence(timeout: 3))
        app.buttons["Discard & switch"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.otherElements["preview.g2.screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["preview.meta.screen"].exists)
        XCTAssertFalse(app.staticTexts["Hello, how are you?"].firstMatch.exists, "The guest's G2 never inherits the wearer's view")
    }

    /// Opt-in before/after tour: TEST_RUNNER_BORDERLESS_TOUR_DIR=<folder outside ~/Documents>
    /// writes one PNG per screen in a fixed state. Delete the app first so history starts empty.
    @MainActor func testScreenTour() throws {
        let folder = ProcessInfo.processInfo.environment["BORDERLESS_TOUR_DIR"] ?? ""
        try XCTSkipIf(folder.isEmpty, "Screen tour writes PNGs only when a folder is given")
        func shot(_ app: XCUIApplication, _ name: String) throws {
            let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
            try app.screenshot().pngRepresentation.write(to: url)
        }
        let app = XCUIApplication()
        app.launchArguments = ["--show-onboarding", "--silent-audio-capture", "--fictional-rehearsal", "--single-glasses"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.glasses.single"].waitForExistence(timeout: 10))
        try shot(app, "01-onboarding-single")
        app.buttons["onboarding.glasses.dual"].tap()
        app.swipeUp()
        try shot(app, "02-onboarding-dual")
        app.buttons["onboarding.glasses.single"].tap()
        app.buttons["Try the demo"].tap()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5))
        app.buttons["Next"].tap()
        app.buttons["Next"].tap()
        try shot(app, "03-demo-single")
        let play = app.buttons["play.t1"]
        if play.waitForExistence(timeout: 3) {
            play.tap()
            wait(play, "label == 'Stop'")
            try shot(app, "04-play")
            play.tap()
        }
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Two pairs"].waitForExistence(timeout: 3))
        try shot(app, "05-settings")
        app.swipeUp()
        try shot(app, "06-settings-lower")
        app.buttons["Done"].tap()
        app.buttons["Conversation languages"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        try shot(app, "07-languages")
        app.buttons["Done"].tap()
        app.buttons["Conversation history"].tap()
        XCTAssertTrue(app.buttons["Save conversation on this phone"].waitForExistence(timeout: 3))
        app.buttons["Save conversation on this phone"].tap()
        try shot(app, "08-history")
        app.buttons["Done"].tap()
        app.buttons["Live"].tap()
        if app.buttons["Discard & switch"].waitForExistence(timeout: 3) { app.buttons["Discard & switch"].tap() }
        XCTAssertTrue(app.buttons["capture.me"].waitForExistence(timeout: 3))
        try shot(app, "09-live-single")
        app.buttons["capture.them"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 3))
        try shot(app, "10-capture")
        app.swipeUp()
        try shot(app, "11-capture-lower")
        app.buttons["Cancel"].tap()
        app.terminate()

        app.launchArguments = ["--silent-audio-capture", "--fictional-rehearsal", "--dual-glasses"]
        app.launch()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 10))
        app.buttons["Next"].tap()
        app.buttons["Next"].tap()
        try shot(app, "12-demo-dual")
        app.buttons["Live"].tap()
        if app.buttons["Discard & switch"].waitForExistence(timeout: 3) { app.buttons["Discard & switch"].tap() }
        XCTAssertTrue(app.buttons["Start conversation"].waitForExistence(timeout: 3))
        try shot(app, "13-live-dual")
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Two pairs"].waitForExistence(timeout: 3))
        try shot(app, "14-settings-dual")
    }

    @MainActor func testRecordedDemoInSingleGlassesMode() {
        let app = XCUIApplication()
        app.launchArguments = ["--silent-audio-capture", "--single-glasses"]
        app.launch()
        let demo = app.buttons["rehearsal.play"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        demo.tap()
        let meta = app.otherElements["preview.meta.screen"]
        var reached = false
        let deadline = Date().addingTimeInterval(60)
        // Sampling screenshots keeps a headless simulator's display current.
        while !reached && Date() < deadline {
            let value = meta.value as? String ?? ""
            reached = value.contains("2 reply options") && value.contains("Madrid")
            if !reached { _ = app.screenshot(); Thread.sleep(forTimeInterval: 0.4) }
        }
        XCTAssertTrue(reached, "The wearer sees Sofía's question in English with reply ideas")
        XCTAssertFalse(app.otherElements["preview.g2.screen"].exists)
        keep(app, "single-meta-demo-mid-conversation")
        let line = app.buttons["play.audio-0-1"]
        XCTAssertTrue(line.waitForExistence(timeout: 3))
        line.tap()
        wait(line, "label == 'Stop'")
        wait(demo, "label == 'Play demo'")
        let previews = app.descendants(matching: .any)["glasses.previews.toggle"].firstMatch
        previews.tap()
        keep(app, "single-play-in-use")
        line.tap()
        wait(line, "label == 'Play in English'")
        previews.tap()
        app.buttons["Even G2"].tap()
        let g2 = app.otherElements["preview.g2.screen"]
        XCTAssertTrue(g2.waitForExistence(timeout: 3))
        wait(g2, "value CONTAINS 'Madrid'")
        keep(app, "single-g2-demo-mid-conversation")
    }
}
