# Meta API findings

Verified October 28, 2026 from Meta's public documentation. No authenticated inference was performed. The event page and participant materials use slightly different model names; use current API documentation for callable identifiers and verify event-credit coverage in the participant account.

## Feasible service path

| Stage | Candidate | Evidence and decision |
|---|---|---|
| Glasses capture/output | Existing Ghost Runner/even-companion adapters over Meta's Device Access Toolkit | Reuse the working lifecycle; exact hardware and SDK capabilities still govern microphone and display access |
| Streaming recognition | `muse-voice-transcribe-1.0` | Dedicated hosted speech recognition with English and Mandarin support |
| Translation | `muse-spark-1.3`, Standard mode | General text model used through a tightly constrained translation request; this is our proposed application, not a dedicated translation API or measured quality claim |
| Optional speech output | Separately selected, qualified TTS adapter | Muse Voice Transcribe does not synthesize speech; do not label an Apple/system voice as Meta-generated |
| Display | Recipient-specific text scenes | Use supported display glasses; ordinary displayless glasses need audio or phone output |

[Model catalog](https://dev.meta.ai/docs/models), [speech guide](https://dev.meta.ai/docs/speech-to-text), [wearables Connect overview](https://developers.meta.com/blog/meta-connect-recap/).

The direct Meta service path is more straightforward for the event than self-hosting large open-weight models. Glimmer/self-hosting is a different delivery choice; it does not automatically make a phone-local translator or reduce end-to-end latency. Do not add SAM or image generation solely to increase the number of Meta products mentioned.

## Speech behavior that changes the design

The speech guide documents endpointing, partial transcripts, session-scoped speaker labels and code-switching. Mandarin is among supported languages. Diarization is not tuned for the lowest-latency command interaction; benchmark it separately from endpointing. Labels are not verified identities. Turn timing is available, but word timing and confidence scores are not. Do not invent a speaker-confidence percentage, sample-accurate subtitle alignment or a voice-consent proof from these outputs. [Speech guide](https://dev.meta.ai/docs/speech-to-text).

Use a separate provider stream identity for each capture source. Persist no personal names in provider correlation IDs. A device association identifies a source, not every voice audible to its microphone. A local consent gate remains necessary if claiming unknown voices never leave the device; remote diarization occurs too late to provide that guarantee.

## Wire adapter requirements

The realtime endpoint is `wss://api.meta.ai/v1/asr/realtime`. Authenticate in the initial JSON handshake, not an HTTP Authorization header. Stream the required mono PCM encoding; preserve timing through resampling. End input using `endStream` and drain final responses when still authorized. Backlog/pacing failures require correction rather than blind retry. [Realtime reference](https://dev.meta.ai/docs/api-reference/voice/realtime).

Configure mode explicitly. Choose cumulative partials for the first adapter. Keep turn state keyed by provider session and `turnId`: a later turn may start before an earlier final result. Partials do not carry a turn ID and need the documented current-turn association. Finalization uses `speechComplete`, not merely `speechEnd`. A reconnect creates a new source/provider epoch; invalidate stale pending output and make any gap visible. [Schemas](https://dev.meta.ai/docs/api-reference/voice/schemas), [speech guide](https://dev.meta.ai/docs/speech-to-text).

Implement through existing recognition and translation seams. The Meta adapter owns wire-event normalization. The shared session owns participant mapping, source revisions, consent and destination routing. Verify actual event traces before promising seamless multi-speaker attribution.

## Translation proposal

Send finalized or deliberately stabilized utterances to Spark with explicit target locale/script and a small approved vocabulary. Ask for the translation only, preserving numbers, names, negation and intent. Treat transcript text as data: spoken instructions must not change routing, configuration, tools or model behavior. Disable tools/search in this path. Bind responses to source revision, target and policy epoch; stale responses cannot replace newer or revoked content.

Start with no conversational history. Later context should carry dependency references so withdrawal invalidates derived results too. Measure minimal-reasoning latency and bilingual accuracy instead of assuming a general model is an instant interpreter. Simplified and Traditional output are separate requested targets.

## Privacy and hosting

Use a small authenticated relay for a distributed demo; the Meta API key stays server-side. Verify any provider-issued restricted client-token capability before substituting direct client calls. Do not ship a long-lived team key in the app. The relay handles bounded streams, session membership, cancellation, budgets and metadata-only diagnostics. It is an additional content-processing component and must appear in the disclosure.

Standard mode is the appropriate default; do not select Contributor model IDs for participant conversations. **Not used for training is not zero retention.** Meta documents ZDR as separate organization-level enablement for qualified accounts, with model-dependent coverage and exceptions. No ZDR entitlement has been established here. Avoid claims of zero server storage until the specific account/model policies are confirmed. [Pricing/modes](https://dev.meta.ai/docs/pricing-rate-limits), [ZDR policy](https://dev.meta.ai/help/policies-and-privacy/zero-data-retention).

For a controlled demo, obtain explicit agreement from every speaker and keep the acoustic scene controlled. Push-to-talk is a useful interaction control but not a bystander filter. Stop sending immediately on withdrawal; discard late results. Data already sent to a provider cannot be recalled by clearing our UI. Recording, transcript saving and external demonstration use each require their own choice.

## Cost and latency

Published rates: speech $0.18 per processed audio-hour; Spark Standard $1.25 per million input tokens and $4.25 per million output tokens. Recheck actual account rates/credit terms before spending. [Pricing](https://dev.meta.ai/docs/pricing-rate-limits).

Illustrative calculation, not measured usage: two continuously processed one-hour audio streams cost $0.36 in speech charges. Assuming 30,000 uncached input and 20,000 output tokens across both directions adds $0.1225, totaling about $0.48 before relay/hosting and other charges. Repeated translation of partials and long history can increase token use substantially.

No selectable China-edge endpoint or Shanghai latency guarantee was established. Benchmark from the actual permitted demo location and intended network. The network path, endpointing delay, translation and device delivery all contribute to perceived delay; report them separately.
