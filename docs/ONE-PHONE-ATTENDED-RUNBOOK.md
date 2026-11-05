# Borderless: attended one-phone acceptance

This is an acceptance procedure, not a completed device test. Browser playback,
Swift tests and iOS simulator builds are separate evidence from physical output.

## Prepare before capture

Use the separately identified Borderless rehearsal build; do not replace Ghost
Runner or another shipping installation. Configure the app's own Meta developer
registration and signing. Enable its matching G2 plugin in Even Hub. The plugin
profile permits only the companion's loopback port 8767 and has no microphone
capability. The phone needs a reachable trusted WSS relay; simulator localhost
8766 is not a backend reachable from a physical phone. No API key belongs in the
app; the live sheet accepts only the relay's separate token.

Enable the G2 companion in Borderless, open the matching plugin in Even Hub,
then return to Borderless. The shared plugin's frame executor intentionally
continues polling when its phone page is hidden. The user confirms this shared lifecycle is already tested and verified in Ghost Runner.
For Borderless, check the matching package, port and projected content; do not treat
background continuity as an unresolved architecture blocker.
Keep Borderless foreground for the controlled test. If G2 freezes, record the
foreground app and last frame; do not add a fake keepalive or treat serving status
as proof of delivery. Never start a recording just to keep a process alive.

Connect/register the Meta display explicitly. Default Play does not register,
connect, enable inputs, access a microphone or call a model. Test fictional Play
and both physical display outputs before enabling live capture.

## Navigation contract

The stable build uses native Meta display buttons for private reply selection.
Experimental band input is a separate opt-in build and explicit activation on an
already connected Meta session. It requests only neural-band input, not capture
buttons or motion streams. Up/down selects host reply focus; when no replies
exist it pages host history. Left/right pages history independently. Select opens
a private pronunciation cue. Back dismisses the cue and returns to latest.
Nothing sends a reply. Pronunciation is off by default; when enabled, confirmation requests Spanish speech over a personal audio route after capture finishes. G2 never receives host reply assistance.

Record physical event delivery, duplicate handling, disconnect, reconnect, input
stream termination and application backgrounding. Simulator mapping tests do not
establish band availability or publication eligibility. Backgrounding disables
band navigation; explicitly re-enable it after returning.

## Live speech

Obtain both participants' consent, select the current speaker explicitly, and
start one bounded phone-microphone capture. The relay must acknowledge readiness
before recording starts. Finish utterance drains queued audio and retains the
completed result. Stop and clear cancels and clears. Backgrounding cancels active
capture; completed conversation history remains available after returning.

Use English-speaking Alex with Meta and Spanish-speaking Sofía with G2. Exchange
20 turns including names, prices, negation, corrections and café noise. Verify
both translation directions and host-only Spanish/English/pronunciation choices.
No voiceprint, diarization or automatic speaker attribution is claimed. Do not
mix the two glasses microphone streams. Compare capture sources only in a
separately consented attended test.

## Evidence to retain

Record the app, each physical display and timestamps for speech end and visible
translation. Label each recording as physical, simulator or browser. Verify
history scrollback, return-to-latest, disconnect of either display without losing
the conversation, stale button rejection, pending speech invalidation and stop.
Check whether switching to Even Hub interrupts updates and whether returning
recovers them. A successful local HTTP request does not prove optical delivery.

Keep the Meta multi-glasses guest-mode request as a draft. Mixed-manufacturer
success does not prove the Meta SDK supports multiple Meta pairs. Publication,
submission, deployment and installed-app replacement remain separate approvals.

## Pronunciation acceptance (new, not yet device verified)

Leave pronunciation off for the baseline. Enable it explicitly, finish microphone capture, then confirm a Spanish reply. Hear only the Spanish reply text in the host glasses/headphones; English gloss and written pronunciation must not be spoken. Navigation alone stays silent, and the G2 guest never receives private suggestions. Confirm both phone and band selection. Try Stop, disable, reset and Bluetooth disconnect mid-utterance; speech must stop without falling back to the phone speaker. Repeated selection replaces, rather than queues, speech. Try selecting during active capture: it should explain that capture must finish first. Verify the installed Spanish voice and actual iOS audio route; simulator tests cannot prove the Meta speaker route or acoustic privacy of open-ear glasses.

Registration still needs resolution of the Meta console HTTPS callback requirement (see META-REGISTRATION.md), a separately signed Borderless device build and trusted reachable relay. The native source retains Meta placeholders. Do not mistake simulator readiness for completion of those device prerequisites.
