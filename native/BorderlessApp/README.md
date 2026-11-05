# Borderless native rehearsal

Standalone iOS 18+ SwiftUI app. Open `Borderless.xcodeproj`, select Borderless and an iPhone simulator, then Run. Regenerate the committed project with `xcodegen generate --spec project.yml` from this directory when its configuration changes.

The app uses the real `BorderlessCore` conversation and `HistoryFollow` state. Optional blue Meta / green G2 transcript previews share one session with the phone; the always-visible top screen previews use the actual `MetaRender` and `G2Render` implementations through `ConversationScene`. The continuous transcript preview is a UI simulation, not a claim that a physical lens has unlimited scrollback. ConversationViewport paginates through those physical line limits without dropping long transcript or reply text. Each display has independent Previous/Next/Latest controls and returns to latest after 20 idle seconds. The focused reply cue is the host default page.

Press Play immediately. No glasses, checkbox, account, microphone or network is required. The bundled Spanish fixture is the browser rehearsal fixture. English-speaking Alex gets Spanish reply ideas, English meanings and approximate pronunciation. Spanish-speaking Sofía sees no reply suggestions. A selection is a private reading cue and never sends speech. Next steps through turns; Reset invalidates the session. Each of the three scroll histories owns a separate follow policy, resumes at bottom or after 20 idle seconds, and offers Latest while detached.

This target has a unique rehearsal bundle identifier. Bluetooth and microphone purpose strings support explicit connection and capture. It does not replace Ghost Runner or Local AI Cat. Device lifecycle and microphone ownership live in reusable packages. Optical acceptance remains separate work; fitted paging is verified against the shared renderer models.

Build:

```sh
xcodebuild -project Borderless.xcodeproj -scheme Borderless -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Tests include the model's source/reply invalidation and a UI rehearsal test exercising Play, transcript visibility, optional previews, standalone mode, Next and Reset. Evidence is recorded in the project artifacts receipt; a build alone is not physical-glasses verification.

## Synthetic relay benchmark

From project root run `python3 -m conversation_relay.fixture_server`, then in the simulator open Rehearsal tools (ellipsis) → Test local fixture relay. It sends two synthetic zero bytes to the loopback service and receives the same five-turn fixture through the reusable BorderlessRelay client. No provider call or microphone recording occurs. The fixture token cannot authenticate to the paid development service. Normal Play stays entirely on-device and works without a server.

The native relay actor has a real wire round-trip test against this fixture service, including ten provisional events, five host/five guest final projections, completion ordering and guest reply exclusion. Actual live audio integration is not implied by this benchmark.

The simulator UI benchmark `testLocalRelayConversationAndPrivateSelection` is opt-in: start the synthetic service, then prefix the xcodebuild test command with `TEST_RUNNER_BORDERLESS_TEST_RELAY=1` and select `-only-testing:BorderlessUITests/RehearsalUITests/testLocalRelayConversationAndPrivateSelection`. It opens the tools menu, loads the five network-delivered turns, and verifies private host selection. Without the opt-in it skips, so ordinary offline tests need no server.

## Device adapter composition

The tools menu offers explicit Meta Connect/Register/Disconnect and G2 Enable/Disable. Both are owned by this one app; initialization never configures DAT or binds the G2 server. Meta uses the new reusable MetaDATAdapter (real DAT1.0.0 + shared MetaDisplayKit), and G2 uses BorderlessG2 (shared EvenCompanionKit + Swifter loopback listener). Scene updates route host content to Meta and guest content to G2 independently. Reply action IDs are tied to native conversation epochs/revisions, including when a new turn repeats identical words.

The generated Info.plist uses the `borderless://` callback scheme (Config/*.xcconfig; Release takes an HTTPS app link from Meta.local.xcconfig) and DAT developer-mode placeholders (`0`), not another app's credentials. Physical installation requires normal signing and supported Meta developer registration. The Borderless Meta project has been created; team 599WAZ6282 is configured locally; the console still needs its valid callback configuration. Stable display button callbacks are connected; experimental raw band up/down input remains separate.

G2 needs the matching Borderless plugin profile and a content/pairing smoke check. Ghost Runner already validates the shared companion lifecycle, as confirmed by the user. Serving a frame is not proof of BLE delivery. Neither adapter adds a Live Activity or artificial keepalive. Device and background validation remains attended.

## Explicit live capture (development)

The tools menu opens a separate capture sheet with speaker selection, a secure local relay token field and both-person consent. Start requests microphone permission, connects the relay, then starts the built-in phone microphone only after the relay acknowledges readiness. Capture is bounded to 60 seconds. Finish utterance drains queued PCM and keeps translated replies; Stop and clear, Reset or entering the background cancel forwarding and clear the session. No automatic retry or speech playback occurs.

The default relay endpoint is simulator loopback at port 8766. The capture sheet also accepts a trusted `wss://` relay address. Cleartext remote URLs, embedded credentials, query parameters and fragments are rejected. HTTP redirects are declined. A physical iPhone needs a reachable relay with a certificate trusted by iOS; that environment has not been provisioned or device-tested. The token is for this development relay, never a Meta API key. The synthetic fixture server uses the same port and must be stopped before starting the actual service.

Borderless is the user-approved product name. Package, target, bundle and callback identifiers now use Borderless consistently. The previous Elsewhere simulator installation is a separate identity; no shipping app was replaced.

Physical pages are calculated off the main actor with one worker and the latest pending snapshot only. Reset invalidates in-flight work. G2 receives an immutable guest projection so publishing does not repeat text layout or accidentally send host assistance. New capture immediately invalidates old reply actions while waiting for speech.
