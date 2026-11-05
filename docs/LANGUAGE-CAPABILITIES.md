# Language availability — 2 November 2026

Borderless now permits any two different languages from Meta's 25-language speech catalog: 600 ordered host/guest configurations, or 300 unordered pairs. The selection is passed through the native session handshake, speech bias, translation prompts, private reply generation and display direction labels. It is not a translation-quality guarantee.

English host / Spanish guest has recorded live API evidence using generated speech. All other configurations are explicitly marked untested. Recorded Demo remains English–Spanish regardless of the Live selection. Experimental pairs do not offer pronunciation playback yet. Physical display glyph coverage, RTL layout and translation quality remain to be tested.

Catalog: Arabic, Bengali, Dutch, English, French, German, Hebrew, Hindi, Indonesian, Italian, Japanese, Kannada, Korean, Malay, Mandarin Chinese, Marathi, Polish, Portuguese, Spanish, Tagalog, Tamil, Telugu, Thai, Turkish and Vietnamese.

Official source: https://dev.meta.ai/docs/speech-to-text (checked 2 November 2026). Speech language bias guides recognition; it does not force detection. No provider assertion of all-pairs translation quality is implied.

Validation this pass: 86 Python tests and 22 Swift package tests passed, including pair propagation and direction handling. No new paid API calls. Native application validation is recorded separately in IMPLEMENTATION-STATUS.md.
