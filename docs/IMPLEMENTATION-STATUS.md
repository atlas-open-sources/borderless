## 2026-11-03 — Public relay built, not yet deployed

Implemented `conversation_relay.hosted`: capacity 3 with a coded "busy" error, 60 s audio and 120 s wall clock per session, 8 translations per session, per-install (optional `install_id`) and per-IP hourly/daily limits, $3 daily cap, optional hosted total cap, kill switch (control file or env), health endpoint, counters-only JSON logs, SQLite state on a volume. The hosted ledger keeps the same $20 cap and is seeded with local committed + pending spend plus $1 headroom. `--behind-proxy` allows a plain non-loopback listener behind TLS termination. Deploy kit for AWS us-east-1 (t4g.nano, Caddy, Docker, SSM secrets, AASA, privacy page) in `deploy/`.

Tested: 130 Python tests pass (43 new for limits, IPv6 /64 buckets, install-id rotation, concurrent admission, kill switch, allowance seeding, coded errors, a real WebSocket health/unauthorized/keyless round trip and a subprocess start), also under Python 3.13. The release client key is plain config (it ships in the app), never the dev token; only META_API_KEY goes through the operator's secrets script. Not deployed: the AWS SSO session had expired and no other host sign-in existed. No paid request, no ledger change, no image built.

## 2026-11-02 — Physical phone-only Start failure reproduced

Implemented and installed: 12-second connection/handshake deadline, cancellation of stalled transport before microphone startup, prominent live status panel and actionable network/security errors. Glasses remain optional; tests hide previews and do not connect either manufacturer.

Tested: 18 native model tests passed on the physical iPhone 17 Pro Max, including new stalled-handshake regression (microphone never starts, transport closes, start state released). Signed device build succeeded. Attended UI test navigated Live → hide glasses previews → Start conversation → explicit consent → Start live capture. It failed the Listening acceptance assertion: the device displayed Cannot reach the translation service. Earlier runs corrected XCTest switch targeting; those are not product acceptance passes. The final physical failure and screenshot are in artifacts/2026-11-01/184237-codex-f641f670/PhoneConnection.xcresult and connection-images. Test is opt-in via TEST_RUNNER_BORDERLESS_ATTENDED_DEVICE=1 and stops capture after checking Listening.

Network evidence: relay PID 7010 listening on the Mac tailnet address:8766; phone shown on cellular in screenshot; phone tailnet ping timed out. Mac Tailscale also reported an intercepted captive-portal certificate for one relay region. Exact phone Tailscale state awaits user confirmation. Do not claim missing glasses caused this, or claim end-to-end speech now works. No provider calls or ledger increase: local committed $0.12163275, four existing pending reservations unchanged (not account-wide billing). No microphone audio was captured by the failed start.

Remaining: restore phone-to-private-service reachability, rerun attended capture and verify actual speech produces source + translated text on the phone without glasses, then physical displays. User asked to confirm Tailscale Connected on iPhone. No TestFlight work, deployment or submission.

## 2026-11-02 — Attended live service provisioned (supersedes manual setup blocker)

User paused all TestFlight/listing work and prioritized hardware. No listing, export/upload or submission performed. A local release archive exists from the preceding preparation only.

Started authenticated TLS speech relay bound only to this Mac's Tailscale address on port 8766. Uses a publicly trusted certificate for its existing tailnet hostname; no public tunnel, TLS bypass or provider key in the app. Debug-only provisioning copies the ignored .budget/device-service.json into the development build; only a separate app relay token is included. Release builds remove that resource and compile out its reader. This private development setup requires the phone's existing Tailscale connection and the Mac relay running; it is not a deployed public service.

Fixed actual startup failure: Path.open does not accept opener; token creation now uses built-in open with exclusive/private permissions. Added token creation/reuse/0600 regression. 87 Python tests pass. Invalid authentication over trusted WSS rejected without provider use. One synthetic WAV passed through that WSS endpoint, real Meta ASR/translation, two host replies, zero guest replies and completed shutdown. Evidence: artifacts/2026-11-01/181606-codex-45d38dfb/check_private_proxy.json. Local accounting increased from $0.1144165 to $0.12163275; four pending reservations unchanged, not account-wide spend.

Onboarding now names Meta Ray-Ban Display and Even G2 and one-of-each paired with this phone for dual-glasses use. Configured Live hides service fields and retains provisioned authentication across sheet dismissal. Two targeted native UI tests passed (onboarding and repeated Live sheet), without starting a microphone. Signed device build succeeded, provisioning matched the private service config without printing credentials, and devicectl confirmed installation and launch on the connected iPhone 17 Pro Max. Physical phone network, microphone and optical acceptance remain attended checks. Relay remains running for the user test (terminal session 67299); loopback site remains running on 8769.

## 2026-11-02 — Standalone product flow and submission desk

Implemented Demo/Live onboarding without upfront permission requests; Play demo labels; clear optional-preview toggle; visible per-device Connect controls; useful Settings; current and explicitly saved local conversation history; swipe-left history access. Saved text uses protected atomic storage excluded from backups. Mode switching offers save/discard/cancel. Microphone permission is deferred until live capture. Live service setup is visibly required rather than hiding the reason Start is disabled.

Language selection now allows any two distinct languages in the 25-language catalog and propagates the choice through native session, speech bias, translation and reply generation. Experimental pairs are labeled untested; recorded Demo remains English–Spanish. No new-language live API or optical rendering claim.

Fixed missing app version/build metadata required by Meta SDK; built simulator plist verifies Borderless 0.1.0 (2). Configuration errors are specific. This fixes a source defect, but physical registration still needs an attended check.

Local submission tracker: site/submission.html, served at http://127.0.0.1:8769/submission.html. Includes hackathon, beta, hardware and local Meta issue drafts. No vendor issues posted. App Store Connect and Cerebral Valley require user sign-in before portal completion; no beta upload or hackathon submission performed.

Tests: 86 Python, 22 Swift package and 3 site suites passed. Native model tests 17/17 and saved-history relaunch passed in Product-final.xcresult; onboarding/mode/preview passed in Product-ui.xcresult after correcting test locators; unsaved-mode protection and live setup passed in Mode-ui.xcresult. Changed the mode confirmation to an alert so Cancel is explicitly available on all layouts. Signed physical Debug build succeeded and devicectl confirmed installation and launch of Borderless 0.1.0 (2) on the connected iPhone 17 Pro Max. Simulator onboarding visually inspected. Evidence: artifacts/2026-11-01/181606-codex-45d38dfb. No paid requests, ledger changes or physical microphone capture. Physical Meta registration, simultaneous glasses output and actual microphone/audio routing remain unverified.

## 2026-11-02 — Connection buttons, G2 package and Meta Developer Mode

Implemented visible Connect/Disconnect controls under both glasses previews, inline Meta registration when required, and G2 instruction to open its microapp then return. G2 serving is still labelled connection-unverified. Rebuilt glasses-plugin/borderless-guest.ehpk: two tests, TypeScript, whitelist, Vite and official packaging passed. Package is local, not uploaded or store-approved.

Signed iPhone build passes after removing dummy Meta credentials for documented Developer Mode and adding required Bluetooth background mode. Registration docs corrected: production HTTPS/AASA is not the same as Developer Mode custom callback. Actual physical registration and output remain unverified.

Even deep-link research: official CLI documents QR opening of a LAN development URL, with no store listing prerequisite. No documented external link to launch a specific installed or development microapp found. Do not invent a URL scheme. Sources: https://hub.evenrealities.com/docs/cli/project and https://hub.evenrealities.com/docs/get-started/overview . No vendor message sent.

## 2026-11-02 — First signed physical iPhone install

**Native build verified:** Debug arm64 build succeeded with automatic development signing and team 599WAZ6282, explicitly overriding the project default CODE_SIGNING_ALLOWED=NO. Build log retained at artifacts/2026-11-01/180815-codex-ba1f9bda/device-build.log.

**Installed and launched:** devicectl confirmed installation and process launch of ai.atlascodes.skunkworks.borderless.rehearsal on the user-connected iPhone 17 Pro Max. This is development distribution, not TestFlight. No physical UI assertions, microphone capture or glasses acceptance have yet been performed.

**Current source verified:** language sheet is wired into the app; English–Spanish is the sole enabled pair. The 25 speech languages are disclosed separately as model capability, not working product pairs. MetaAppID remains 0 in project configuration; default relay is simulator loopback. Meta registration and trusted phone-reachable relay remain real blockers to live glasses/API acceptance, even though app installation now succeeds.

**Submission:** public deadline rechecked November 4, 21:00 Eastern / November 5, 10:00 Singapore. Cerebral Valley submission portal redirects to sign-in; exact required fields need authenticated inspection. No submission, deployment or TestFlight upload performed.

## 2026-11-02 — User-reference correction: simple cartoon restored

**Implemented:** supersedes the generated 3D illustration below. Restored simple flat SVG characters using the two user-supplied glasses photos: brown squared Meta frame with clear lens cutouts, circular outer details and one small lower-right schematic display cue; black round crown-panto G2 frame with grey hinge blocks, nose pads and green cues in both lenses. Speaking mouth/lean motion, pinch and ear-wave cues follow existing playback state. This is explanatory artwork, not an optical simulation.

**Tested:** scene-state, recorded-timing and voice-comparison Node suites pass. Browser verified muted playback and transcript updates, desktop frame appearance, one Meta/two G2 cue elements and 390px mobile layout without horizontal overflow. Mobile label spacing corrected after inspection. Screenshots retained in artifacts/2026-11-01/173118-codex-2050ceca. Browser viewport restored; local preview running on port 8769.

**Live API / native / hardware:** no new paid requests, native changes/builds, physical recording or deployment. Existing API recordings remain unchanged. This slice verifies website presentation only.

## 2026-11-02 — Rebuilt cartoon, confirmed personal frame colours

**Implemented:** replaced the entire SVG cartoon with a newly generated 3D cartoon café illustration, using the user-confirmed tortoiseshell Meta host and black Even G2 guest. Clear lenses, visible eyes, natural adult proportions, neural wristband, one shared phone. Simplified the scene stylesheet and retained captured-event bilingual bubbles, speaker/phase labels, waveform animation and optional pinch/ear-cue highlights. This is static character artwork with animated overlays, not lip-synced character video. Product likeness remains illustrative, not an exact CAD or ownership-shape match; removed the unconfirmed G2 A label.

**Tested:** three Node suites pass (scene state, replay timing including actual transcript chronology, voice comparison); module syntax passes. Browser: image loaded at native 1536 width, muted Play/Pause and scrub exercised, translated question preserved at 9.05 seconds, no console warnings/errors. Mobile 390px visually inspected, 320px and 390px show no horizontal overflow. Viewport reset afterwards. Screenshots and generation direction retained in artifacts/2026-11-01/084700-codex-4c3aec51; production asset site/assets/madrid-conversation.png. Local preview restarted to include new asset in its explicit allowlist.

**Boundaries:** built-in image generation used; no new speech/translation API calls, budget-ledger changes, native changes, physical recording, vendor messages or deployment. Official product pages researched online. Existing recorded API timing and simulator media retained.

## 2026-11-02 — Conversation experience and reviewed glasses illustration

**Implemented:** cohesive café/player/device presentation, bilingual speech bubbles driven by captured transcript events, mobile device layout, speaker motion, receiving-display cues and readable wearer labels. Host wears a chunky black Meta Ray-Ban Display illustration; guest wears the slimmer olive Even G2 A crown-panto illustration. Drawings reference official product photographs, not hardware rendering evidence. Claude CLI review completed using claude-opus-5-5; review findings informed this pass. Original question/reply recordings and optional pronunciation audition remain intact.

**Correctness:** seeking selects only captions already received for the current speaker; gaps retain the preceding segment. Host result state now says translation delivered rather than ready to reply. Scrubber duration initializes even when video metadata loaded before its listener. Earlier partial translations remain visible with a processing note until final results arrive.

**Tested:** replay-timing, conversation-scene and voice-comparison Node suites pass; site JavaScript syntax passes. Tests include actual Original/Azure transcript final-result timing and backward seeking. Desktop browser checked host translation, frame assignment, bubble wrapping and no console warnings/errors. Earlier layout checks covered 320/390 widths; final frame-pass mobile recheck was limited because browser viewport override remained at 949px after two attempts. Do not treat the misnamed mobile-refined.png as mobile evidence. Latest desktop evidence: artifacts/2026-11-01/082721-codex-1193c727/final-experience.png.

**Sources:** https://www.ray-ban.com/usa/electronics/0HX000001-META%20RAY-BAN%20DISPLAY-Black/815820026679 and https://www.evenrealities.com/en-GB/products/g2-a .

**Live API / native / hardware:** no new Meta/Azure calls, ledger changes, native build, device installation, physical recording or deployment in this slice. Captured API timing remains captured, not live requests during playback. Physical acceptance remains separate.

## 2026-11-01 — Measured replay timing and illustrated pronunciation audition

**Implemented:** website Original/Azure recordings now remove initial, inter-turn reading and final presentation padding while retaining all within-turn API event offsets. Azure replay is about 60 seconds instead of 87; original about 66 seconds. Connection setup is excluded; cuts round up to video frames. Playback is a captured API run, not fresh API requests. Original source recordings and native resources are preserved.

**Illustration:** animated two-person café scene follows speaking/waiting/results beside the phone and differently proportioned Meta/G2 recordings. A separate optional band → Spanish ear cue → learner speech sequence pauses the recorded API clock. It is explicitly an illustration, not physical routing evidence. Reduced motion supported.

**Live API verified:** two short Azure samples generated: native Spanish pronunciation and an English-voice IPA approximation of Spanish. Learner sample passed through Meta, which returned the imperfect transcript “CS mi primera primera vez me encanta.” Actual result is disclosed on the site. This is an audition, not a validated replacement for the main conversation. Native private pronunciation already exists and was not changed.

**Tested:** 81 Python tests and three Node suites pass; site JavaScript syntax passes. Browser verified Azure switching, seeking, synchronized muted playback (observed maximum video spread about 108 ms), optional sequence through host speaking, restart and Stop, and absence of console warnings/errors. Media requests support HTTP 206. Screenshot and test log retained in artifacts/2026-11-01/074513-codex-5fd370c4.

**Accounting:** project-local committed Meta ledger is $0.1144165, four pending reservations unchanged. Not account-wide billing. Existing Azure S0 resource reused; not claimed free. Credentials excluded from clients/logs.

**Native build / hardware:** no native source changes or new native build in this slice. Prior native results below remain separate. Actual glasses ear routing, band gestures and simultaneous physical displays still require hardware acceptance. No device install, unattended microphone recording, publication or deployment.

## 2026-11-01 — Azure voices through the full Meta pipeline

**Implemented and live API verified:** six Azure-generated speech files passed through the existing bounded Meta speech/translation/reply pipeline. 74 public events, seven recognized turns, 86.565 seconds. Meta split the opening greeting and Madrid question at the pause; these real results are retained. Both host Spanish recordings use the exact newly generated private reply choice. The English allergy/oat-milk detour produces Spanish translation. Assigned speaker roles and synthetic voices; no diarization or human-conversation claim.

**Native build and tests:** Azure.xcresult reports Passed, 18/18 (17 model checks and full timed native replay). 79 Python tests pass. Comparison-module checks pass. Existing AVAudioSession main-thread warning remains. Post-test simulator diagnostics stalled; only that owned collector was terminated after tests passed, and xcodebuild exited successfully.

**Website verified:** Original/Azure now selects separate phone, Meta and G2 recordings AND corresponding actual transcripts. Each selection restarts because provider timings differ. In-app browser verified selection, muted playback, pause, seek to the English detour, and original restoration. New recordings share the same native capture, start at Play (44.75-second source trim), and hold the final frame through the audio end. HTTP byte-range response 206. Both boxed API alternatives and bilingual displays visually inspected. Original recordings preserved.

**Accounting:** local committed Meta ledger moved from $0.09093975 to $0.1106205; four pending reservations unchanged. This is project-local accounting, not account-wide billing. Azure reused the existing S0 service, not claimed free. Credentials stayed out of clients and logs.

**Evidence:** artifacts/2026-11-01/013950-codex-d8a2bb4a contains provider output, generated files, selection audit, native result bundle, raw capture, test logs and comparison screenshot. Current native resources contain the Azure run. Website assets use azure-* names for this variant.

**Physical acceptance remaining:** actual simultaneous Meta/G2 delivery, connection lifecycle, band controls and private pronunciation routing. No physical microphone recording, installed-device replacement, publication or deployment in this run.

## 2026-10-30 — Azure / original voice comparison

Added a temporary website toggle for original system voices versus Azure neural voices. Azure access worked through the existing authenticated account; no new resource, keys stored, account settings changed or subscription created. Elvira speaks Spanish; Andrew Multilingual speaks both host languages. Six generated clips use the exact existing scripts and are aligned at their original turn start times. This is a disclosed voice audition: Azure audio has not been reprocessed through Meta, and the original native footage/API results are unchanged.

Verified in the in-app browser: Azure audio loaded and played silently with the phone (observed timing difference about 3ms), switching to original preserved position, pause stopped audio, reset returned to zero. Node regression checks cover switching, exclusivity, seek, pause/resume, mute, end and failure. PCM overlap checks pass. Audio HTTP range 206; module HTTP 200. No native changes or physical-device tests. Azure service was existing S0, so no claim that this used a free tier. Two incomplete uncompressed downloads failed; completed clips were reused and remaining synthesis succeeded using compressed responses. No new Meta requests or ledger modifications.

Kept generator, comparison module/tests, six source voice clips, generated audio and screenshot under artifacts/2026-10-29/235216-codex-08270d12; website audio at site/assets/azure-conversation.m4a. Browser left paused and muted at zero with Azure selected.

## 2026-10-30 — Selected Spanish speech and an unscripted English detour

**Implemented:** translation direction follows detected spoken language independently of wearer role. Host can read a Spanish option, then speak English later. Private selection never inserts a transcript. Added Say something else guidance and timed selection/free-speech cues. Both question and boxed bilingual alternatives remain on Meta; G2 receives bilingual conversation without private options.

**Live API verified:** six generated voice files passed through Meta ASR/translation/reply APIs. Both host Spanish inputs are exactly the preceding API option; normalized recognized text matches. The host's English milk-allergy/oat-milk question produces Spanish on G2. Synthetic voices and assigned roles, not human recording or diarization. One provider failure interrupted capture; checkpoint resume reused completed results and requested only unfinished turns. Local committed accounting is $0.09093975 with four pending reservations preserved, not account-wide spend.

**Tested:** 79 Python tests; 23 browser contracts plus scroll and bilingual render checks; package suite passed (including spoken-language switching); native Spoken.xcresult 18/18, including full 92.621-second recorded replay. Unsigned generic iPhone build succeeded. Xcode reports an AVAudioSession main-thread activation warning; this remains a performance follow-up. The post-test simulator diagnostics collector stalled and was terminated after all tests passed; xcodebuild exited successfully and the result bundle reports Passed.

**Media:** replaced all three website videos from the same native capture, trimmed 32.25 seconds, with the original source WAV on phone video. Posters and English-to-Spanish G2 frame visually inspected. Preview server restarted on localhost8769; video range response 206. Browser interaction recheck unavailable due to connector error in this session. Evidence retained in artifacts/2026-10-29/220539-codex-28d26b8d, including provider outputs, selection audit, tests, original capture and G2 detour image.

**Physical acceptance remaining:** actual Meta/G2 connection, simultaneous delivery, band navigation and private pronunciation audio routing. No physical microphone recording, device installation, deployment or publication performed.

## 2026-10-30 — Boxed bilingual Meta reply options

**Implemented:** additive shared GlassesScene/MetaScene cards carry title, meaning, stable action ID and focused state. The native Meta bridge sends actual SDK FlexBox containers with padding, Background.card and onTap through the existing stale-action lease. Each Spanish answer and English meaning forms one card; question and translation stay above both cards. Removed redundant bottom Reply buttons from the compact card layout. The focused card has a leading marker. No custom outline/focus-role API is claimed: SDK background material and physical rendering remain device acceptance. G2 receives no private cards. Browser rehearsal cards have stronger separation too.

**Verified:** Borderless package tests pass (5 XCTest, 17 active Swift Testing checks plus 2 opt-in skipped); native Cards.xcresult 17/17 including actual recorded API questions fitting both cards, focus changing without hiding either answer, and a full timed UI replay. Unsigned generic iPhone build succeeds against the actual DAT SDK. Shared Meta layout/card/source-compatibility tests pass 15/15 and GlassesSceneKit passes 11/11; full MetaDisplayKit suite did not finish within the bounded run, so no full-suite pass claim. No new paid API calls.

**Media:** replaced all three site recordings and posters from the same native cards-raw.mp4 capture, trimmed 14.4 seconds and paired with the existing source WAV. Visual inspection confirms both boxed answers and question together; media range requests return 206. Exact final Meta image retained as artifacts/2026-10-29/183425-codex-c20822cf/meta-cards.png. The approximate renderer is not physical glasses proof. No publication or device installation.

## 2026-10-30 — Bilingual conversation retained with complete alternatives

**User correction implemented:** original speech and translation on both wearer views, including their own turns. Meta latest view keeps the bilingual question and both Spanish reply alternatives with English meanings together. Focus changes emphasis, not which response is visible. No written phonetics in native/browser/static examples. Optional spoken pronunciation remains a separate default-off setting. G2 receives both languages and no private assistance. Long unbounded content remains paginated without discarding text; ordinary recorded questions and both answers fit in one Meta panel.

**Provider behavior:** prompt now requires two independent complete answers to the same whole utterance, including multi-clause questions, and no pronunciation field. Parser accepts text/gloss and removes legacy phonetics. Four new generated voice files passed through real Meta ASR/translation/replies; first options both answer wellbeing plus first visit (yes/no). 49 events, 48.494 seconds; retained evidence under artifacts/2026-10-29/181457-codex-dd174462. No private recording or physical microphone used. Local committed total $0.073135, delta $0.0121555, three reservations unchanged; not account-wide billing.

**Verified:** 77 Python tests; 23 browser contracts plus scroll and bilingual markup checks; 5 viewport XCTest and 17 active shared-package tests (2 live opt-in skipped). Native Final.xcresult passes 17/17, including both actual provider question/reply sets fitting together, G2 bilingual privacy, 15 existing model checks and full recorded replay. Earlier headless recordings were rejected. A runtime stale-preview defect was corrected: recorded events publish display snapshots directly, and preview images derive from the current scene without a separate task/state cache. DisplayUpdate.xcresult passes a full timed replay asserting the original question and BOTH actual provider answers reach the Meta preview. Final generic iPhone build passes unsigned. Physical glasses remain untested.

**Preview routing:** another unrelated project now owns 8765. Borderless demo moved to 8764 and site links updated; unrelated server left untouched. Website remains 8769.

**Updated media:** site/assets/{phone,meta,g2}-render.mp4 and posters replaced from replay-corrected.mp4. All three use the same 9.0-second trim and 48.494-second timeline; phone includes source WAV, glasses crops are silent. Native frames and final posters visually inspected: bilingual question plus both answers on Meta, bilingual text and no suggestions on G2. HTTP range request returns 206. Final browser interaction verification was unavailable because the browser connector returned “browser.user is unavailable” on both existing and reacquired tabs; no browser screenshot or hardware claim. Native screenshot evidence is question-corrected.png and the final posters.

## 2026-10-30 — Real audio pipeline replay and optional pronunciation

**Implemented:** four generated English/Spanish voice files streamed through actual Meta ASR and translation/reply APIs. Archived47 partial/final events across49.876 seconds; native default Play replays actual results/timing and source audio. Website synchronizes phone plus correct1:1 Meta and2:1 G2 shared-renderer crops, progressive source/translation captions, pause/seek and optional sound (muted by default). Voices are explicitly synthetic; roles assigned, not diarized. No private Local AI Cat data used.

**Pronunciation:** default-off Rehearsal tools toggle. Selected reply text only, local es-ES voice, phone/band confirmation. Personal headphone/Bluetooth output required before and after audio-session activation; speaker/AirPlay refused. Stops on route/interruption/reset/disable/background; start capture/replay stops prior speech. Active capture or replay refuses pronunciation with guidance. This is implemented policy, not proof of actual optical/audio hardware behavior.

**Tested:**76 Python tests,15 native model tests pass, including fake pronunciation tests for off/default, selection/navigation, invalid index, lifecycle cancellation and personal-route policy. Browser confirmed all three videos seek to12 seconds with matching real captions; playback/audio-track, pause and mute checked. Native recorded replay UI test passed 1/1 in AudioReplay.xcresult; post-test simctl diagnostic collection hung and was interrupted (outer exit 75), so retain that qualification. Earlier Audio.xcresult skipped and Pronunciation.xcresult compile-failed are superseded, not passing evidence. Swift 6 delegate isolation error fixed; PronunciationFixed.xcresult passes 15/15. PronunciationUI.xcresult passes 1/1: normal launch uses recorded-audio mode, pronunciation setting is discoverable and no speech starts. Xcode notes synchronous AVAudioSession activation can affect UI responsiveness; physical routing/latency remain acceptance checks.

**Native build verified:** simulator tests built the new app; unsigned generic iPhone build passed. Not signed, installed on physical phone, or shipped.

**Live API verified:** real ASR/translation/reply results for all four turns; two guest turns get host-private Spanish replies with English meanings/pronunciation, host turns get none. Delta $0.0101645; local committed $0.0609795; prior reservations retained. Local ledger is not account-wide billing. Playback requires no new API calls.

**Physical remaining:** Meta callback registration/credentials, separate signed installation, trusted reachable relay and attended dual-glasses/band/audio-route acceptance. See BORDERLESS-HANDOFF.md and ONE-PHONE-ATTENDED-RUNBOOK.md. No physical microphone, deployment, publication or installed-app replacement.

Evidence: artifacts/2026-10-29/111657-codex-9069a794 including provider-evidence.json, audio-conversation.json/WAV, replay-raw.mp4, site-audio.png, xcresults and build logs. Final website assets are site/assets/{phone,meta,g2}-render.mp4. Glasses footage is cropped from native shared renderers, not vendor emulator or lens recordings.

## 2026-10-30 — Three synchronized simulator recordings

Replaced the site’s fictional glasses cards with actual native shared-renderer footage from the same iOS simulator recording: square Meta left, phone center, wide 2:1 G2 right. One Play/Pause control and scrubber drive all three; drift correction keeps followers aligned. Mobile stacks phone over the two correctly proportioned glasses. Removed leftover visible host name in both display projection paths and captured again. Old film section now uses the fresh phone recording too.

Verified: native full rehearsal UI test passed twice (including after label fix); inspected footage and posters; JS syntax and synthetic play/pause/seek/drift/end checks pass; live HTTP video ranges return 206. Browser verified all three at exactly 10 seconds after scrubbing and display dimensions square versus 2:1. Clips are crops of shared renderers inside the phone simulator, not separate vendor emulator or hardware recordings. Evidence and raw source kept in artifacts/2026-10-29/110537-codex-0fa165c5. Final assets site/assets/{phone,meta,g2}-render.mp4 and posters.

## 2026-10-30 — Visual polish and explicit language availability

**Implemented:** paper/ink website refinement, blue Meta and green G2 display concepts, private reply cue synchronized only to Meta, responsive layout and English–Spanish availability section. Native app has a visible pair control and language availability sheet, clearer preview history labels, larger rendered displays and refined transcript/playback surfaces. English ↔ Spanish remains the only enabled pair; the documented 25-language ASR list is informational, not 25 supported product languages. See LANGUAGE-CAPABILITIES.md.

**Tested / native build verified:** simulator build and 3/3 targeted UI tests passed (language sheet, immediate Play/standalone history, physical-render pagination). Native screenshot inspected. Website JS syntax, static asset/anchor and synthetic selection checks passed; parent browser confirmed selected reply updates Meta and leaves G2 unchanged. Mobile viewport 390px has no horizontal overflow; desktop/mobile screenshots visually inspected. Evidence: artifacts/2026-10-29/104336-codex-02d99367/Visual.xcresult and screenshots, site.png, native.log.

**Live API verified:** no new API calls this pass. Prior generated-speech verification is unchanged. **Physical acceptance:** remains outstanding; no hardware or release claim. Existing site video is explicitly labeled as an earlier app layout. Site available locally at http://127.0.0.1:8769/.

## Visible native glasses screens — 2026-10-29

Meta and G2 actual shared-renderer previews now appear side by side at the top by default, with compact independent scrollable histories below. The glasses toggle still enables standalone phone mode. Pagination controls remain expandable. Simulator build and targeted UI test passed: both screen accessibility elements exist before opening controls; paging remains functional. Screenshot inspected at artifacts/2026-10-29/042913-codex-4af4c7ee/top-previews/B8081E75-68B4-49A7-8FE0-7379910E507B.png. Native change only; existing website video remains the previous recording. No hardware claim.

## Borderless folder and package unification — 2026-10-29

Moved project from `meta-hackathon-skunkworks` to `borderless`. Renamed native app/Xcode project/scheme and shared Swift modules from Elsewhere to Borderless, including source/test folders and imports. Updated source, manifests, build environment names, docs and callback/bundle IDs; regenerated Xcode project and G2 package. Canonical iOS bundle is `ai.atlascodes.skunkworks.borderless.rehearsal`; callback is `borderless-rehearsal://`; G2 ID is `ai.atlascodes.borderless.guest`. Meta console registration still needs its callback resolution; no console mutation in this rename.

Verified: 75 Python tests, 23 browser contract checks plus scroll-follow checks, 2 G2 tests/type-check/production pack, unsigned generic iPhone build, and renamed iOS suite (18 passed, 1 opt-in relay test skipped). Website/demo/review HTTP endpoints respond at ports 8769/8765/8768 from the new folder. Simulator renamed Borderless Rehearsal. Credentials and budget ledger retained without reading their contents. Historical artifacts/sessions/caches retained; their embedded old paths/names are historical rather than new build instructions. No publication or physical hardware verification. Evidence: `artifacts/2026-10-29/042913-codex-4af4c7ee/`.

## Anonymous demo and seekable recording — 2026-10-29

Replaced visible host name with You in browser and native demos. Rebuilt simulator; full one-click native rehearsal UI test passed (1/1); browser session benchmark passed 23/23. Re-recorded native rehearsal, removed home screen and launch fade, inspected opening frame. Published locally to site/review assets: 29-second H.264 fast-start MP4 with one-second keyframes. Both preview servers now support tested HTTP byte ranges; restarted and verified live 206 responses. Browser UI inspection unavailable because local browser use is disabled in Work settings; drag-to-seek not manually exercised. Evidence: artifacts/2026-10-29/001856-codex-f99698f5.

## Signing confirmation — 2026-10-29

User approved Ghost Runner team `599WAZ6282`; native project configured accordingly. Meta project exists, but iOS configuration remains unsaved: current console rejects custom-scheme and empty universal links. Existing Ghost Runner registration uses `ghostrunner://` and the same team (read-only verified). See `docs/META-REGISTRATION.md`. Unsigned generic iPhone build passed after project regeneration (existing orientation warning only). This does not verify provisioning or physical registration. No credentials, permissions, distribution or installed apps changed.

## Borderless identity, G2 package and Meta project — 2026-10-29 Shanghai

**Implemented:** Atlas-inspired paper/ink website at localhost8769, coastline-only globe icon (no political boundaries), native app icon/header/colors and G2 branding. G2 remains a thin shared-package consumer with explicit microphone disabled. Added reproducible official .ehpk packaging, two profile/privacy tests and patched Vite7.3.7; full dependency audit now zero known vulnerabilities. Native and shared internal IDs retained.

**Tested:** G2 tests, TypeScript, whitelist, production build and packaging pass. Candidate74249bytes SHA256 e2f7b3db4f455d10500e2d2ffdfac4332fc1fdfaebb1f872bc99bf7a0f57f913. Website desktop/390px mobile, interactions, reduced-motion support and static-server path protections checked. Branded iOS suite13 model +5 active UI pass,1 opt-in relay UI test skipped. Simulator and unsigned generic iPhone builds pass. Screenshot review identified prominent-button foreground contrast; corrected inherited foreground styling, targeted immediate-play/standalone UI test passes and exported screenshot confirms light text on the dark button. Final unsigned iPhone rebuild passes. An initial misnamed test filter selected no cases and is not counted as evidence.

**Registration:** Borderless project 1142963328181308 created in our existing Meta developer organization. iOS team/configuration pending; no device permissions enabled or distribution published. See META-REGISTRATION.md. API credentials not copied to clients.

**Established hardware evidence:** user explicitly confirms Ghost Runner already tests/verifies the Even Hub companion lifecycle. Borderless needs its own matching-package/content check, not a new architecture proof. Runbook and presentation corrected accordingly.

**Artifacts:** artifacts/2026-10-28/215249-codex-9ba874ac contains G2 package, build/tests, xcresults, screenshots and cropped registration evidence. New site/brand sources retained; site server8769. No physical installation, microphone capture, website deployment, publication or submission.

## Local review presentation — 2026-10-29

**Implemented:** separate review/ presentation at http://127.0.0.1:8768, native simulator video, fitted-display/standalone screenshots, embedded original browser rehearsal, architecture and evidence boundaries, nine editable expectation-versus-reality hardware checks with browser-local persistence and JSON export. Original demo preserved. Server loopback-only with explicit asset allowlist.

**Tested:** browser renders presentation and embedded rehearsal; video readyState4, duration33.466767s, no media error. Notes survive reload; temporary UI-test note cleared. JavaScript syntax passes. Root/script/video return200; .env, path traversal, encoded traversal and server source return404. Screenshot in artifacts/2026-10-28/201327-codex-941691bc/review-page.png. Review server tool session96942.

**Live API/native build:** no new provider calls or native changes this slice; preceding verified receipts remain applicable.

**Registration/hardware:** Meta managed-account sign-in form opened and retained for user. Registration not submitted; waiting for user sign-in. Own signing, physical-phone relay setup and attended physical acceptance remain. No physical microphone, deployment, publication or submission.

## Resumed live verification and readiness fix — 2026-10-29 09:50 Shanghai

**Authorization:** user explicitly resumed work after the former overnight cutoff and confirmed continuing under the existing$20 allowance. No repeat budget approval gate. Old blocked/approval-pending entries below are historical; scheduled overnight automation remains paused because its window expired.

**Live API verified:** synthetic stored English audio passed real Meta ASR→translation→host/guest delivery with clean completion. Synthetic Spanish audio passed the same path with two host-only Spanish replies, English meanings and pronunciation, and zero guest suggestions. Actual Swift RelayClient then passed generated Spanish PCM through real SessionServer→Meta ASR→Meta translation and back through native wire decoding, verifying partials, both final recipients and completed/stopped. No physical microphone or speaker playback.

**Bug found and fixed:** first native live attempt failed because pipeline emitted started before provider acknowledgment. Client audio could fill the eight-frame queue during handshake. SpeechTransport now invokes a bounded readiness callback after provider acknowledgment; pipeline emits started from that callback. A delayed-provider composed regression failed before the change and passes afterward. One post-fix native retry succeeded. Failed charge remains reserved; no blind retry loop.

**Tests/build:**74 Python tests pass after fix. Full iOS suite passes13 model plus6 UI tests, including actual20-second independent scroll resume, complete one-click replay and native local-network UI. Core/display suite passes18 active Swift Testing plus4 viewport XCTest cases; added opt-in live native test separately passes. Audio4, G2 transport/privacy2, Meta policy4 tests pass. Browser23 contracts plus follow checks pass; G2 plugin typecheck/whitelist/build passes. Final unsigned generic iPhone build passes. Exported UI screenshots inspected. Backend readiness change does not alter the built native binary.

**Deliverable:** `artifacts/2026-10-28/184252-codex-7096c4dc/Borderless-Simulator.zip` contains tested simulator app, SHA256 `0d6bd443812375907f824b5b67c73d5354f15a28b8ee1523164429ca1986f539`. App launched on dedicated simulator5C73ACF2-4780-4AE0-B4CB-AC42BC270608. It is not an iPhone IPA or App Store distribution.

**Accounting:** local committed plus reserved$0.050815; remaining$19.949185; three retained reservations; not halted. This run added$0.00698525 including its failed attempt. These are conservative project-local amounts, not account-wide Meta billing.

**Evidence:** same artifact directory contains live-pipeline.json, live-pipeline-spanish.json, native-live-receipt.json, native-live-test.log, retained native-live-before-fix files, readiness-red/green logs, FullAppTests.xcresult, all package/browser/plugin logs and screenshots. Canary scripts retained in corresponding scratch directory; no secrets embedded. Browser server restored at8765 (session84568); synthetic fixture server at8766 (session52655). No paid server left running.

**Physical-only remaining:** own signing and Meta developer registration, trusted physical-phone relay endpoint, attended phone microphone/audio-route testing, dual pairing/Even Hub continuity, real band input, optical output and20-turn/30-minute session. No claim of physical acceptance or shipment. No deployment, submission, publication or shipping-app replacement.

## Goal blocked after repeated input-gate checks

Three consecutive goal turns found the same unresolved input gate: permission for the post-fix paid synthetic test under the execution plan's ambiguous-usage stop rule, plus own signing/Meta registration and attended physical acceptance. No approval arrived. Scheduled automation is confirmed PAUSED. Goal is being marked blocked, not complete. Existing software, test logs, simulator video/screenshots and BORDERLESS-HANDOFF.md are retained. No additional paid request, microphone capture or ledger mutation occurred.

## Verification audit and input gate — 2026-10-29 03:58 Shanghai

**Audit:** consolidated requirement-by-requirement evidence and outstanding gates in BORDERLESS-HANDOFF.md. Corrected the execution plan's stale Mandarin baseline to approved English/Spanish and the draft Meta request to distinguish original Ghost Runner input handling from implemented Borderless experimental navigation. No external message sent.

**Accounting checked:** local committed plus reserved$0.04382975, remaining$19.95617025, two retained reservations, not halted. This is not account-wide usage. No paid call or ledger mutation. Existing plan explicitly stops paid tests on ambiguous usage; user asked whether to allow one post-fix synthetic end-to-end call capped at$0.05 within existing$20. Answer pending, no implicit approval.

**Blocker:** live provider verification awaits that answer. Physical acceptance needs own signing/Meta registration, trusted phone relay setup and attended devices. No new software failure found; full goal remains incomplete. Scheduled automation is being paused under the requested concrete-input-blocker rule, ahead of original22:57UTC deadline. Goal remains active pending blocked-audit threshold or renewed input.

**Evidence retained:** full build/test/video/screenshot receipts and consolidated handoff. No physical mic, publication, deployment or installed-app replacement.

## Simulator UI through the real local relay — 2026-10-29 03:56 Shanghai

**Implemented:** app's synthetic network rehearsal now waits for started before sending its two zero bytes, consumes provisional events, and requires successful completion before stopped. This closes a discrepancy with live capture. Native/voice READMEs now describe current integration and opt-in benchmark invocation.

**Tested:** opt-in XCUITest opens Rehearsal tools, selects Test local fixture relay, verifies all five network-delivered turns, and selects a private host reply while guest has no assistance. Test executed (not skipped), passed in14.04seconds. Screenshot exported and visually inspected: blue host/phone selection agrees, green guest retains conversation only, status confirms5 turns. This is synthetic local-network data, not a microphone or provider result.

**Native build verified:** simulator test/build and final unsigned generic iPhone build passed. No physical installation or signing claim.

**Evidence:** `artifacts/2026-10-28/125417-codex-8d69fb4f/RelayUITests.xcresult`, `relay-ui-tests.log`, `device-build.log`, and `screenshots/D1CD28C0-E6A4-4FE9-A051-267A90162060.png`. Fixture service remains tool session95371 on8766. Browser unchanged.

**Live API/hardware:** no additional provider requests, ledger changes, microphone activity or physical tests. Previous unresolved provider shutdown and attended hardware gates remain. Goal active until original22:57UTC deadline.

## Native provisional-event wire benchmark — 2026-10-29 03:55 Shanghai

**Implemented/tested:** synthetic fixture service now emits recipient-specific pending source events before each ready translation. Opt-in real Swift WebSocket test asserts ten pending events, matching per-audience turn IDs, five host/five guest final turns, empty provisional translation/replies, guest privacy, completed and stopped ordering. All18 Swift Testing cases (including network benchmark) and four viewport XCTest cases pass. All73 Python tests pass.

**Evidence:** `artifacts/2026-10-28/125303-codex-1e7de006/native-wire-tests.log` and `python-tests.log`. Fixture service restarted from current source on127.0.0.1:8766, tool session95371. This local synthetic service cannot call providers; verify its handle before reuse.

**Native build/live API/hardware:** production native source unchanged; preceding final unsigned iPhone build remains applicable. No new paid calls, ledger mutations, microphone capture or physical acceptance. Network fixture test complements composed real-pipeline Python tests; it is not a live-provider result. Goal remains active.

## Provisional speech and iPhone compilation — 2026-10-29 03:54 Shanghai

**Implemented:** relay emits bounded provisional source text to both recipients before translation, with no replies or translation fields populated. Native codec, shared session, phone transcript and both display projections consume these events. A slow older translation preserves newer provisional speech. Silent completion clears the blank Listening placeholder; completion with unfinished actual speech fails rather than silently discarding it. Pending speech invalidates host reply actions.

**Tested:** 73 Python tests pass, including composed loopback partial delivery, duplicate/revision guards and silence. Shared Swift package passes four viewport XCTest cases and17 active Swift Testing cases (one opt-in network test skipped). Full simulator run passes12 model and five UI tests; subsequent final model run passes13 tests including silent completion. UI coverage includes one-click full rehearsal, private host selection, standalone mode, independent20-second scroll resume and fitted page controls.

**Native build verified:** final unsigned generic iPhone build succeeds after all partial/silence changes. This proves device compilation only, not signing, physical installation or pairing. Stable simulator build/test passes. Browser code unchanged.

**Evidence:** `artifacts/2026-10-28/124527-codex-4ec6350b/` contains `PartialTests.xcresult`, `FinalModelTests.xcresult`, `app-partial-tests.log`, `final-model-tests.log`, `final-core-tests.log` and `final-device-build.log`. Python receipt: `artifacts/2026-10-28/120649-codex-587ce187/partial-python-tests.log`.

**Live API verified:** no new paid request; prior ASR transcription and text translation evidence remains distinct from unverified post-fix live shutdown. Ledger untouched this slice. No microphone activated.

**Remaining:** native-to-provider end-to-end verification, trusted physical-phone relay setup, own signing/Meta registration and attended two-glasses, band, audio-route and optical acceptance. Meta guest-mode request remains draft. Goal active within original22:57UTC deadline; no deployment, publication or submission.

## Native rehearsal recording — 2026-10-29 03:45 Shanghai

**Implemented/tested:** added full one-click XCUITest: Play automatically advances all five turns to Replay, then host privately chooses a reply while guest remains suggestion-free. Test passed twice. Prior15-test app suite remains separate evidence; this run exercised the new full-replay case only.

**Deliverable:** `artifacts/2026-10-28/124041-codex-5e31196f/borderless-simulated-rehearsal.mp4`,33.47seconds,720px wide. Raw39.47second simulator capture, screenshots, contact sheet, build/test logs and two xcresults retained alongside its README. Visually inspected captured mid-replay and completed-selection screenshots and video contact sheet. No hardware or live model footage is implied.

**Tool boundary:** XcodeBuildMCP UI hierarchy failed due missing SimulatorKit framework; XCUITest drove the UI successfully. Its recorder claimed start but produced no file; one bounded retry via Apple simctl succeeded and stopped. No recording process remains owned by this task.

**Native build:** stable build-for-testing succeeded; dedicated Borderless simulator only. No shipping installed app replaced. Browser unchanged.

**Live API/hardware:** no paid request or microphone activation. Physical pairing, band events, optical evidence and live API shutdown remain outstanding. Goal active until22:57UTC.

## Composed speech-to-recipient loopback verification — 2026-10-29 03:40 Shanghai

**Tested:** added three integration tests using actual loopback WebSockets, SessionServer, SpeechConversation, SpeechTransport and ASR parser. Synthetic PCM traverses the real capture transport into normalized finals, translation prompting and host/guest projections. Tests exercise two sequential language directions with source-only context, exact event ordering, guest reply exclusion, trailing stable transcript after speechComplete, ledger settlement, model failure sanitization and explicit Stop during blocked translation. Stop cancels the translator and delivers no late reply; all owners release and the session lock clears.

**Evidence:** all67 Python tests pass. `tests/test_composed_session.py`; `artifacts/2026-10-28/123848-codex-3918cf0e/python-tests.log`. These tests replace only the external provider socket, model response and accounting store with controlled synthetic implementations. They do not use the precomputed browser fixture pipeline.

**Implemented:** production source unchanged this slice. The stronger integration checks found no additional failure.

**Live API verified:** none added; synthetic provider responses do not verify current Meta entitlement, model quality or clean live shutdown. No credentials accessed, real ledger modified or microphone used.

**Native build / hardware:** prior15-test native result unchanged; this is backend composed integration, not native-to-live-provider or physical glasses acceptance. Goal active until22:57UTC.

## Experimental band navigation and companion handoff — 2026-10-29 03:39 Shanghai

**Implemented:** Meta adapter offers explicit neural-band navigation on its existing session, behind `BORDERLESS_EXPERIMENTAL_INPUTS=1`. Stable builds exclude MWDATInputs and expose unavailable status. Experimental builds request neuralBand only, with bounded activation, lifecycle/identity guards, timestamp duplicate rejection and cleanup. App maps up/down to private reply focus (history when no replies), left/right to host history, select to private cue, back to dismiss/latest. G2 has no assistance. Backgrounding disables band inputs and cancels active capture, while retaining already completed live history.

**Tested/native build verified:** stable and experimental adapter simulator builds pass, four policy/action tests pass. Final integrated experimental app test run passes all15 tests (11 model, four UI). Shared package passes four viewport tests and14 active Swift tests; one network test skipped. Browser23 contracts and follow-policy checks pass. First UI run exposed a test synchronization race: Latest disappears before scroll animation completes. Test now waits up to3seconds for the reply to be hittable; final timed idle-resume test passed in35seconds. No product follow timing was weakened.

**Evidence:** `artifacts/2026-10-28/123244-codex-969b4c45/BandFinalTests.xcresult`, `app-final-tests.log`, `core-tests.log`, `browser-contracts.log`; earlier failing `BandTests.xcresult` retained. Adapter logs: `artifacts/2026-10-28/120649-codex-587ce187/navigation-{stable-build,experimental-build,policy-tests}.log`. Experimental app build log includes actual MWDATInputs dependency. Stable adapter log excludes it.

**Source/lifecycle finding:** shared Even plugin intentionally keeps its frame executor polling while its phone page is hidden. Intended flow is enable companion, open plugin in Even Hub, return to foreground Borderless. This is source evidence, not proof of iOS/Even Hub background continuity. See ONE-PHONE-ATTENDED-RUNBOOK.md. No fake keepalive or Live Activity introduced.

**Live API / hardware:** no new provider call, recording, registration or input activation. Physical band events, optical output, dual pairing, secure phone relay and post-fix live API shutdown remain unverified. Goal remains active until22:57UTC.

## Monotonic pending speech revisions — 2026-10-29 03:32 Shanghai

**Implemented:** shared native conversation rejects older or duplicate partial revisions and finals older than the current partial. A final at the current revision is accepted. Rejected events leave pending text, history and reply-action generation unchanged.

**Tested:** new regression first failed on four assertions, then passed after the guard. Complete package run passes four viewport XCTest cases and fourteen active Swift Testing cases (one network opt-in skipped). Integrated iOS simulator app build succeeded. Receipts: `artifacts/2026-10-28/123029-codex-098d598e/revision-red.log`, `revision-green.log`, `app-build.log`.

**Live API / hardware:** no provider or microphone activity; unchanged prior evidence. No new physical acceptance claim. Browser preserved. Remaining integration work and original22:57UTC deadline remain active.

## Fitted physical-display paging — 2026-10-29 03:27 Shanghai

**Implemented:** new reusable ConversationViewport builds complete retained-history pages using shared G2 firmware widths/rows and Meta font/layout metrics. Long source/translation and host reply text, meaning and pronunciation remain accessible across pages. Only current host reply pages carry actions; focused/selected reply is the default last page. Independent per-display Previous/Next/Latest controls resume after20 idle seconds. Physical render panels and actual adapter output use these same pages; scrolling transcript previews remain continuous.

**Responsiveness/lifecycle:** page computation runs off the main actor with one worker and only the latest pending snapshot. Immutable GuestProjection avoids repeating guest layout at publish time and excludes host assistance by construction. Reset rejects in-flight layout results. Same-count transcript revisions now trigger UI refresh. Starting capture sets pending Listening state immediately, invalidating prior reply actions.

**Tested/native build verified:** all13 iOS app tests pass (nine model, four UI), including actual20-second transcript resume and fitted-render page controls. Four viewport XCTest cases and13 active shared Swift tests pass (one opt-in wire test skipped); two G2 tests including actual loopback delivery pass. Plugin TypeScript/whitelist/Vite build passes with Borderless branding. Long multilingual source/reply content reconstruction and actual renderer bounds have explicit assertions. Stress timings justify off-main layout; they are local debug measurements, not physical latency claims.

**Evidence:** `artifacts/2026-10-28/122035-codex-4893f2d1/DisplayTests.xcresult`, `app-tests.log`, `viewport-tests.log`, `g2-tests.log`, `plugin-build.log`, exported screenshots. Visually inspected `screenshots/10C104A1-3F8B-44B3-BDEE-B4DA821C5F08.png`: actual shared Meta renderer shows Spanish, English meaning, pronunciation and two private action buttons within bounds. Expanded diagnostic panel reduces phone transcript height; default remains collapsed.

**Live API verified:** unchanged; no paid request or microphone activity.

**Remaining:** raw band input and on-glasses history input, iOS foreground/background coexistence with Even Hub, trusted phone relay provisioning and attended dual-pairing/mic/optical acceptance. Shared renderer geometry is not firmware/optical verification; unsupported G2 glyphs remain a font limitation. Goal active until22:57UTC.

## Bounded cross-capture conversation context — 2026-10-29 03:18 Shanghai

**Implemented:** native app carries recent spoken source text into each new live capture, at most six turns and 6,000 Unicode scalars total (2,000 per turn). No translations, private reply ideas or pronunciation cues are included. Reset/Stop clears the source history. Server independently validates exact speaker/source entries before pipeline creation; seed context is combined with current utterances under the same bounds and cleared on stop. Handshake now allows32KB while individual PCM frames remain4,800 bytes. Fixture startup now acknowledges before waiting for audio, matching the real client's readiness gate.

**Tested:** all64 Python tests pass, including oversized/invalid context before factory and real loopback larger handshakes; native shared suite passes, including context/privacy limits. Seven iOS app model tests pass, including two consecutive captures carrying spoken context and reset clearing it. Updated native WebSocket test with context waits for started before sending PCM and receives five host/five guest turns successfully from the refreshed fixture server.

**Native build verified:** `artifacts/2026-10-28/121558-codex-4e10dad6/ContextTests.xcresult`, `app-tests.log`, `native-tests.log`, `context-wire-roundtrip.log`. Backend evidence: `artifacts/2026-10-28/120649-codex-587ce187/context-python-tests.log`. Synthetic fixture server restarted under tool session6980 on8766; previous54392 was stopped. Browser8765 unchanged.

**Live API verified:** no calls added; no microphone activated. Semantic quality of cross-capture context remains unmeasured against live models.

**Remaining:** fitted physical history/reply viewport and raw band navigation; trusted TLS phone environment and hardware acceptance; post-fix live API clean shutdown. Explicit speaker selection remains the controlled baseline, not diarization. Goal active until22:57UTC.

## Capture lifecycle and configurable secure relay — 2026-10-29 03:14 Shanghai

**Implemented:** native capture now injects small microphone/relay interfaces, with unchanged real defaults. Capture sheet accepts a validated relay endpoint: fixed simulator loopback or secure WSS, no embedded credentials/query/fragment, no HTTP redirects. Server defaults to loopback but supports explicit TLS certificate/key and IP bind for attended phone setup; non-loopback without TLS is rejected. No listener, certificate, tunnel or deployment was created.

**Tested:** six native app model tests pass in iOS simulator: consent/token gates do not request permission; successful capture retains host-private replies; explicit Stop cancels both directions and rejects queued/late data; failure closes and clears; old capture cleanup cannot mutate or stop the next capture; fixture selection remains private. Shared native package suite passes with the new endpoint validation test, and the opt-in real WebSocket fixture round trip passes against the existing local synthetic server. All 56 Python tests pass, including TLS configuration validation. No mic or provider traffic.

**Native build verified:** integrated app builds with updated endpoint field, injected adapters and real audio/Meta/G2 dependencies. `artifacts/2026-10-28/121122-codex-e8e6f9d8/CaptureTests.xcresult`, `capture-tests.log`, `native-tests.log`, `wire-roundtrip.log`, `python-tests.log`. Earlier three UI acceptance scenarios remain passed from the prior slice; this run tested models only.

**Live API verified:** unchanged. No additional spend, credentials read into output, or account-wide billing observation.

**Remaining:** a real trusted TLS environment and phone reachability are not provisioned; cross-capture translation context, fitted physical display history and raw band navigation are still open. Endpoint validation/build is not a TLS handshake/device acceptance claim. Physical mic/pairing/optical acceptance remains attended. Goal active until22:57UTC.

## Borderless capture integration and timed UI acceptance — 2026-10-29 03:10 Shanghai

**Implemented:** native app composes BorderlessAudio with the reusable relay client behind explicit local token, participant selection and both-person consent. Permission and microphone start occur only after the user starts capture; the relay must acknowledge readiness before audio capture. Bounded capture, Finish utterance versus Stop and clear, cancellation/reset/background cleanup and successful result retention are wired. Default Play remains synthetic. Fixed Swift task-group isolation compiler failure using extracted actor-isolated methods; no unchecked Sendable workaround. Starting fixture advancement after live history resets that history.

**Tested/native build verified:** integrated iOS simulator app build and all five tests pass: two model tests (private selection and capture guards), three UI tests (immediate Play/standalone/reset, host-only band selection without sending, independent history detach/20-second idle resume/Latest). The timed history test ran 33.467 seconds and verified final reply visibility after resume. Screenshots exported and the final history screenshot visually inspected, showing Borderless branding and both participant surfaces. Initial integration compile and test-query compile errors were fixed before the successful run.

**Evidence:** `artifacts/2026-10-28/120414-codex-22daf206/AcceptanceRun.xcresult`, `app-tests-run.log`, `screenshots/`; prior failed attempts retained separately. Audio package four synthetic tests and simulator compilation are in the worker receipt cited below.

**Live API verified:** no new paid calls or microphone activation. Existing local accounting remains unchanged; no account-wide billing claim.

**Remaining:** live capture orchestration still needs injected synthetic audio/event lifecycle tests beyond start guards; physical phone relay topology, cross-capture context, fitted physical viewport and raw band navigation remain open. Live API post-fix clean shutdown remains unverified. Physical dual pairing, microphone route and optical acceptance require attended testing. Goal remains active, hard stop 22:57 UTC.

## Product name — approved October 29

User selected **Borderless**. Browser and native visible branding now use Borderless; development build is Borderless Rehearsal. Existing internal package, target and bundle identifiers remain stable. Earlier Borderless receipts describe this same project.

## Simulator acceptance expansion — 2026-10-29 03:08 Shanghai

**Implemented:** BorderlessAudio delivered with explicit bounded phone PCM capture and cancellation; four synthetic package tests and iOS simulator compilation passed (worker receipt `artifacts/2026-10-28/115733-codex-c3512ab3/audio-package-report.md`). App composition is in progress. Added native UI acceptance scenarios for independent history detach/20-second idle resume and private band selection without sending a turn; these new UI tests are **not yet run**, awaiting stable capture UI and accessibility IDs from the app integration worker.

**Testing commitment:** exercise the standalone iOS app plus both shared manufacturer-rendered previews and synthetic network transport in the simulator. This is software simulation, not a vendor emulator or physical-device proof. Stable display buttons can be tested through semantic actions; raw experimental band events, Bluetooth pairing, optical fitting and microphone routes still require hardware acceptance. No additional API call or microphone use in this slice. Existing passed app build/UI evidence remains recorded below; active goal deadline remains 22:57 UTC.

## Device adapter composition — 2026-10-29 03:00 Shanghai

**Implemented:** new reusable `native/MetaDATAdapter` owns explicit DAT registration/session/display lifetime and stable button callbacks, importing MetaDisplayKit and real DAT1.0.0 without GhostRunnerFeature. New `native/BorderlessG2` mounts shared EvenCompanionKit read-only guest routes on loopback8767 and projects guest-only fitted text. `glasses-plugin` is a thin profile importing the existing plugin package with matching localhost/127.0.0.1 whitelist and no microphone capability. Native app tools now compose independent Meta and G2 enable controls; default Play still activates neither. Unique Borderless callback URL and developer-mode placeholders only; no existing account secrets copied. No Live Activity or artificial keepalive added.

**Correctness fixes:** real G2 route testing caught a MainActor handler running on Swifter's worker queue; handler is now explicitly nonisolated. HTTP JSON idempotence is checked semantically, not byte order. Meta scene action leases preserve duplicate publishes and reject late superseded scene callbacks. Native reply action IDs now include session/action generations so a new turn with identical text cannot accept an old display button.

**Tested:** two G2 tests pass, including actual loopback HTTP frame delivery and rejection of audio upload; three Meta connection/action policy tests pass; ordinary native core/codec tests pass (fixture-network test stays opt-in). Plugin TypeScript, shared whitelist validation and Vite build pass. App model + XCUITest passed with both device packages linked; final incremental iOS simulator build after action-token changes succeeded. One intermediate build overlapped a core/display source edit and saw an outdated module; the subsequent coherent build passed. No hardware activation occurred.

**Native build verified:** real DAT adapter simulator build (worker receipt `artifacts/2026-10-28/115021-codex-0ebb7caf/`); integrated app test and final build in `artifacts/2026-10-28/115104-codex-64161300/` (`DeviceAdapterAppTests.xcresult`, `app-tests.log`, `final-app-build-retry.log`, `g2-tests.log`, `meta-policy-tests.log`, `native-core-tests.log`, plugin logs).

**Live API verified:** no additional calls. Previous ASR/text evidence and conservative local ledger remain unchanged; account-wide usage not observed.

**Remaining:** phone PCM capture owner is now delegated in `native/BorderlessAudio` (no mic tests authorized); parent still needs client/capture UI composition. Native developer registration/signing, matching Even plugin installation, actual simultaneous pairing, stable/experimental band behavior, optical text fitting, and iOS foreground/background continuity require attended acceptance. G2 serving is labelled connection-unverified. Loopback relay remains a simulator development path; secure physical-phone relay endpoint/deployment is not configured. Raw experimental band navigation is not linked yet; stable display buttons route private replies correctly in source/policy tests. Meta guest-mode request remains unsent.

## Native app and relay benchmark — 2026-10-29 02:49 Shanghai

**Implemented:** runnable standalone SwiftUI iOS app in `native/BorderlessApp`, importing BorderlessCore/Display and real manufacturer renderers. Immediate fixture Play, phone-only toggle, blue host/green guest previews, continuous independent transcript histories, host-only suggestions/gloss/pronunciation and band simulation. Added `BorderlessRelay` package product: cancellable URLSession WebSocket client, strict recipient-aware wire decoder and capture-namespaced IDs. App's Rehearsal tools menu can load the same five turns from the synthetic loopback fixture service without microphone or provider use.

**Tested:** 54 Python tests; nine ordinary Swift package tests; opt-in real native WebSocket test passed, receiving five host and five guest projections from the Python fixture service, with no guest suggestions. Updated app built and its model test plus XCUITest passed after relay integration. UI test exercises immediate Play, replies, optional previews, standalone history, Next and Reset. Current screenshots visually inspected; source above translation is scrollable and may be above viewport when following the latest reply choices. Full 20-second UI idle timing remains policy-tested rather than a timed UI/device acceptance claim.

**Native build verified:** both BorderlessRelay iOS simulator library build and updated app simulator build/test succeeded. Dedicated simulator: `5C73ACF2-4780-4AE0-B4CB-AC42BC270608`; unique rehearsal bundle ID, no shipping app replaced. Main receipts: `artifacts/2026-10-28/113712-codex-b299d898/` (`swift-test.log`, `native-wire-test.log`, `relay-ios-build.log`, `app-tests.log`, `AppTests.xcresult`, screenshots). Initial app receipts in `artifacts/2026-10-28/113728-codex-1595c296/`.

**Live API verified:** none added in this slice; synthetic service cannot call providers. Earlier live evidence/retained reservations unchanged. No unattended microphone recording.

**Remaining:** physical device lifecycle adapters and band action mapping, real capture owner/client hookup, dynamic participant control/cross-capture context, fitted physical text history and attended acceptance. App is a runnable rehearsal with a tested synthetic network path, not yet live dual-glasses translation. Actual paid service remains loopback development only. Synthetic fixture server is running on port 8766 in tool session 54392; verify that handle before relying on it. It conflicts with the paid dev service port by design and must be stopped before running the latter.

## Overnight slice 4 — speech-to-translation service — 2026-10-29 02:45 Shanghai

**Implemented:** `SpeechConversation` now connects finalized speech to ordered, bounded translation and host/guest output; guest events strip private choices. Existing sync/async conversation paths share validation. Cancellable text subprocess uses the existing ledger and HTTP adapter, with a 50-second deadline and kill/reap on stop. Added loopback-only WebSocket service with separate local token, explicit consent/participant, bounded audio queue, one-session exclusion and cancellation on disconnect. It is a development service, not deployed; no API key is sent to clients.

**Tested:** 54 Python tests pass, including queue overflow, stale/cancelled results, private recipients, async worker cleanup, invalid authentication/consent, concurrent-session rejection and real loopback WebSocket exchange using a synthetic pipeline. Logs: `artifacts/2026-10-28/113712-codex-b299d898/python-tests.log`.

**Live API verified:** No paid calls this slice. Previous text-only and ASR evidence unchanged; post-fix clean live ASR shutdown remains unverified. Last local committed/reserved total $0.04382975 with two retained reservations; not account-wide billing.

**Native build verified:** Superseded by the native app and relay benchmark receipt above.

**Remaining:** Native client/capture wiring and physical adapter integration. Service currently uses explicit fixed participant per capture; cross-capture context and dynamic speaker assignment are not implemented. Loopback is suitable for simulator development, not a physical phone backend. Browser rehearsal unchanged. Hardware-only acceptance still includes dual pairing, microphone route, band and optical displays.

## Overnight slice 3 — bounded speech transport — 2026-10-29 02:38 Shanghai

**Implemented:** server-side Meta ASR WebSocket transport with bounded PCM pacing, authenticated handshake, no redirects, private disabled payload logging, consent/source epochs, timeout/cancellation, final drain and existing ledger reservations. Added pinned websockets dependency. Browser demo and native code unchanged.

**Tested:** 40 Python tests pass (eight new transport tests and one trailing-final regression). Fake-socket shutdown now includes the actual observed ordering: speechComplete followed by a stable transcript. Completed text cannot be revised by this trailing event. Receipt: `artifacts/2026-10-28/112827-codex-84d239b8/python-tests.log`.

**Live API verified:** Two short synthetic Apple voice uploads returned correct completed English greetings. Both sessions failed in final drain because a stable transcript followed speechComplete. The second request captured sanitized event ordering and isolated this parser defect. Fixed locally and regression-tested; no third paid request this run. Clean live shutdown after the fix remains unverified. These are ASR-only tests, not end-to-end translation tests. No real microphone or speaker playback.

**Accounting:** Local project committed/reserved total $0.04382975, including two retained ambiguous $0.0005 reservations (pending 2). This is conservative local accounting, not account-wide measured spend or a provider invoice. No reservations released.

**Native build verified:** No native changes/build this run; prior slice's simulator library build and seven Swift tests remain the current native evidence. No runnable native app or device proof yet.

**Remaining:** Connect bounded finalized speech events to translation and recipient delivery, finish native app shell/input context and long-text viewport fitting. One short post-fix live shutdown test is justified in a later slice; avoid repeating paid tests without changed evidence. Physical dual pairing, mic routing, band events and optical display acceptance still require attended hardware.

**Receipt:** retained synthetic WAV, both live canary JSON records and test log in `artifacts/2026-10-28/112827-codex-84d239b8/`. No publish/deploy/install. Automation remains active within its original 22:57 UTC deadline. No user input required for the next software slice.

## Overnight slice 2 — native package integration — 2026-10-29 02:00 Shanghai

**Implemented:** `native/BorderlessKit` exposes Foundation-only `BorderlessCore` and `BorderlessDisplay`. Native session owns explicit participants, consent/epochs, revision replacement, correction-dependent context invalidation, bounded 256-turn history, host-only replies, stale action tokens and private selection. Native HistoryFollow implements independent 20-second idle resume. Display projection imports the actual sibling GlassesSceneKit package, reusing both G2Render and MetaRender; no device lifecycle copied and no upstream files changed. Earlier browser-only package-reuse limitation is now partly resolved: this new native library really imports the packages, while the browser remains independent JS.

**Tested:** Seven Swift Testing tests passed, including golden five-turn browser fixture through both real renderers, guest privacy, consent/late epochs, pending invalidation, corrections, bounded history, older history without stale actions, and follow timing. Existing 23 browser contracts plus scroll-policy checks passed. Initial Swift Testing macro compile error was fixed by evaluating mutating calls before assertions; final run passes.

**Native build verified:** `xcodebuild -scheme BorderlessDisplay -destination 'generic/platform=iOS Simulator' ... CODE_SIGNING_ALLOWED=NO build` succeeded. This is an iOS simulator library build, not a runnable native app or physical device proof. macOS package tests ran successfully.

**Live API verified:** No additional paid calls in this run. Previous two-direction text canary remains the only live pipeline evidence; last recorded project ledger total $0.04282975, not freshly queried or account-wide. Voice transport is still unimplemented.

**Remaining:** Native app shell and phone presentation, bounded authenticated speech transport, source-epoch wiring, input context routing and physical pairing. History projection currently selects bounded logical turn windows; pixel-fitted long-utterance pagination still needs implementation because existing renderers retain only ten rows/lines. No claim of full physical scrollback. Phone/glasses recordings and microphone comparison require attended hardware acceptance.

**Receipts:** `artifacts/2026-10-28/105744-codex-1c6ae0e4/{swift-test.log,ios-build.log,browser-contracts.log}`; package usage/boundaries in `native/BorderlessKit/README.md`. Build cache and DerivedData retained for incremental follow-up. No publish/deploy/install/device recording. Automation remains useful and within its original deadline; next run should implement the bounded voice transport or native app shell rather than repeat this audit.

## Follow mode and native readiness — 2026-10-29 Shanghai

Browser surfaces now follow incoming text, detach on scrollback, reset a 20-second inactivity deadline on scrolling/input, and resume on timeout, reaching the bottom or Latest. Each surface owns independent state. Pure policy tests cover deadline, renewal, bottom resume, explicit resume and independent surfaces; all 23 existing contracts still pass.

Native readiness: design ready for implementation, not hardware-qualified. Re-read GlassesSceneKit/GlassesScene.swift, G2Render.swift and MetaRender.swift: semantic lines/actions already exist, but both rendering paths keep newest ten rows/lines and provide no history cursor. Add a reusable history viewport/follow policy above renderers, with fitted windows and explicit input context (history navigation versus reply focus). Add native conversation core with participant IDs, revisions, stale-event rejection and host-private replies; use golden fixtures. Reuse device transport/lifecycle owners, not copies. Live ASR transport and actual band action mapping remain incomplete. No user input required for software work; attended dual-pairing, microphone and optical evidence require user later.

## Continuous transcript UI — 2026-10-29 Shanghai

Implemented reference-inspired neutral white transcript, muted source above translation, language filters, and consistent retained history on phone and both glasses. Each surface scrolls independently, follows when at the bottom, and offers Latest. Previous host reply ideas remain expandable beside their utterance; only current suggestions are actionable. Guest receives no suggestions. One-click rehearsal preserved.

Verified app syntax and 23 existing session contract checks. Browser replay retained five turns on all three surfaces with actual overflow; EN→ES filter showed exactly two turns; band selection synchronized two selected controls (phone and host), with zero guest choice controls. This is browser simulation only; native/hardware and live voice evidence unchanged. No API calls for this UI change.

## Overnight slice 1 — 2026-10-29 Shanghai

Implemented `conversation_relay`: finalized speech-event input → metered Meta text translation → validated host-only Spanish reply options. Explicit participant attribution; bounded conversational context; duplicate/source/revision gates; late-result discard; corrections invalidate later context-dependent turns; selection never sends speech.

Verified 31 Python tests (9 new conversation tests) and all 23 browser contract tests. Ran exactly two short synthetic text API requests through the existing ledger: Spanish→English with two host replies and English→Spanish with zero guest replies both passed. Receipt: `research/conversation-canary.json`. Total local committed $0.04282975, no pending charges. No real microphone, live ASR, native build or hardware test. Browser remains fixture replay and has not been rewired to this backend yet.

Next slice: implement bounded authenticated ASR WebSocket transport and connect its normalized finals to the conversation module; retain explicit participant attribution for controlled tests. Native integration still open. Updated overnight automation to latest Spanish/host-only/one-click product contract; original hard deadline unchanged.

## Latest product correction — takes precedence over earlier receipt

Browser demo now opens ready for one-click Play with no checkboxes or join screen. English-speaking Alex wears blue Meta; Spanish-speaking Sofía wears green G2. Only Alex receives two Spanish reply options, English meanings and approximate pronunciation guides. G2 only receives conversation text/translations. Both directions translate. Phone and both previews are visible together. Rehearsal-only consent is initialized internally for fictional playback; this does not grant consent to microphone recording or provider uploads in the real app. Chinese remains archived in demo/fixtures-mandarin.json for later, not the current default.

23 JS contract checks pass including guest-suggestion exclusion. New Spanish fixture is one actual Muse Spark 1.3 response (shared response ID across turns: count usage once, not per turn). Total local ledger $0.0399615. No actual audio captured.

status: browser target verified; overnight implementation scheduled; live speech and native integration incomplete

# Borderless implementation receipt

Updated 2026-10-29 Shanghai (2026-10-28 16:58 UTC).

## Implemented and verified now

- One-phone browser app, Alex Meta host and Lin G2 guest, collapsible top previews, inline replies, pinyin and private selected reading cue.
- Band up/down/confirm simulation with separate focused and selected state, re-opening alternatives with navigation.
- Standalone phone-only mode, independently disconnected displays, replay, stale/revision cases, consent and stop.
- Recorded Muse Spark 1.3 fictional dialogue reused; this iteration made no paid requests.
- 22 JS contract checks + fixture semantic/provenance validation; app syntax check passed.
- 22 Python unit tests passed: 11 existing budget, 11 new offline speech-state tests.
- Browser exercised full autoplay to moment 10/10, benchmark 22/22, band selection, phone-only reply reveal, reconnect, and mobile 390px layout. DOM width was 390 with no horizontal overflow.
- Screenshots retained in artifacts/2026-10-28/095001-codex-34e9f7fa/: one-phone-rehearsal.jpg and phone-only-mobile.jpg.
- Local preview http://127.0.0.1:8765/ was left open. Server was running in tool session 83413; verify before assuming it remains live.

## Actual evidence boundaries

Browser core is independent JS, not yet importing the Swift glasses package. No new native build, live ASR, microphone capture, actual band input, dual-device pairing or display recording was performed. VoiceStream is an offline normalization/lifecycle core, not a WebSocket relay. Existing actual Meta fixture calls are text-model evidence only.

Local project ledger: $0.03672475 committed, $19.96327525 remaining, no pending charges. This is not account-wide usage. Meta account sign-in opened in a separate in-app browser tab; it awaits the user's login. No account-wide balance was observed.

## Decisions and next work

Read ONE-PHONE-EXECUTION.md for audio comparison and gates, META-GUEST-MODE-REQUEST.md for the unsent draft, and ../research/ONE-PHONE-SOURCE-EVIDENCE.md for exact reuse seams. Keep one authoritative capture source initially; retain separate timestamps/tracks for evaluating dual-source capture. Do not mix waveforms without evidence.

Prioritized next slice: bounded realtime voice transport around voice_relay, explicit handshake and cancellation, recorded provider fixtures from a short synthetic audio canary if entitlement and budget permit, then translation/reply delivery through the existing text relay. Add voice accounting without resetting or bypassing the current ledger. Native portable core and fixture parity follow; reuse existing lifecycle owners rather than copying them. Final physical pairing/recording requires the user.

## Overnight scheduling

Created active thread heartbeat `borderless-overnight-implementation`, every 30 minutes, 12 occurrences, with hard deadline 2026-10-28 22:57 UTC (2026-10-29 06:57 Shanghai). At deadline/completion/concrete blocker it must write a receipt and pause itself. Six-hour maximum, three review rounds, two concurrent subagents. Scheduled is not evidence that a run has executed; inspect its receipts. No deploy, publish, submit, installed-app replacement, or unattended real microphone recording authorized by this continuation.
