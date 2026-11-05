import contextlib
import io
import unittest

from conversation_relay.server import server_options


class ServerOptionsTests(unittest.TestCase):
    def test_default_is_loopback_without_tls(self):
        options = server_options([])
        self.assertEqual(options.bind, '127.0.0.1')
        self.assertEqual(options.port, 8766)
        self.assertIsNone(options.tls_cert)

    def test_remote_bind_requires_complete_tls_configuration(self):
        for args in [
            ['--bind', '0.0.0.0'], ['--bind', '192.168.1.2'],
            ['--tls-cert', 'cert.pem'], ['--tls-key', 'key.pem'],
            ['--port', '0'], ['--bind', 'example.test'],
        ]:
            with self.subTest(args=args), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    server_options(args)
        options = server_options(['--bind', '192.168.1.2', '--tls-cert', 'cert.pem', '--tls-key', 'key.pem'])
        self.assertEqual(options.bind, '192.168.1.2')

    def test_local_token_is_private_and_reused(self):
        import tempfile
        from pathlib import Path
        from unittest.mock import patch
        from conversation_relay.server import local_token
        scratch = Path(__file__).resolve().parents[1] / 'scratch'
        scratch.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as directory:
            path = Path(directory) / 'token'
            with patch('conversation_relay.server.TOKEN_PATH', path):
                first = local_token()
                self.assertGreaterEqual(len(first), 32)
                self.assertEqual(first, local_token())
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
