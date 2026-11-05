# Borderless G2 adapter

A foreground loopback publisher built on the real EvenCompanionKit stores/routes and GlassesSceneKit renderer. `G2Companion()` does nothing to hardware or network. Explicit `start()` binds IPv4 loopback port 8767; `publish(Conversation)` produces guest-only fitted text. `stop()` closes the listener and discards local transcript/frame references. It cannot prove the physical display erased its last frame.

The app exposes Enable G2 companion in its tools menu. This starts serving; it does not claim a plugin or glasses connected. Install/configure the matching `glasses-plugin` package separately during attended device acceptance. Its profile and whitelist use both localhost and 127.0.0.1 on port8767. Existing Ghost Runner/plugin installations are not modified.

Only GET/OPTIONS hello/frame routes are mounted. No audio, control or event upload route is exposed by this baseline. Nothing captures a microphone or starts a Live Activity. This foreground adapter does not solve iOS background suspension; evaluate foreground/background behavior with the real capture owner and plugin on device.

Two macOS tests pass: guest projection excludes reply assistance; a real loopback HTTP request retrieves an idempotent guest frame and rejects the audio upload route. The handler is explicitly nonisolated so Swifter worker threads do not inherit MainActor isolation. Hardware BLE delivery and background continuity are unverified.
