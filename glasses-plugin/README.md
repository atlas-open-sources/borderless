# Borderless G2 guest microapp

A thin consumer of `even-companion-plugin`: shared discovery, bridge, frame executor and glasses mirror are imported, not copied. The phone serves guest-only frames on loopback8767. No microphone capability, provider key or direct cloud access is enabled. Startup and idle text use Borderless.

## Build and package

```
npm ci --ignore-scripts
npm run pack
```

Runs two profile/privacy tests, TypeScript, network whitelist validation, Vite production build and official Even Hub packaging. Output: `borderless-guest.ehpk`, package ID `ai.atlascodes.borderless.guest`, version0.1.0, SDK0.0.14, minimum Even app2.2.9. The internal package ID is retained for continuity and has not been claimed on the store. This is a local package, not an uploaded or installed release.

`npm run dev` binds127.0.0.1:5191 for local preview. Physical development QR testing needs a deliberately reachable development host; do not mistake computer localhost for phone localhost. The companion endpoints inside Even Hub must remain phone loopback8767.

## Attended integration

Ghost Runner already validates the shared Even Hub companion lifecycle on hardware, as confirmed by the user. This is a Borderless-specific smoke check, not a new architectural gate:

1. Install this separate guest microapp through an attended Even Hub development/private-build workflow.
2. In Borderless, enable G2 companion; open this matching microapp in Even Hub, then return to Borderless.
3. Press Play. Confirm Spanish guest text, no host reply suggestions, and continued updates.
4. Connect Meta from Borderless and compare both displays with the phone.

Do not replace the Ghost Runner plugin. No upload, registration, publication or tester invitation was performed. Official packaging/private-build documentation: https://hub.evenrealities.com/docs/cli and https://hub.evenrealities.com/docs/cli/builds.
