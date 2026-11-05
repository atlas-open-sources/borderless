# Conversation inference and development relay

`Conversation` accepts finalized speech updates and explicit host/guest attribution. It translates English ↔ Spanish through the existing budgeted text adapter, producing exactly two Spanish reply choices for the English host and none for the guest. Pronunciation is approximate, not pinyin. Both synchronous `submit` and cancellable `submit_async` share validation, revisions, bounded context and stale-result rejection.

`SpeechConversation` connects bounded speech transport to an ordered four-turn translation queue. Partials never trigger model calls. Queue overload stops capture; it never silently drops an utterance. Recipient events explicitly separate host from guest, removing all reply options from guest output. Stop cancels both tasks, invalidates retained state and emits stopped. Consumers must clear actionable replies on stopped and clear private transcript presentation on consent withdrawal. Callbacks have a three-second deadline.

`AsyncRelay` runs the existing metered HTTP adapter in a short-lived server process. Cancellation kills and reaps the process; ambiguous ledger reservations remain. Its 50-second overall deadline bounds both token-count and generation calls. No automatic retries; no API key in client or command arguments.

## Local protocol

Start `python3 -m conversation_relay.server` for a loopback-only development service at `ws://127.0.0.1:8766`. This is not a deployed backend and cannot be reached from a physical phone on another device. The server creates `.budget/relay-token` with private file permissions; configure that separate token in the development client, never the provider API key. Browser origins are rejected and only one paid session runs at a time.

Initial JSON: `{"type":"start","token":"<local relay token>","participant":"guest","consent":true}`. Explicit participant is host (English) or guest (Spanish), fixed for this bounded capture. Send binary PCM24k mono16 frames up to 4,800 bytes, then `{"type":"end"}`. `{"type":"stop"}` or disconnection cancels capture/inference. Frames must arrive at real-time pace. No microphone is captured by the service itself.

Events: started, completed, stopped, error, and `{"type":"turn","audience":"host|guest","turn":{...}}`. A turn contains integer id, revision, speaker, source, translation, status and replies (text/gloss/pronunciation). Prefix IDs with a client capture UUID when retaining turns across reconnects. The phone is the authorized host client; it routes only guest-audience projections to G2. Reconnect begins a new capture and inference context. Cross-capture conversational context and dynamic speaker switching remain integration work; this protocol is a controlled-turn baseline, not automatic diarization.

## Evidence

54 Python tests pass, including queue overload, cancellation, recipient privacy, token/consent validation, concurrent-session rejection and a real local WebSocket round trip with a synthetic pipeline. No paid request was made for this integration slice. The earlier text-only two-direction canary passed. Earlier live ASR produced completed transcripts but hit a trailing event bug, since fixed with regression coverage; clean post-fix live shutdown remains unverified.

Run `python3 -m unittest discover -s tests -v`. `python3 -m conversation_relay` is a separate TWO-PAID-REQUEST text canary, not a unit test; never include it in automated suites.

Remaining: native service/capture wiring, actual audio route and physical glasses acceptance. Browser remains recorded-fixture playback. This service has not been exposed or deployed.

## Attended physical-phone transport configuration

The default server remains bound to `127.0.0.1:8766`. For an explicitly started development session, the server accepts `--bind <local-IP> --port <port> --tls-cert <certificate.pem> --tls-key <key.pem>`. Non-loopback binds require both TLS files and TLS 1.2 or newer. No remote listener, certificate, tunnel or deployment has been created by this implementation.

Use a hostname/certificate trusted by the phone and set the app's relay address to the corresponding `wss://` URL. Do not bypass trust validation. The app sends the separate relay token in its WebSocket handshake; provider credentials stay on the server. It rejects credentials in URLs and refuses redirects. The server accepts native clients only (no browser Origin), authenticates before starting inference and serializes paid sessions. Stop the synthetic fixture server before binding its port. LAN reachability, trust, signing and physical capture are still attended acceptance gates.

## Public hosted relay

`python3 -m conversation_relay.hosted` wraps the same `SessionServer` for TestFlight and judges: up to three paid sessions at once, a 120-second wall clock, eight translations per session, per-install and per-IP rate limits, a daily spend cap, a kill switch and the shared $20 allowance (local spend is seeded into the hosted ledger). The start message may carry an optional `install_id` UUID; errors carry a `code`. It listens plain behind a TLS proxy (`--behind-proxy`) and answers `GET /health`. Deployment, limits and costs: `deploy/README.md`.
