# MetaDATAdapter

A small iOS adapter for one Meta display session. It imports the actual shared MetaDisplayKit and DAT **1.0.0**, not GhostRunnerFeature. Initialization does not configure DAT, register, activate Bluetooth, record or connect. There are no camera, microphone, motion or experimental input dependencies.

```swift
import MetaDATAdapter
import MetaDisplayKit

let connection = MetaConnection() // @MainActor
connection.onAction = { id in /* map current reply ID to session action */ }
connection.enable()              // explicit Connect button
connection.register()            // separate explicit registration handoff
connection.submit(scene)        // MetaScene from shared MetaRender.scene(for:)
// onOpenURL: await connection.handle(url: url)
connection.disable()            // stop display, then session
```

Public API: `status`, `enabled`, `driver` (shared MetaDisplayDriver), `onAction`, `enable()`, `register()`, `handle(url:) async -> Bool`, `submit(_:)`, `disable()`. Status is off, registrationRequired, waitingForDevice, connecting, connected, stopping or failed(message). `DATSceneSink` is also public for apps already owning a DAT Display.

Connection discovery/start is bounded to twenty seconds and never retried automatically. Stream subscriptions precede session start; display is acquired only after session starts, then its sink attaches only after display starts. Generation and object identity reject old-session events. A stop must be acknowledged before another session can start; if the SDK never acknowledges, the adapter deliberately refuses a replacement instead of overlapping owners. Explicit disable also cancels registration/discovery/deadline work. Dropping the owner stops SDK resources. Registration handoff remains user-driven and can await Meta AI; no additional background keepalive or Live Activity is introduced.

Shared MetaDisplayDriver owns pacing and single-flight publication. Scene actions carry sink-generation guards evaluated on the main actor; a new scene submission, disconnect or replacement invalidates prior view callbacks. UI must still validate its own reply token/epoch. No raw band navigation is included: stable DAT component button actions are delivered through `onAction`. Experimental MWDATInputs is not linked.

The app must provide its own callback URL scheme, `MWDAT` dictionary (`AppLinkURLScheme`, `MetaAppID`, `ClientToken`, `TeamID`) and Bluetooth usage description. Those belong to the consuming app; this package contains no credentials or IDs. Existing Ghost Runner configuration is reference evidence, not reused account configuration. Actual registration, SDK compatibility, physical pairing and display/input behavior require attended validation.

Default resolution pins the official URL to exact 1.0.0. For an offline build, set `BORDERLESS_DAT_PACKAGE_PATH` to an existing **verified** checkout of revision `1f38beecba83c4c8b5e343540f9cd615323ab19a`. This development override does not verify the checkout itself and must not point to an arbitrary revision; no binaries are vendored here.

Validation: `swift test` exercises the SDK-free connection lease: explicit activation, duplicate-owner prevention, stale-generation rejection, repeated disable and stop acknowledgment. `xcodebuild -scheme MetaDATAdapter -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` compiles the real iOS SDK path. The macOS build intentionally excludes iOS DAT implementation; macOS policy tests alone are not an adapter compilation claim.

## Experimental neural-band navigation (opt-in build)

Default builds do not link MWDATInputs; `navigationStatus` is `.unavailable` and calling `setNavigationEnabled(true)` does not activate anything. To include exact DAT1.0.0's experimental product, set `BORDERLESS_EXPERIMENTAL_INPUTS=1` while resolving/building the package. This adds both the product dependency and matching Swift compile definition. Use separate DerivedData for stable and experimental builds to avoid stale package graphs. The cached SDK override remains optional and must point to the reviewed exact1.0.0 checkout.

API on `MetaConnection`:

- `onNavigation: (@MainActor (MetaNavigation) -> Void)?` with `.up`, `.down`, `.left`, `.right`, `.select`, `.back`.
- `setNavigationEnabled(_ enabled: Bool)`: separate explicit opt-in, requires an already connected display session. It never registers or connects automatically.
- `navigationStatus`: `.unavailable`, `.off`, `.activating`, `.active`, `.failed(String)`.

Experimental enable calls the actual `session.addInputs(configuration: InputsConfiguration(sources: [.neuralBand], consumeBack: true))`. Back is consumed only during this explicit capability opt-in. Other input sources, drag/capture/button events, duplicate/non-increasing timestamps and stale generations are ignored. States, errors, events and20sec activation timeout are monitored. Disable invalidates delivery first, cancels listeners/tasks and removes Inputs before session shutdown; failed removal blocks re-add until that session stops and preserves a reconnect diagnosis. No automatic retry or re-enable after reconnect. Actions must still be checked against the app's current reply/viewport state.

Synthetic tests exercise semantic delivery, opt-in, source filtering, duplicate timestamps, stop and old-generation rejection. Real SDK event switch and lifecycle compile for iOS Simulator, but physical band gestures, permissions and device activation remain unverified. Stable and experimental builds do not prove hardware support or approval for the experimental SDK.
