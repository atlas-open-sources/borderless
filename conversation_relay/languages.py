"""Selectable ASR languages; pair quality is experimental beyond English/Spanish."""
LANGUAGES = {
    'ar': 'Arabic', 'bn': 'Bengali', 'nl': 'Dutch', 'en': 'English',
    'fr': 'French', 'de': 'German', 'he': 'Hebrew', 'hi': 'Hindi',
    'id': 'Indonesian', 'it': 'Italian', 'ja': 'Japanese', 'kn': 'Kannada',
    'ko': 'Korean', 'ms': 'Malay', 'zh': 'Mandarin Chinese', 'mr': 'Marathi',
    'pl': 'Polish', 'pt': 'Portuguese', 'es': 'Spanish', 'tl': 'Tagalog',
    'ta': 'Tamil', 'te': 'Telugu', 'th': 'Thai', 'tr': 'Turkish', 'vi': 'Vietnamese'
}
DEFAULT_PAIR = ('en', 'es')


def validate_pair(pair):
    if (not isinstance(pair, (list, tuple)) or len(pair) != 2 or
            any(not isinstance(code, str) or code not in LANGUAGES for code in pair) or
            pair[0] == pair[1]):
        raise ValueError('Choose two different supported speech languages')
    return tuple(pair)
