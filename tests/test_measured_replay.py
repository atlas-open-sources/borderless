import json
from pathlib import Path
import unittest
from scripts.build_measured_replay import plan

ROOT=Path(__file__).resolve().parents[1]
class MeasuredReplayTests(unittest.TestCase):
    def test_wait_is_preserved_but_presentation_padding_removed(self):
        evidence={'turns':[{'speaker':'guest','input_script':'Hola','audio_start':1,'events':[
            {'at':1,'event':{'type':'partial','audience':'host'}},
            {'at':6,'event':{'type':'turn','audience':'host'}}]},
            {'speaker':'host','input_script':'Sí','audio_start':11,'events':[
            {'at':2,'event':{'type':'partial','audience':'host'}},
            {'at':5,'event':{'type':'turn','audience':'host'}}]}]}
        result=plan(evidence,[3,2])
        self.assertEqual(result[0]['start'],0)
        self.assertEqual(result[0]['latency'],3)
        self.assertEqual(result[1]['start'],6)
        self.assertEqual(result[1]['resultAt'],11)
    def test_saved_timelines_preserve_every_event_and_latency(self):
        for variant,old in [('azure','azure-'),('original','')]:
            before=json.loads((ROOT/f'site/assets/{old}audio-transcript.json').read_text())
            after=json.loads((ROOT/f'site/assets/measured-{variant}-transcript.json').read_text())
            self.assertEqual(len(before['events']),len(after['events']))
            for a,b in zip(before['events'],after['events'],strict=True):
                segment=after['segments'][int(a['turn']['id'].split('-')[1])]
                self.assertEqual(a['turn'],b['turn'])
                self.assertAlmostEqual(a['at']-segment['sourceStart'],b['at']-segment['start'],places=3)
            self.assertLess(after['duration'],before['duration']-26)
            self.assertTrue(all(e['at']<=after['duration'] for e in after['events']))
