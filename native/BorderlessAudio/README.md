# BorderlessAudio

Explicit foreground phone-microphone capture for a bounded speech transport. iOS 17+, Swift 6.2. Constructing `PhoneMicrophone` does nothing to audio hardware or permissions. The independent `PCMConverter` also builds on macOS 14 for synthetic tests.

## Public API

`@MainActor @Observable PhoneMicrophone` exposes:

- `requestPermission() async -> Bool`: call from an explicit user action. Requires app `NSMicrophoneUsageDescription`.
- `start(maximumSeconds: Int = 60) throws -> AsyncThrowingStream<Data, Error>`: requires permission first; accepts 1...60 seconds. Requests the built-in phone microphone, never a Bluetooth/glasses input.
- `stop()`: idempotent resource cleanup. Call on user Stop, view/session cancellation, and app scene leaving `.active`.
- `state`: `.idle`, `.capturing`, or `.failed(AudioCaptureError)`; `permissionGranted` reflects the last explicit permission result.

Each frame is mono signed 16-bit little-endian PCM at 24,000Hz, even byte count, at most 4,800 bytes. No WAV header. Supply frames to `RelayClient.sendPCM`. A production stream buffers at most eight frames and terminates with `consumerTooSlow` on overflow; it does not silently drop speech. The audio callback performs bounded synchronous conversion and schedules a task only for terminal cleanup, not for each frame.

The caller owns the capture task and relay lifecycle. Start only after consent and relay readiness. Use `Task.checkCancellation()` before forwarding each frame, cancel that task and stop the microphone and relay when consent is revoked or Stop is pressed. A stream's normal `finish()` retains already queued frames for draining: calling `microphone.stop()` alone is not a network revocation mechanism. Use `defer { microphone.stop() }` and a cancellation handler that schedules `stop()` on the main actor if the consumer can suspend in network I/O. The stream also observes consumer cancellation.

A duration timer and PCM-byte ceiling independently bound capture. Route changes, interruptions and media-services resets terminate capture with a visible typed failure; no automatic restart. Engine, tap, observers, timer and active audio session are released on stop and isolated deinitialization. This package owns its active AVAudioSession while capturing; an aggregate app must arbitrate audio ownership before starting another recording or playback feature. No background recording entitlement is requested; app integration must stop on scene deactivation.

`PCMConverter(inputFormat:)` and `convert(_:) -> [Data]` are serial-use conversion helpers for generated buffers or another explicitly authorized input. They do not access hardware, files or network.

## Evidence and limits

Four synthetic tests cover stereo48k→mono24k sample conversion, explicit overflow failure with eight buffered frames, stop rejecting subsequent buffers, and exact duration byte clipping. iOS simulator arm64/x86_64 compilation passes. No microphone permission request, capture, playback, physical device or server API call was performed. Hardware route transitions, permission denial/revocation and foreground capture quality require an explicit physical acceptance session. Converter tail flushing is intentionally omitted at a bounded stop; a small filter tail may be lost.
