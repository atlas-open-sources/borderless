"""Loopback-only Borderless site preview; static assets only, no project exposure."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import re
from urllib.parse import urlsplit, unquote
ROOT = Path(__file__).resolve().parent
ALLOWED = {'/submission.html', '/', '/index.html', '/style.css', '/site.js', '/voice-comparison.mjs', '/conversation-scene.mjs', '/conversation-scene.css', '/replay-timing.mjs'} | {
    '/assets/' + path.name for path in (ROOT / 'assets').iterdir() if path.is_file()
}
class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)
    def send_head(self):
        self._remaining = None
        path = unquote(urlsplit(self.path).path)
        if path not in ALLOWED:
            self.send_error(404)
            return None
        if not path.endswith(('.mp4', '.m4a')):
            return super().send_head()
        video = (ROOT / path.lstrip('/')).resolve()
        if not video.is_relative_to(ROOT.resolve()) or not video.is_file():
            self.send_error(404)
            return None
        source = video.open('rb')
        size = video.stat().st_size
        start, end = 0, size - 1
        requested = self.headers.get('Range')
        # If-Range validators are not supplied by this no-store preview server.
        # A conditional range must therefore fall back to the complete resource.
        if self.headers.get('If-Range'):
            requested = None
        if requested:
            match = re.fullmatch(r'bytes=([0-9]*)-([0-9]*)', requested)
            try:
                if not match or not any(match.groups()):
                    raise ValueError
                first, last = match.groups()
                if first:
                    start = int(first)
                    end = min(int(last), size - 1) if last else size - 1
                else:
                    suffix = int(last)
                    if suffix == 0:
                        raise ValueError
                    start = max(0, size - suffix)
                if start >= size or start > end:
                    raise ValueError
            except ValueError:
                source.close()
                self.send_response(416)
                self.send_header('Content-Range', f'bytes */{size}')
                self.send_header('Content-Length', '0')
                self.end_headers()
                return None
        self._remaining = end - start + 1
        source.seek(start)
        self.send_response(206 if requested else 200)
        self.send_header('Content-Type', 'audio/mp4' if path.endswith('.m4a') else 'video/mp4')
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Content-Length', str(self._remaining))
        if requested:
            self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        self.end_headers()
        return source

    def copyfile(self, source, outputfile):
        if self._remaining is None:
            return super().copyfile(source, outputfile)
        remaining = self._remaining
        while remaining:
            chunk = source.read(min(64 * 1024, remaining))
            if not chunk:
                break
            outputfile.write(chunk)
            remaining -= len(chunk)
    def end_headers(self):
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()
if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 8769), Handler).serve_forever()
