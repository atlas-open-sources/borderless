# Borderless privacy policy

Last updated November 3, 2026

Borderless helps two people talk across languages, with the translation shown on the phone and on smart glasses.
This page says what happens to your speech. The same text is served by our relay at `/privacy`.

**Demo mode.** Demo mode plays recorded sample conversations. It does not use the microphone and sends nothing to
our service.

**Live mode.** Live mode starts only after both people agree on screen. The microphone runs only while a live
capture is on, and each capture stops after about a minute. While a capture is on, the app streams the audio over
an encrypted connection to our relay service. The relay passes it to Meta's speech recognition (Muse Voice
Transcribe) and translation (Muse Spark) APIs and sends the transcript, the translation and any reply ideas back to
the app.

**What the relay keeps.** The relay does not store audio, transcripts or translations, and does not log what was
said. To keep the service affordable and fair, it keeps counters: how many sessions and how many seconds a device
or network address used recently. It stores these as one-way hashed identifiers, not as your IP address or device
identifier, and deletes them after two days. Meta processes the audio and text under its own terms and privacy
policy. For translation requests the relay asks Meta not to store them.

**On your phone.** Conversation text is kept only on your phone. If you save a conversation, it stays on the phone
in protected storage and is excluded from backups. Delete it in the app at any time, or delete the app.

**Glasses.** When you connect Meta Ray-Ban Display or Even Realities G2 glasses, the app sends the translated text to
them to display. Playing a line aloud uses the voice built into iOS, on your phone.

**No accounts, no ads.** Borderless has no user accounts, no advertising, no analytics and no tracking.

**Contact.** Open an issue on this repository.
