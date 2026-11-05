"""Exercise the actual preview handlers over HTTP, including seek requests."""
import http.client
import importlib.util
from pathlib import Path
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer

PROJECT = Path(__file__).resolve().parents[1]


class PreviewRangeTests(unittest.TestCase):
    def test_both_preview_servers(self):
        (PROJECT / 'scratch').mkdir(exist_ok=True)
        # review/ is a local preview surface that is not version-controlled.
        surfaces = [name for name in ('site', 'review') if (PROJECT / name / 'serve.py').exists()]
        for surface in surfaces:
            with self.subTest(surface=surface):
                self.check_handler(surface)

    def check_handler(self, surface):
        spec = importlib.util.spec_from_file_location(f'{surface}_preview', PROJECT / surface / 'serve.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory(dir=PROJECT / 'scratch') as directory:
            root = Path(directory)
            (root / 'assets').mkdir()
            payload = bytes(range(256)) * 600
            (root / 'assets/rehearsal.mp4').write_bytes(payload)
            (root / 'index.html').write_text('preview')
            module.ROOT = root
            server = ThreadingHTTPServer(('127.0.0.1', 0), module.Handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()

            def request(path='/assets/rehearsal.mp4', method='GET', headers=None):
                connection = http.client.HTTPConnection(*server.server_address)
                try:
                    connection.request(method, path, headers=headers or {})
                    response = connection.getresponse()
                    return response.status, dict(response.getheaders()), response.read()
                finally:
                    connection.close()

            try:
                status, headers, body = request()
                self.assertEqual(status, 200)
                self.assertEqual(body, payload)
                self.assertEqual(headers['Accept-Ranges'], 'bytes')
                for range_value, start, end in (
                    ('bytes=10-99', 10, 99),
                    ('bytes=150000-', 150000, len(payload) - 1),
                    ('bytes=-75', len(payload) - 75, len(payload) - 1),
                    ('bytes=0-999999', 0, len(payload) - 1),
                ):
                    status, headers, body = request(headers={'Range': range_value})
                    self.assertEqual(status, 206)
                    self.assertEqual(body, payload[start:end + 1])
                    self.assertEqual(headers['Content-Range'], f'bytes {start}-{end}/{len(payload)}')
                    self.assertEqual(int(headers['Content-Length']), len(body))
                status, headers, body = request(method='HEAD', headers={'Range': 'bytes=10-99'})
                self.assertEqual(status, 206)
                self.assertEqual(headers['Content-Length'], '90')
                self.assertEqual(body, b'')
                for invalid in ('bytes=999999-', 'bytes=99-10', 'bytes=-0', 'bytes=-', 'bytes=0-1,5-7', 'nonsense'):
                    status, headers, body = request(headers={'Range': invalid})
                    self.assertEqual(status, 416)
                    self.assertEqual(headers['Content-Range'], f'bytes */{len(payload)}')
                    self.assertEqual(body, b'')
                status, _, body = request(headers={'Range': 'bytes=10-99', 'If-Range': '"stale"'})
                self.assertEqual(status, 200)
                self.assertEqual(body, payload)
                for denied in ('/.env', '/../AGENTS.md', '/assets/%2e%2e/serve.py'):
                    self.assertEqual(request(denied)[0], 404)
                self.assertEqual(request('/')[2], b'preview')
            finally:
                server.shutdown()
                server.server_close()
                thread.join()


if __name__ == '__main__':
    unittest.main()
