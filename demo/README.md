## Current demo

Press **Play rehearsal** immediately: no setup or checkboxes. Sofía speaks Spanish and wears green G2; Alex speaks English and wears blue Meta. Only Alex gets reply options, shown in both phone chat and Meta display, with Spanish, English meaning and an approximate pronunciation guide (not pinyin). G2 gets translations only. Reset returns to a ready-to-play state; Replay works after completion. These fictional fixtures were generated in one Meta request; each turn shares its response ID and usage record, so count that request once. Archived Mandarin fixtures are retained separately.

# Borderless: G2 + Meta conversation rehearsal

A runnable design prototype and repeatable behavioral reference. Working title, not final branding.

## Run

From the project root: `python3 demo/serve.py`, then open http://127.0.0.1:8765. The server binds loopback and allows only demo assets; it does not expose `.env`, the ledger, or parent directories. Stop it with Ctrl-C.

Join both fictional participants, start, and play or step the five-turn conversation. After Lin speaks, two private Mandarin replies appear in the chat and Meta display. Use the band simulator arrows and Select, or click a reply, to reveal tone-marked pinyin. Arrow navigation returns to the alternatives. Both device selectors can swap G2/Meta without changing conversation semantics. Disconnect/reconnect, end the session, or open the benchmark lab to inject a stale result/revision. Export produces a JSON receipt explicitly marked as simulation evidence.

## Design

Palette: cloud #f1f5f6, deep blue-grey #203c49, water #216877, mist #dbe8eb, clay accent #bd593c; G2-like monochrome green is confined to its conceptual HUD. Avenir Next carries the calm companion interface. The conversation app is the primary surface. Optional Meta-host and G2-guest previews sit above its chat flow, with device controls alongside on desktop. Use phone only disconnects both previews; the chat and reply selection continue independently. Mobile uses the same app with a compact phone-only control; keyboard focus is visible, no autoplay or audio starts on load.

The scene is an authored CSS illustration, not a camera image. G2 binocular monochrome and Meta monocular colour are illustrative presentation profiles, not optical calibration, exact pixel specifications, SDK output or validated gesture mappings. Band up/down/select are simulated semantic actions; physical bindings and publishable SDK access remain open. Long text fit must be tested on real glasses and may require pagination.

## What actually uses Meta

`tools/generate-fixtures.py` calls Meta Muse Spark 1.3 through the existing local adapter. `fixtures.json` retains response IDs, usage and generation timestamp. Its translations and reply suggestions came from real model calls using fictional text. The browser replays those results; it does not make live model requests and contains no API key. Source dialogue and timings are scripted. Speech-to-text, microphone capture, diarization, transport and optical output are simulated.

Generation originally hit the output limit during reasoning. The text adapter now fixes minimal reasoning for these short tasks; its existing tests were rerun. Generated pinyin and translations require competent-speaker review before quality acceptance. The `reference` fields are authored expected meanings, not independent human-reviewed gold labels.

## Package seam and evidence

`core.mjs` is an executable session contract and simulator, not the existing native multi-glasses package. It owns utterance identity/revisions, session epochs, consent, endpoint connection state and recipient projections. A future native bridge should implement the same observable transitions using the existing EvenCompanion package's GlassesSceneKit / GlassesTextKit / MetaDisplayKit and app-owned lifecycle. No existing Swift package has been changed or packaged for OSS here.

The current source audit is in `../research/ONE-PHONE-SOURCE-EVIDENCE.md`. The one-phone execution and audio evaluation plan is `../docs/ONE-PHONE-EXECUTION.md`. This prototype is an acceptance target for that work, not proof it already passes.

## Automated reference checks

Run `node demo/test.mjs`. The browser lab runs the same tests. Coverage includes consent, both language directions, own-speech handling, duplicate suppression, stop, late events, disconnect/reconnect, revision invalidation, capability swap and non-sending reply selection.

The final release benchmark additionally requires: physical G2+Meta run, both microphones in the same room, overlap/background voices, at least 20 bilingual turns, name/number/negation accuracy, p50/p95 end-of-speech-to-visible-display latency, cancellation/reconnect checks, display fit, and 30-minute stability. Record real device and SDK versions. Browser tests cannot close these gates.

## Submission use

This is an openly labelled simulation/design artifact suitable as supporting material. Pair it with real device footage before presenting the end-to-end experience as working hardware. Do not remove the simulation label or invent latency measurements. The guide requires a public repo and three-minute video; neither publication nor video export has occurred here. Keep generated fictional fixtures, source rights, contribution dates and inherited-package attribution explicit.
