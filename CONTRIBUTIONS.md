# Contributions: what was built during the hackathon

The Meta Global AI Developer Hackathon building period ran **October 27 to November 4, 2026** (kickoff October 26,
12:00 ET). The rules ask entrants to identify clearly what was newly built during the event. This file is that
manifest. Dates are Asia/Shanghai (UTC+8), where the work was done.

**Short version:** everything in this repository was written during the event, starting **October 28, 2026**.
It builds on four small display kits and a glasses-microapp core from an earlier project of ours
(even-companion, MIT), on Meta's and Even Realities' SDKs, and on design patterns (not code) from our earlier app
Ghost Runner. Those are listed under [Prior work](#prior-work) and [Third-party](#third-party).

## How to check

- The working tree's first file dates are October 28, 2026; there is no Borderless code from before the event.
- [docs/IMPLEMENTATION-STATUS.md](docs/IMPLEMENTATION-STATUS.md) is the dated engineering log written as the work
  happened (oldest entries at the bottom). Paths it cites under `artifacts/` are our private evidence folders
  (test results, screenshots, recordings); they are not in this repository.
- This public repository starts with one squashed commit because the private working repository was only put
  under version control at the end of the event (November 3). The dates above and the log are the record.

## Built during the event (October 28 to November 4)

| date | what | where |
|---|---|---|
| Oct 28 | Meta Model API research; fail-closed spend ledger ($20 cumulative cap, reservations, no silent reset) | `budget_relay/`, `docs/BUDGET*.md`, `docs/research/META-APIS.md` |
| Oct 28–29 | Browser conversation rehearsal with two wearer views, Meta-generated fixtures, benchmark lab | `demo/` |
| Oct 29 | Bounded speech transport on Muse Voice Transcribe: realtime WebSocket, partial/final handling, cancellation, pacing | `voice_relay/` |
| Oct 29 | Translation pipeline on Muse Spark: revisions, stale-result rejection, bounded context, recipient projection (host-only replies), 4-turn queue | `conversation_relay/` |
| Oct 29 | Authenticated development relay: token, consent, one paid session at a time, TLS for non-loopback | `conversation_relay/server.py` |
| Oct 29 | Native packages: conversation state, fitted display history and paging, relay client, phone mic capture | `native/BorderlessKit/`, `native/BorderlessAudio/` |
| Oct 29 | Device adapters: one Meta display session on DAT 1.0.0; G2 loopback companion; Even Hub microapp | `native/MetaDATAdapter/`, `native/BorderlessG2/`, `glasses-plugin/` |
| Oct 29 | The iOS app: Demo playback, optional glasses previews, explicit live capture with both-person consent | `native/BorderlessApp/` |
| Oct 29 | Experimental neural-band navigation (opt-in build flag) | `native/MetaDATAdapter/` |
| Oct 30 | Real audio pipeline replay, synchronized simulator recordings, boxed bilingual reply options, pronunciation playback | `scripts/`, `site/assets/`, `native/` |
| Oct 30 | Reply cards on the shared glasses scene and Meta panel (committed to even-companion on Nov 3 as `527efbf`) | even-companion `GlassesSceneKit`, `MetaDisplayKit` |
| Oct 30–Nov 1 | Voice comparison and measured replay timing; the website with the animated conversation scene | `site/`, `scripts/` |
| Nov 2 | Any two of 25 languages selectable through the whole pipeline; standalone Demo/Live flow; saved local history (encrypted, excluded from backup); connection controls; first signed device install | `native/`, `conversation_relay/languages.py` |
| Nov 3 | Hosted relay on AWS (Caddy TLS, Docker) with per-session caps, per-install and per-IP rate limits, a daily spend cap and a kill switch | `deploy/`, `voice_relay/` |
| Nov 3 | **Single-glasses mode**: one wearer reads the others translated; others tap Play on the wearer's line to hear it in their language | `native/BorderlessApp/` |
| Nov 3 | TestFlight packaging, privacy manifest, this public copy | `native/BorderlessApp/`, `scripts/export-public.sh` |

## Prior work

Built before October 27, 2026 by the same developer, used here, not presented as event work.

| what | from | how Borderless uses it | license |
|---|---|---|---|
| **EvenCompanionKit** | even-companion (Sep 19 to Oct 24, 2026) | frame model and companion routes for the G2 loopback server | MIT |
| **GlassesTextKit** | even-companion | G2 firmware font metrics and text fitting | MIT |
| **MetaDisplayKit** | even-companion | Meta display panel layout, scene model and the paced display driver | MIT |
| **GlassesSceneKit** | even-companion | one scene rendered for both Meta and G2 | MIT |
| **even-companion plugin core** | even-companion (extracted from Ghost Runner, Sep 19) | the Even Hub microapp runtime under `glasses-plugin/` | MIT |
| Ghost Runner's Meta DAT and G2 patterns | Ghost Runner, our running app | design reference only (one phone driving both manufacturers, preview composition, DAT session lifecycle). No Ghost Runner code is copied; `MetaDATAdapter` is a new adapter written for Borderless | n/a |
| Atlas Codes look (paper/ink, heavy Roboto) and the Natural Earth globe source | our Atlas site | the website's style and globe | see below |

One change to even-companion was made during the event, for Borderless: reply cards on `GlassesScene` and the
Meta panel (commit `527efbf`, written October 30, committed November 3). It is event work and listed above.

The prior-work kits are not in this repository: even-companion is still private, so the Swift manifests point at
its GitHub URL pinned to `527efbf`. See "Display kits" in the [README](README.md).

## Third-party

| component | version | license | used for |
|---|---|---|---|
| Meta Model API: Muse Voice Transcribe, Muse Spark | `muse-voice-transcribe-1.0`, `muse-spark-1.3` | Meta terms | speech recognition, translation, reply ideas |
| Meta Wearables Device Access Toolkit (`facebook/meta-wearables-dat-ios`) | 1.0.0 | Meta license | Meta Ray-Ban Display output |
| Even Hub SDK and CLI (`@evenrealities/even_hub_sdk`, `evenhub-cli`) | 0.0.14 / 0.1.14 | Even Realities terms | the G2 microapp |
| Swifter (`httpswift/swifter`) | 1.5.0 | BSD-3-Clause | the G2 loopback HTTP server |
| websockets (Python) | 16.0 | BSD-3-Clause | relay WebSockets |
| Roboto Black | | Apache 2.0 (`site/assets/Roboto-LICENSE.txt`) | website type |
| Natural Earth 110m land | pinned revision | public domain | website globe |
| Azure AI Speech voices | | Azure terms | **only** to generate the synthetic demo speakers in `site/assets`; the app never calls Azure |

The demo speakers are synthetic. The transcripts, translations, reply ideas and timing shown with them are real
recorded Meta API results; each recording keeps its provenance next to it.

## Team

<team members: names only, as listed on the submission page>
