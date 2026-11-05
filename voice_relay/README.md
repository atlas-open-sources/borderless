# Bounded speech transport

`SpeechTransport` wraps the offline `VoiceStream` with authenticated Meta WebSocket ASR. Install `python3 -m pip install -r voice_relay/requirements.txt`. Credentials load server-side from the project environment file; never send them to a browser or native client.

Input is an async iterator of PCM24k mono16 frames, at most 100 ms each. Defaults: 60 seconds input, five seconds final drain, bounded message/receive buffers, real-time pacing and explicit consent/source epoch. Cancellation closes the socket, cancels producer/receiver tasks and clears core state. No microphone adapter or automatic retry is supplied. Callbacks must complete promptly; enqueue translation into a bounded consumer rather than perform a slow model call inside the callback. Source identity does not establish speaker identity.

ENDPOINTING and CUMULATIVE partials are supported. speechComplete is authoritative. A trailing stable transcript after completion is ignored without revising completed text; this ordering was observed in live synthetic tests. Old-turn completions do not steal current-turn partial ownership. DIARIZATION and PUSH_TO_TALK are not implemented.

The existing ledger reserves the full configured duration ceiling before opening a socket and conservatively retains that ceiling after success. Ambiguous failures retain their reservation. This is local project accounting, not provider invoicing or account-wide usage. Voice pricing was checked at $0.18/hour; the provider rounds processed audio to whole seconds, while this implementation intentionally keeps its larger ceiling.

Verification: the current backend suite has 74 passing Python tests, including transport tests with fake sockets, cancellation, timeouts, malformed input and trailing-final shutdown. Two live synthetic greeting requests produced correct completed transcripts but failed at the trailing transcript event. Post-fix English and Spanish synthetic-audio live tests now complete cleanly, including translation and recipient delivery. A native Swift live test exposed premature readiness; the relay now waits for provider acknowledgment before authorizing capture. The delayed-handshake regression and post-fix native live retry pass. No microphone or hardware was used.

Integration now exists in `conversation_relay`: bounded final-event translation queue, authenticated development WebSocket delivery, provisional source events and recipient-specific results. The native app composes the relay with explicit phone capture through reusable packages. Composed synthetic tests exercise the real server/ASR parser/translation orchestration with fake providers; Swift wire and simulator UI evidence remain separate. See [current evidence](../docs/IMPLEMENTATION-STATUS.md).

Remaining: trusted physical-phone relay environment and attended audio-route/dual-glasses evaluation. Live synthetic verification is not physical microphone or optical proof. Existing browser fixture replay is unchanged.

Run `python3 -m unittest discover -s tests -v` from the project root.

References checked 2026-10-29: [realtime API](https://dev.meta.ai/docs/api-reference/voice/realtime), [schemas](https://dev.meta.ai/docs/api-reference/voice/schemas), [pricing](https://dev.meta.ai/docs/pricing-rate-limits).
