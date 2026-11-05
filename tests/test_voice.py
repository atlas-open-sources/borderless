import unittest
from voice_relay import StreamError, VoiceStream


def event(kind, turn_id=None, **fields):
    value = {'type': kind, 'audioProcessedMs': 100, **fields}
    if turn_id is not None:
        value['turnId'] = turn_id
    return value


class VoiceTests(unittest.TestCase):
    def setUp(self):
        self.stream = VoiceStream()
        self.epoch = self.stream.start('phone', consent=True, now=0)

    def receive(self, item):
        return self.stream.receive(item, epoch=self.epoch, now=1)

    def test_consent_and_explicit_source_switch(self):
        with self.assertRaises(StreamError):
            VoiceStream().start('phone', consent=False, now=0)
        with self.assertRaises(StreamError):
            self.stream.start('g2', consent=True, now=1)
        self.stream.stop()
        new_epoch = self.stream.start('g2', consent=True, now=2)
        with self.assertRaises(StreamError):
            self.stream.receive(event('speechStart', 1), epoch=self.epoch, now=2)
        self.assertGreater(new_epoch, self.epoch)
        self.assertEqual(self.stream.source, 'g2')

    def test_cumulative_revisions_and_authoritative_final(self):
        self.receive(event('speechStart', 8))
        self.receive(event('transcript', transcript='four work', final=False))
        update = self.receive(event('transcript', transcript='Four works', final=True))
        self.assertEqual(update.kind, 'partial')
        self.assertEqual(update.text, 'Four works')
        self.assertEqual(update.revision, 2)
        self.receive(event('speechEnd', 8))
        update = self.receive(event('speechComplete', 8, transcript='Four works.'))
        self.assertEqual((update.kind, update.revision), ('final', 3))
        with self.assertRaises(StreamError):
            self.receive(event('speechComplete', 8, transcript='Duplicate'))

    def test_trailing_final_does_not_replace_completed_turn(self):
        self.receive(event('speechStart', 0))
        final = self.receive(event('speechComplete', 0, transcript='Hello.'))
        trailing = self.receive(event('transcript', transcript='Different trailing text', final=True))
        self.assertIsNone(trailing)
        self.assertEqual(self.stream.turns[0].text, final.text)
        self.assertEqual(self.stream.turns[0].revision, final.revision)
        with self.assertRaises(StreamError):
            self.receive(event('transcript', transcript='Malformed', final=False))

    def test_earlier_final_does_not_steal_current_partial(self):
        self.receive(event('speechStart', 90))
        self.receive(event('speechEnd', 90))
        self.receive(event('speechStart', 2))
        earlier = self.receive(event('speechComplete', 90, transcript='Earlier'))
        later = self.receive(event('transcript', transcript='Later', final=False))
        self.assertEqual(earlier.turn_id, 90)
        self.assertEqual(later.turn_id, 2)
        self.assertEqual(self.stream.turns[90].text, 'Earlier')

    def test_missing_start_and_malformed_events(self):
        for item in (event('transcript', transcript='x', final=False),
                     event('speechComplete', 1, transcript='x'),
                     event('speechStart', True), event('speechStart', 2, audioProcessedMs=-1)):
            with self.assertRaises(StreamError):
                self.receive(item)
        self.assertEqual(self.stream.turns, {})

    def test_revoke_clears_and_rejects_queued_content(self):
        self.receive(event('speechStart', 1))
        self.receive(event('transcript', transcript='private', final=False))
        self.stream.revoke()
        self.assertFalse(self.stream.active)
        self.assertEqual(self.stream.turns, {})
        with self.assertRaises(StreamError):
            self.receive(event('speechComplete', 1, transcript='private'))
        with self.assertRaises(StreamError):
            self.stream.accept_pcm(b'\0\0', epoch=self.epoch, now=2)

    def test_pcm_limits_before_transmission(self):
        stream = VoiceStream(max_seconds=.1)
        epoch = stream.start('phone', consent=True, now=0)
        for value in (b'\0', b'', b'\0' * 4802):
            with self.assertRaises(StreamError):
                stream.accept_pcm(value, epoch=epoch, now=0)
        self.assertEqual(stream.bytes_accepted, 0)
        stream.accept_pcm(b'\0' * 4800, epoch=epoch, now=0)
        with self.assertRaises(StreamError):
            stream.accept_pcm(b'\0\0', epoch=epoch, now=0)
        self.assertFalse(stream.active)

    def test_wall_deadline_and_clock(self):
        with self.assertRaises(StreamError):
            self.stream.accept_pcm(b'\0\0', epoch=self.epoch, now=float('nan'))
        with self.assertRaises(StreamError):
            self.stream.accept_pcm(b'\0\0', epoch=self.epoch, now=-1)
        with self.assertRaises(StreamError):
            self.stream.accept_pcm(b'\0\0', epoch=self.epoch, now=61)
        self.assertFalse(self.stream.active)

    def test_drain_accepts_final_but_not_audio(self):
        self.receive(event('speechStart', 1))
        self.stream.finish_input(epoch=self.epoch, now=2)
        with self.assertRaises(StreamError):
            self.stream.accept_pcm(b'\0\0', epoch=self.epoch, now=2)
        value = self.stream.receive(event('speechComplete', 1, transcript='Done'), epoch=self.epoch, now=3)
        self.assertEqual(value.kind, 'final')
        with self.assertRaises(StreamError):
            self.stream.receive(event('audioProgress'), epoch=self.epoch, now=8)

    def test_provider_error_closes_without_exposing_message(self):
        with self.assertRaisesRegex(StreamError, '^Provider stopped the stream$'):
            self.receive({'type': 'error', 'message': 'arbitrary upstream content'})
        self.assertFalse(self.stream.active)

    def test_unknown_and_speaker_events_are_not_identity(self):
        self.assertIsNone(self.receive({'type': 'futureEvent'}))
        self.assertIsNone(self.receive({'type': 'speaker', 'label': 'A'}))
        self.assertEqual(self.stream.turns, {})

    def test_duplicate_start_does_not_reset_revision(self):
        self.receive(event('speechStart', 1))
        self.receive(event('transcript', transcript='hello', final=False))
        with self.assertRaises(StreamError):
            self.receive(event('speechStart', 1))
        self.assertEqual(self.stream.turns[1].revision, 1)


if __name__ == '__main__':
    unittest.main()
