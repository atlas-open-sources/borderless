"""Provider key loading. The value never enters argv, logs or exception text."""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# A hosted relay names a secret file (tmpfs on the host); development reads .env.
KEY_FILE_VARIABLE = 'BORDERLESS_META_KEY_FILE'
PLACEHOLDER = 'paste-key-here'


def meta_api_key():
    """Return the key, or '' when it is not configured. .env errors propagate."""
    path = os.environ.get(KEY_FILE_VARIABLE)
    if path:
        try:
            key = Path(path).read_text().strip()
        except OSError:
            return ''
    else:
        key = ''
        for line in (ROOT / '.env').read_text().splitlines():
            if line.strip().startswith('META_API_KEY='):
                key = line.split('=', 1)[1].strip().strip("\"'")
    if key == PLACEHOLDER:
        return ''
    return key
