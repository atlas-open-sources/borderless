> 2026-10-30 correction: both wearers see original and translation, including their own speech. Host keeps the question with both complete alternatives and English meanings underneath. No written phonetics. Optional pronunciation audio is separate and remains off by default.

> Latest user correction: default rehearsal is English ↔ Spanish, Meta host Alex and G2 guest Sofía. Open and press Play immediately; no join checkboxes. Host-only reply suggestions with Spanish, English meaning and approximate pronunciation. Guest has translation only. This overrides older Mandarin/both-participant suggestion descriptions below. Real microphone permission remains separate from fictional replay.

# One phone, two people, optional glasses

Status: browser and native rehearsals implemented and tested; native package/relay integration has synthetic evidence. Live-provider completion and attended physical acceptance remain pending. Current receipts: IMPLEMENTATION-STATUS.md. Product name: Borderless.

## Product contract

One iPhone owns the conversation, consent, inference, language routing and reply selection. Alex wears Meta Display as host; Sofía wears Even G2 as guest. Both displays are optional outputs. The app must remain usable with neither attached, and previews can be hidden independently of connection state. No second phone or account is part of this target experience.

The top preview strip mirrors recipient-specific output. Meta shows two suggested replies, a focused choice, and the confirmed pronunciation cue; Chinese includes pinyin and meaning. The chat contains the same choices. Up/down moves focus; confirm opens a private cue. It never sends or commits a conversational turn. An optional, default-off pronunciation setting can speak the selected Spanish reply privately over a personal audio route after capture finishes. New speech, revisions, stop, and revoked consent invalidate obsolete actions. Physical input maps to these semantic actions only after checking the actual SDK event surface.

G2 guest receives Spanish conversation text and translations only; reply assistance is private to the Meta host. The host's Meta display is the primary reply-navigation surface. Neither speaker identity nor transcript direction is inferred solely from which glasses heard the sound.

## Audio decision and evaluation

Decision: one selected capture source and one provider ASR session initially. Use the phone microphone as the standalone baseline; evaluate the Meta microphone and G2 SDK audio as alternatives. Source changes create an explicit capture epoch and visible gap. Do not sum two microphone signals by default.

| Option | Advantages | Costs and risks | Decision |
| --- | --- | --- | --- |
| One phone mic | Standalone; one clock; no duplicate capture | Distance and room noise | Baseline |
| One selected glasses mic | Potentially better near-field sound; one inference stream | May favour wearer; SDK/audio-route constraints | Compare on hardware |
| Two separate ASR streams | Keeps source evidence; no waveform sync needed | Duplicate utterances, conflicting text, doubled audio; diarization labels not shared | Experimental candidate after capture feasibility |
| Mix two raw streams | One ASR input | Clock drift, delays, clipping, acoustic duplication, loss of provenance; overlap remains | Reject as default; evaluate only if simpler options fail |

This is an engineering decision, not a measured accuracy conclusion. Two transports being connected does not prove iOS permits both microphones to be captured simultaneously. Preserve timestamps, source IDs, sample counts, route changes and capture epochs if dual capture is available. Energy alone is not a wearer classifier. Avoid fast source switching mid-utterance.

Compare identical consented recordings across candidates: 20 English/Spanish turns including times, prices, names, negation, overlap and code-switching; quiet and café noise; each orientation. Score omitted/duplicated turns, Spanish and English word error rates, meaning/number accuracy, p50/p95 speech-end-to-visible translation, provider audio duration, route gaps and CPU/battery. Test dual-stream duplicate reconciliation separately from recognition. Require human bilingual scoring before selecting a winner. No synthetic timing will be reported as measured device latency.

For the first controlled session, participants choose English and Spanish and take turns. Provide explicit speaker/direction correction or push-to-talk where language is ambiguous. A third speaker or code switching must not silently become an enrolled participant. Voiceprints are not needed to prove this controlled demonstration; robust automatic identity is a separate feature.

## Execution and gates

1. Browser target: one-phone layout, optional previews, inline/display suggestions, band simulation, complete recorded-fixture replay. Verify reducers, browser interactions, phone-only mode, mobile layout, stale events and reconnection.
2. Native shared session: portable transcript/revision/epoch and reply-action contracts; keep transport, model and UI adapters outside core. Port the browser fixtures to native golden tests. Use current GlassesSceneKit/TextKit/MetaDisplayKit seams after checking actual source, not a copy of Cat lifecycle code.
3. Real service slice: one bounded capture stream → Muse Voice Transcribe → stable utterance → Spark translation and two replies → app output. Key remains in relay. Bound duration, retries and cancellation. Preserve existing accounting; authorized total is $20 including prior spend. No uncontrolled replay loops.
4. Native display/input: one phone connects Meta and G2 independently. Render same revision to app and applicable devices, map supported band actions to navigation, cancel on stop, recover one adapter without restarting the conversation. Connection logs must show the same phone session, device types and independent lifecycle events without identifiers in submission footage.
5. Physical acceptance with user: connect both pairs; measure the audio options; record the app and both wearer/display views. Run 20 bilingual turns and a 30-minute session; verify disconnect, replay, pending/revised replies, stop, source switch and no duplicate turns. Optical recordings and simulated preview footage must be identified separately.
6. Submission: three-minute honest demo, public source only after publication approval, inherited versus new work, measured evidence, and the Meta guest-session request below. Do not claim OSS release or multi-Meta support before it exists.

## Overnight bounds

Maximum unattended implementation window: six hours, three review rounds, two delegated agents at once. Stop paid calls on exhausted allowance or ambiguous usage; no retries that bypass the ledger. Stop any work loop after two attempts with no progress and leave a concrete receipt. Preserve credentials, ledger and other sessions' files. No deployment, submission, SDK-account changes or installed app replacement. Device pairing and physical demonstration remain attended gates. A saved plan is not a running automation; scheduler status must be recorded separately if used.

## Meta request deliverable

See META-GUEST-MODE-REQUEST.md. Mixed-manufacturer success will be evidence that one-phone guest experiences are useful and implementable in our orchestration layer; it cannot establish that multiple Meta devices already work in DAT.

## Source audit update

Our source review confirms Ghost Runner already publishes to both manufacturers in one app and preserves separate capture tracks. Reuse those seams. Current band navigation needs real action handling and publishable SDK support; current Meta controller selects one session. Physical concurrency and guest pairing remain unverified.
