import XCTest

/// Live translation on a real phone against the hosted relay, with recorded speech fed in through
/// `--capture-wav` (no microphone, nothing played aloud). One paid capture (~$0.02). Opt-in only:
/// `TEST_RUNNER_BORDERLESS_HOSTED_DEVICE=1 xcodebuild test … -only-testing:BorderlessUITests/HostedLiveUITests`
/// on a Debug build whose Relay.local.xcconfig points at the hosted relay.
final class HostedLiveUITests: XCTestCase {
    @MainActor func testSingleGlassesLiveTranslatesTheGuestThroughTheHostedRelay() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BORDERLESS_HOSTED_DEVICE"] == "1")
        let app = XCUIApplication()
        app.launchArguments = ["--skip-onboarding", "--single-glasses", "--silent-speech",
                               "--capture-wav=debug-speech-guest-es"]
        app.launch()
        XCTAssertTrue(app.buttons["Live"].waitForExistence(timeout: 10))
        app.buttons["Live"].tap()
        let them = app.buttons["capture.them"]
        XCTAssertTrue(them.waitForExistence(timeout: 5))
        them.tap()
        let consent = app.switches["Everyone speaking agrees to sending this conversation's captures to Meta for translation"]
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let start = app.buttons["Start live capture"]
        for _ in 0..<3 where !start.exists { app.swipeUp() }
        XCTAssertTrue(start.isEnabled)
        start.tap()

        let translated = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'first time in Madrid'")).firstMatch
        let reached = translated.waitForExistence(timeout: 75)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "hosted-live-guest-translated"
        shot.lifetime = .keepAlways
        add(shot)
        print("HOSTED_LIVE " + app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | "))
        XCTAssertTrue(reached, "The guest's Spanish comes back in English through the hosted relay")
        let meta = app.otherElements["preview.meta.screen"]
        if meta.exists {
            XCTAssertTrue((meta.value as? String ?? "").contains("Madrid"), "The wearer's glasses show the translation")
        }

        // The live conversation is already in History, with Play on its line.
        app.buttons["Conversation history"].tap()
        let kept = app.buttons["history.saved.live"].firstMatch
        XCTAssertTrue(kept.waitForExistence(timeout: 5), "Live conversations are kept as they happen")
        kept.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'first time in Madrid'")).firstMatch
            .waitForExistence(timeout: 3))
        let historyShot = XCTAttachment(screenshot: app.screenshot())
        historyShot.name = "hosted-live-kept-in-history"
        historyShot.lifetime = .keepAlways
        add(historyShot)
    }
}
