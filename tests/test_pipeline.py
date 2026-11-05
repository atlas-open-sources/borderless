import asyncio
import json
import unittest
from conversation_relay.pipeline import SpeechConversation, PipelineError
from voice_relay.core import Update


class Speech:
    def __init__(self, count=2):
        self.count = count
        self.stopped = False
    async def run(self, frames, callback, **kwargs):
        await kwargs['on_ready']()
        try:
            for index in range(self.count):
                await callback(Update('partial', 7, 'fixture', index, 1, 'ignored'))
                await callback(Update('final', 7, 'fixture', index, 2, 'Hola' if index % 2 == 0 else 'Hello'))
            return 'speech receipt'
        finally:
            self.stopped = True


class ScriptedSpeech:
    def __init__(self, updates):
        self.updates = updates
    async def run(self, frames, callback, **kwargs):
        await kwargs['on_ready']()
        for update in self.updates:
            await callback(update)
        return 'synthetic receipt'


class Relay:
    def __init__(self):
        self.calls = []
        self.started = asyncio.Event()
        self.hold = None
        self.cancelled = False
    async def generate(self, prompt, limit):
        self.calls.append(prompt)
        self.started.set()
        try:
            if self.hold:
                await self.hold.wait()
            guest = json.loads(prompt.split('Conversation data:\n')[1])['suggest_replies_for_english_host']
            replies = [{'text': 'Bien', 'gloss': 'Well', 'pronunciation': 'bee-en'}] * 2 if guest else []
            value = {'translation': 'Hello' if guest else 'Hola', 'replies': replies}
            return {'output': [{'content': [{'type': 'output_text', 'text': json.dumps(value)}]}]}
        except asyncio.CancelledError:
            self.cancelled = True
            raise


class PipelineTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.relay = Relay()
        self.speech = Speech()
        self.pipeline = SpeechConversation(self.speech, self.relay)
        self.events = []
    async def emit(self, event):
        self.events.append(event)
    async def run_session(self):
        return await self.pipeline.run(None, self.emit, source='fixture', consent=True,
                                       participant=lambda u: 'guest' if u.turn_id % 2 == 0 else 'host')
    async def test_experimental_pair_reaches_speech_and_translation(self):
        observed = {}
        class PairSpeech:
            async def run(self, frames, callback, **kwargs):
                observed.update(kwargs)
                await kwargs['on_ready']()
                await callback(Update('final', 7, 'fixture', 1, 1, 'Bonjour'))
                return 'receipt'
        class PairRelay:
            async def generate(self, prompt, limit):
                observed['prompt'] = json.loads(prompt.split('Conversation data:\n')[1])
                value = {'source_language': 'fr', 'translation': 'こんにちは', 'replies': []}
                return {'output': [{'content': [{'type': 'output_text', 'text': json.dumps(value)}]}]}
        pipeline = SpeechConversation(PairSpeech(), PairRelay())
        await pipeline.run(None, self.emit, source='fixture', consent=True,
                           participant=lambda u: 'host', language_pair=['fr', 'ja'])
        self.assertEqual(observed['language_bias'], ['French', 'Japanese'])
        self.assertEqual(observed['prompt']['supported_languages'], ['fr', 'ja'])
        turns = [event['turn'] for event in self.events if event['type'] == 'turn']
        self.assertTrue(all(turn['target_language'] == 'ja' for turn in turns))
        self.assertTrue(all(turn['replies'] == [] for turn in turns))

    async def test_two_directions_ordered_and_private(self):
        self.assertEqual(await self.run_session(), 'speech receipt')
        turns = [e for e in self.events if e['type'] == 'turn']
        self.assertEqual([(e['turn']['id'], e['audience']) for e in turns],
                         [(0, 'host'), (0, 'guest'), (1, 'host'), (1, 'guest')])
        self.assertEqual(len(turns[0]['turn']['replies']), 2)
        self.assertTrue(all(not e['turn']['replies'] for e in turns[1:]))
        self.assertEqual(len(self.relay.calls), 2)
        self.assertIn('Hola', self.relay.calls[1])
        self.assertEqual(self.events[-1]['type'], 'stopped')
    async def test_cancel_discards_result_and_stops_worker(self):
        self.relay.hold = asyncio.Event()
        task = asyncio.create_task(self.run_session())
        await self.relay.started.wait()
        task.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await task
        self.assertTrue(self.relay.cancelled)
        self.assertFalse(self.pipeline.running)
        self.assertFalse(self.pipeline.conversation.active)
        self.assertFalse(any(e['type'] == 'turn' for e in self.events))
    async def test_queue_overflow_stops_without_silent_loss(self):
        self.speech.count = 20
        self.relay.hold = asyncio.Event()
        with self.assertRaises(PipelineError):
            await self.run_session()
        self.assertTrue(self.speech.stopped)
        self.assertFalse(self.pipeline.running)
    async def test_unknown_speaker_never_calls_model(self):
        with self.assertRaises(PipelineError):
            await self.pipeline.run(None, self.emit, source='fixture', consent=True, participant=lambda u: None)
        self.assertEqual(self.relay.calls, [])
    async def test_missing_consent_no_calls(self):
        with self.assertRaises(PipelineError):
            await self.pipeline.run(None, self.emit, source='fixture', consent=False, participant=lambda u: 'guest')
        self.assertEqual(self.events, [])
        self.assertEqual(self.relay.calls, [])

    async def test_context_seed_reaches_prompt_and_does_not_leak_to_next_run(self):
        seed = [{'speaker': 'host', 'source': 'We met yesterday.'}]
        await self.pipeline.run(None, self.emit, source='fixture', consent=True,
                                participant=lambda u: 'guest', context=seed)
        first = json.loads(self.relay.calls[0].split('Conversation data:\n')[1])
        self.assertEqual(first['context'], seed)
        self.assertEqual(self.pipeline.conversation.seed_context, [])
        self.relay.calls.clear()
        await self.run_session()
        next_capture = json.loads(self.relay.calls[0].split('Conversation data:\n')[1])
        self.assertEqual(next_capture['context'], [])

    async def test_invalid_seed_never_starts_speech_or_provider(self):
        with self.assertRaises(ValueError):
            await self.pipeline.run(None, self.emit, source='fixture', consent=True,
                                    participant=lambda u: 'guest', context=[{'private': 'reply'}])
        self.assertFalse(self.pipeline.running)
        self.assertFalse(self.speech.stopped)
        self.assertEqual(self.relay.calls, [])
        self.assertEqual(self.events, [])

    async def test_no_speech_completes_without_model_work(self):
        self.pipeline.speech = ScriptedSpeech([])
        await self.run_session()
        self.assertEqual(self.events, [{'type': 'started'}, {'type': 'completed'}, {'type': 'stopped'}])
        self.assertEqual(self.relay.calls, [])
        self.assertFalse(self.pipeline.running)

    async def test_partial_revisions_are_scoped_private_and_free(self):
        updates = [Update('partial', 7, 'fixture', 1, 1, 'Ho'),
                   Update('partial', 7, 'fixture', 1, 1, 'Ho'),
                   Update('partial', 7, 'fixture', 1, 2, 'Hola')]
        self.pipeline.speech = ScriptedSpeech(updates)
        await self.run_session()
        partials = [e for e in self.events if e['type'] == 'partial']
        self.assertEqual([(e['audience'], e['turn']['revision']) for e in partials],
                         [('host', 1), ('guest', 1), ('host', 2), ('guest', 2)])
        self.assertTrue(all(e['turn']['translation'] == '' and e['turn']['replies'] == []
                            and e['turn']['status'] == 'pending' for e in partials))
        self.assertEqual(self.relay.calls, [])

    async def test_final_source_is_visible_while_translation_waits(self):
        self.pipeline.speech = ScriptedSpeech([Update('final', 7, 'fixture', 1, 1, 'Hola')])
        self.relay.hold = asyncio.Event()
        task = asyncio.create_task(self.run_session())
        await self.relay.started.wait()
        partials = [e for e in self.events if e['type'] == 'partial']
        self.assertEqual([e['turn']['source'] for e in partials], ['Hola', 'Hola'])
        self.assertFalse(any(e['type'] == 'turn' for e in self.events))
        task.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await task
        self.assertTrue(self.relay.cancelled)
        self.assertEqual(self.events[-1]['type'], 'stopped')

    async def test_same_revision_partial_then_final_translates_once(self):
        self.pipeline.speech = ScriptedSpeech([
            Update('partial', 7, 'fixture', 1, 1, 'Hola'),
            Update('final', 7, 'fixture', 1, 1, 'Hola'),
            Update('final', 7, 'fixture', 1, 1, 'Hola')])
        await self.run_session()
        self.assertEqual(len([e for e in self.events if e['type'] == 'partial']), 2)
        self.assertEqual(len(self.relay.calls), 1)
        turns = [e for e in self.events if e['type'] == 'turn']
        self.assertEqual([e['turn']['revision'] for e in turns], [1, 1])

    async def test_unknown_speaker_emits_no_partial(self):
        with self.assertRaises(PipelineError):
            await self.pipeline.run(None, self.emit, source='fixture', consent=True, participant=lambda u: None)
        self.assertFalse(any(e['type'] in ('partial', 'turn') for e in self.events))
        self.assertEqual(self.relay.calls, [])

    async def test_conflicting_revision_stops_without_second_partial(self):
        self.pipeline.speech = ScriptedSpeech([
            Update('partial', 7, 'fixture', 1, 1, 'Hola'),
            Update('partial', 7, 'fixture', 1, 1, 'Different')])
        with self.assertRaises(PipelineError):
            await self.run_session()
        self.assertEqual(len([e for e in self.events if e['type'] == 'partial']), 2)
        self.assertEqual(self.relay.calls, [])


if __name__ == '__main__':
    unittest.main()
