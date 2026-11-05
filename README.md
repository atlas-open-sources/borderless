# Borderless

**Two people, two languages, one conversation.** Borderless is an iPhone app that lets two people who don't share
a language talk face to face. Each person speaks normally; Borderless shows the original words and the translation,
on the phone and, if you wear them, on display glasses (Meta Ray-Ban Display and Even Realities G2). The host can
privately see two reply ideas in the other person's language, with the meaning, and hear how to say them.

Built for the Meta Global AI Developer Hackathon (Startup track, theme *Build for Your World*), October 27 to
November 4, 2026. **What was built during the event, and what it builds on, is listed in
[CONTRIBUTIONS.md](CONTRIBUTIONS.md).**

## Try it

| | how | needs |
|---|---|---|
| iPhone app (TestFlight) | https://testflight.apple.com/join/dJTN5jBc (Beta App Review submitted Nov 5) | iOS 18+ |
| Recorded demo, in the app | open Borderless, tap **Demo**, then **Play** | nothing: no mic, network, account or glasses |
| Live translation, in the app | tap **Live**, pick two languages, confirm both people agree, **Start** | network; uses our hosted relay |
| Single-glasses mode | one person wears glasses and reads the other's words translated; when the wearer speaks, the other person taps **Play** on that line to hear it in their language | one pair of Meta Ray-Ban Display or Even G2 (optional) |
| Website and browser demo | Run `python3 site/serve.py` and open http://127.0.0.1:8769 | a browser |
| Video (3 min) | See the hackathon submission | |

Glasses are optional; the app works on the phone alone. English and Spanish are tested end to end; the other
pairs from Meta's 25-language speech catalog are selectable and marked experimental
([docs/LANGUAGE-CAPABILITIES.md](docs/LANGUAGE-CAPABILITIES.md)).

## How it works

```
 iPhone (SwiftUI)                         relay (Python, asyncio)                  Meta Model API
 ───────────────                          ─────────────────────                    ──────────────
 phone mic ── PCM 24 kHz ── wss:// ──▶   auth, consent, session caps  ── wss ──▶ Muse Voice Transcribe
                                          bounded 4-turn queue                     (streaming ASR)
 conversation state  ◀── turn events ──   per-recipient projection   ◀── text ──  Muse Spark
 (revisions, stale-result rejection)      spend ledger (fail-closed)               (translation + 2 replies)
    │
    ├── Meta Ray-Ban Display  (Meta Wearables DAT SDK 1.0.0, MetaDATAdapter)
    ├── Even Realities G2     (loopback companion on 127.0.0.1:8767 + Even Hub microapp, glasses-plugin/)
    └── Play a line aloud     (on-device iOS speech, in the listener's language)
```

**Meta models**

- **Muse Voice Transcribe** (`muse-voice-transcribe-1.0`) over Meta's realtime WebSocket: streaming partials and
  endpointed finals; partials are shown as provisional and never trigger a model call (`voice_relay/`).
- **Muse Spark** (`muse-spark-1.3`): one JSON request per finalized utterance, with bounded conversation context.
  A guest utterance returns a faithful translation plus exactly two short reply ideas for the host, each with
  text and a host-language gloss (the phone can play the reply aloud so the host hears how to say it); a host utterance returns the translation only. Results are bound to
  the utterance revision and dropped when a correction, new question, cancel or session change makes them stale
  (`conversation_relay/`, `budget_relay/`). Spoken text is treated as data, never as instructions.

**Engineering we care about**

- *Recipient privacy.* The relay projects every turn per audience: reply ideas go to the host only, never to the
  guest's display (tests in `tests/test_conversation.py`, `native/BorderlessG2/Tests`).
- *Revisions and staleness.* Every turn carries an id and revision; translations and replies for an old revision are
  discarded on the phone and on the relay.
- *Bounded, cancellable sessions.* 60-second capture ceiling, real-time pacing, a bounded queue that stops capture
  rather than silently dropping speech, Stop/background/Reset cancel everything, no automatic retries.
- *Fail-closed spend.* A SQLite ledger reserves the worst-case cost before each provider call and never releases an
  ambiguous charge (`budget_relay/core.py`, [docs/BUDGET.md](docs/BUDGET.md)). This is local enforcement: Meta has
  no provider-side cap.
- *Fitted display paging.* Text is laid out against each display's real line limits (G2 firmware font metrics,
  Meta panel layout), with Previous/Next/Latest paging that never drops long lines
  (`native/BorderlessKit/Sources/BorderlessDisplay`).
- *Keys stay on the server.* The app holds only a relay token; it rejects credentials in URLs and refuses redirects.

## Repository

| path | what |
|---|---|
| `native/BorderlessApp/` | the iOS app (`Borderless.xcodeproj`, generated from `project.yml` by XcodeGen) |
| `native/BorderlessKit/` | conversation state, display fitting and the relay client (Swift packages) |
| `native/BorderlessAudio/` | phone microphone capture and PCM conversion |
| `native/MetaDATAdapter/` | one Meta display session on the Meta Wearables DAT SDK |
| `native/BorderlessG2/` | the Even G2 loopback companion |
| `glasses-plugin/` | the Even Hub microapp the G2 shows |
| `conversation_relay/`, `voice_relay/`, `budget_relay/` | the relay: ASR transport, translation pipeline, spend ledger |
| `demo/`, `site/` | the browser rehearsal and the website, with recorded API results |
| `tests/` | Python tests for the relay (`python3 -m unittest discover -s tests -v`) |
| `docs/` | implementation log, budget design, language coverage, runbooks |

## Run it yourself

**Relay** (Python 3):

```sh
python3 -m pip install -r voice_relay/requirements.txt
printf 'META_API_KEY=%s\n' '<your Meta Model API key>' > .env     # never commit; .gitignore covers it
python3 -c 'from budget_relay.core import Ledger; Ledger(".budget/ledger.sqlite3").initialize()'  # $20 cap
python3 -m conversation_relay.server                               # ws://127.0.0.1:8766, loopback only
python3 -m unittest discover -s tests -v                           # no paid calls
```

The server writes a separate relay token to `.budget/relay-token`; paste that token, never the Meta key, into
the app's Live settings. For a phone on another network, bind with TLS:
`--bind <address> --port <port> --tls-cert <cert.pem> --tls-key <key.pem>`.
The hosted relay the TestFlight build uses (one small AWS box, Caddy TLS, spend caps, rate limits, a kill switch)
is described in [deploy/README.md](deploy/README.md).

**App** (Xcode 26+, iOS 18+):

```sh
cd native/BorderlessApp
xcodegen generate --spec project.yml
xcodebuild -project Borderless.xcodeproj -scheme Borderless \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Demo mode runs in the simulator with no server. For a device, set your own team and bundle id in `project.yml`.
Meta display output needs your own Meta Wearables developer project or Developer Mode in the Meta AI app.

### Display kits (prior work, private dependency)

The glasses rendering uses four Swift kits (EvenCompanionKit, GlassesTextKit, MetaDisplayKit, GlassesSceneKit)
and an Even Hub plugin core from our earlier project **even-companion** (MIT licensed), pinned at revision
`527efbf`. That repository is not public yet, so a fresh clone of this repository does not resolve it:

- **Demo mode, the relay, the tests in `tests/`, the website and the browser demo** need nothing from it.
- **The iOS app and `glasses-plugin/`** need it to build. Judges can install the app from TestFlight instead.

The kits were built before the hackathon (September 19 to October 24, 2026), except the reply-card change in
`527efbf` (see [CONTRIBUTIONS.md](CONTRIBUTIONS.md)). Everything Borderless-specific is in this repository.

## Limits, stated plainly

- Physical two-glasses acceptance and the full live speech loop on a physical phone are being verified as this is
  written; see the newest entries in [docs/IMPLEMENTATION-STATUS.md](docs/IMPLEMENTATION-STATUS.md).
- Speaker attribution is explicit (who is speaking is chosen), not automatic diarization.
- Meta's iOS DAT documentation says App Store publication is not supported with this SDK; Borderless is
  distributed through TestFlight for the hackathon.
- The demo voices in `site/assets` are synthetic (Apple and Azure voices); the transcripts, translations and timing
  shown with them are real recorded Meta API results.

## Privacy

Live audio goes to Meta's speech and translation APIs through our relay, only after both people agree. The relay
keeps no audio or transcripts. Saved conversations stay on the phone and are excluded from backups.
Full text: [PRIVACY.md](PRIVACY.md).

## License

MIT, see [LICENSE](LICENSE). Third-party components keep their own licenses (listed in
[CONTRIBUTIONS.md](CONTRIBUTIONS.md#third-party)).
