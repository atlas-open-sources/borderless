"""Serve only the public demo directory, never project secrets or budget files."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import os
ROOT=Path(__file__).resolve().parent
os.chdir(ROOT)
class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path.split('?',1)[0] not in ('/','/index.html','/style.css','/app.mjs','/core.mjs','/render.mjs','/fixtures.json','/README.md'):
            self.send_error(404)
            return
        super().do_GET()
    def end_headers(self):
        self.send_header('Cache-Control','no-store')
        self.send_header('X-Content-Type-Options','nosniff')
        super().end_headers()
port = int(os.environ.get('BORDERLESS_DEMO_PORT', '8764'))
print(f'Rehearsal preview: http://127.0.0.1:{port}', flush=True)
ThreadingHTTPServer(('127.0.0.1', port), Handler).serve_forever()
