# BorderlessKit

Reusable native session logic and display projection for the one-phone conversation app.

- `BorderlessCore`: Foundation-only, Sendable value state. Explicit participant identity and consent, session epochs, transcript revisions, bounded history, private host replies, stale-token rejection and 20-second follow policy. An app actor/main-actor model owns serialization; this value type does not own microphone or network tasks.
- `BorderlessDisplay`: imports the existing `GlassesSceneKit` package from the sibling even-companion checkout. Projects the session into participant-specific semantic scenes. Existing G2Render and MetaRender perform device layout. No vendor transport, session lifecycle or credentials are copied here.
- Tests replay the same five-turn Spanish JSON fixture as the browser and exercise both real renderers on macOS. Fixture changes must update this test resource; these are text fixtures, not audio/hardware recordings.

```sh
swift test --package-path native/BorderlessKit
```

`ConversationScene.make(... through: turnID)` displays an older logical window without actionable stale replies. A nil cursor follows latest. This is not complete physical scrollback: the existing renderers still crop to ten rows/lines. Pixel-fitted row windows, long utterance pagination and semantic input routing remain required before hardware acceptance. Confirming a reply only sets a private reading cue; it never appends speech.

The consuming app must gate band events on connection state, capture the current ReplyToken when presenting actions, and reject callbacks from replaced scenes. It must bind audio source epochs separately and explicitly resolve speaker attribution. Store no API credentials in the app. Stop/cancel owned work on consent withdrawal. No native app shell, signing, pairing or microphone implementation is included yet.

even-companion is pinned by revision (Package.swift; EVEN_COMPANION_LOCAL=1 for the sibling checkout). Versioned public vendoring remains a separate publication step; no upstream repository was modified.

## Native relay adapter

`BorderlessRelay` supplies a loopback-only URLSession WebSocket actor and separately testable wire decoder. It accepts explicit consent, a separate local service token and paced PCM from an external capture owner; it never accesses the provider key or starts a microphone. Call stop to close the socket and invalidate old callbacks. Wire IDs are namespaced by capture UUID, and guest events carrying replies are rejected.

With `python3 -m conversation_relay.fixture_server` running at project root, run `BORDERLESS_FIXTURE_RELAY=1 swift test --filter realFixtureRelayRoundTrip` here. The opt-in test exercises actual native networking against synthetic responses, with no paid provider. This is distinct from the ordinary pure package tests and from hardware validation.

### Capture continuity

`RelayContextTurn.recent` carries at most six recent spoken source turns (6,000 Unicode scalar values total, 2,000 per turn) into the next capture. It excludes translations, private reply suggestions and pronunciation cues. The relay independently validates the same limits before starting provider work. Reset/Stop clears the phone conversation, so a new capture has no retained context. This is explicit participant attribution, not automatic diarization.

### Fitted display pages

`ConversationViewport.pages(_:wearer:)` covers the retained conversation and current host reply cues using shared G2 firmware metrics and Meta font/layout metrics. No history page has reply actions; only current host reply pages do. Focused/selected reply pages are last. Long content splits at Character boundaries instead of dropping the beginning. Unsupported firmware glyphs remain a hardware/font limitation. Compute away from the main actor and cache by conversation revision; optical acceptance is still required.
