## 2026-11-02 correction: Developer Mode versus distribution

Authenticated official iOS integration docs (updated October 29) explicitly support custom URL callbacks in Developer Mode. Console says to omit MetaAppID for Developer Mode. The rehearsal configuration now omits dummy MetaAppID/ClientToken and includes bluetooth-central background mode; custom callback and team remain. This supersedes treating HTTPS console registration as a prerequisite for local Developer Mode testing. Physical registration remains to be exercised with Developer Mode enabled in Meta AI.

Production/distributed registration still requires HTTPS callback, Associated Domains and hosted AASA. No console configuration was saved. Current official docs warn App Store publication is not supported with this SDK; do not equate development install or Meta release channels with App Store approval.

Source: https://wearables.developer.meta.com/docs/develop/dat/build-integration-ios/

# Borderless Meta registration

Created 2026-10-29 in our existing Meta developer organization, alongside Ghost Runner.

Project: Borderless
Application ID: 1142963328181308

Project creation confirmed in console. User confirmed Ghost Runner's Apple Developer team: 599WAZ6282. This is now set in the native project. iOS console configuration is not yet saved: the current form requires an HTTPS universal link, rejected the then-current elsewhere-rehearsal:// scheme, and also rejected an empty link. The newly renamed borderless-rehearsal:// scheme has not been submitted to the console. Ghost Runner's existing console configuration was inspected read-only and contains ghostrunner:// with team 599WAZ6282. Its existing custom-scheme registration does not establish that the current form accepts new custom-scheme registrations. Borderless bundle ai.atlascodes.skunkworks.borderless.rehearsal and custom callback borderless-rehearsal:// match current app source. Unsaved invalid console edits were discarded. A valid Borderless HTTPS callback and app association, or clarification of Meta's custom-scheme registration route, is still required before completing registration. Keep production credentials out of shared source and reports. No camera or microphone permissions enabled, distribution version created, terms accepted or publication performed.

Native app currently retains developer placeholders, so the new registration is not yet wired into an installed device build. This is separate from the Meta model API account and its server-side API key.
