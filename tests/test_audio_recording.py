"""Recorded provider evidence must stay aligned with the public demo assets."""
import json
from pathlib import Path
import unittest
import wave

ROOT = Path(__file__).resolve().parents[1]

class AudioRecordingTests(unittest.TestCase):
    def test_audio_covers_every_provider_event(self):
        resources = ROOT / 'native/BorderlessApp/Resources'
        recording = json.loads((resources/'audio-conversation.json').read_text())
        with wave.open(str(resources/'audio-conversation.wav')) as wav:
            duration = wav.getnframes()/wav.getframerate()
        self.assertAlmostEqual(duration, recording['duration'], places=3)
        events = recording['events']
        self.assertEqual(sorted(e['at'] for e in events), [e['at'] for e in events])
        self.assertLess(events[-1]['at'], duration)
        finals = [e['turn'] for e in events if e['final']]
        # Endpointing may split one audio file into multiple recognized turns.
        self.assertEqual({t["id"].split("-")[1] for t in finals}, {str(i) for i in range(6)})
        self.assertEqual([t.get("sourceLanguage") for t in finals if t["speaker"] == "alex"], ["es", "en", "es"])
        self.assertEqual({t['speaker'] for t in finals}, {'alex','lin'})
        self.assertTrue(all(t['translation'] for t in finals))
        self.assertTrue(all(not t['replies'] for t in finals if t['speaker']=='alex'))
        self.assertTrue(all(len(t['replies'])==2 for t in finals if t['speaker']=='lin'))
        self.assertTrue(any(not e['final'] for e in events))
        for turn in finals:
            partials=[e for e in events if not e['final'] and e['turn']['id']==turn['id']]
            self.assertTrue(partials)
            self.assertTrue(all(not e['turn']['replies'] for e in partials))
        self.assertEqual(recording,json.loads((ROOT/'site/assets/azure-audio-transcript.json').read_text()))

if __name__ == '__main__': unittest.main()
