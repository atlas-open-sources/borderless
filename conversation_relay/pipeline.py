"""Bounded single-source speech → translation, with explicit speaker assignment."""
import asyncio
from .core import Conversation, validate_context, MAX_TEXT, MAX_TURNS
from .languages import DEFAULT_PAIR, LANGUAGES, validate_pair


class PipelineError(RuntimeError):
    pass


class SpeechConversation:
    def __init__(self, speech, relay, *, queue_size=4):
        if type(queue_size) is not int or not 1 <= queue_size <= 16:
            raise ValueError('Invalid queue capacity')
        self.speech = speech
        self.conversation = Conversation(relay)
        self.queue_size = queue_size
        self.running = False

    async def run(self, frames, on_event, *, source, consent, participant, context=None, language_pair=DEFAULT_PAIR):
        """participant(Update) must explicitly return host/guest; no voice inference.

        Output audiences are explicit. Guest turn events never contain replies.
        completed followed by stopped retains final presentation and private replies.
        Cancellation/error or explicit revoke clears presentation and actions.
        Translation overload stops capture rather than silently dropping words.
        """
        if self.running:
            raise PipelineError('Session already active')
        if consent is not True:
            raise PipelineError('Explicit consent required')
        seed = validate_context([] if context is None else context)
        pair = validate_pair(language_pair)
        self.running = True
        queue = asyncio.Queue(self.queue_size)
        tasks = []
        epoch = None
        source_epoch = None
        seen = {}
        delivery_lock = asyncio.Lock()

        async def emit(event):
            await asyncio.wait_for(on_event(event), 3)

        async def ingest(update):
            nonlocal epoch, source_epoch
            if epoch is None:
                source_epoch = update.epoch
                epoch = self.conversation.start(source, source_epoch, consent=consent, context=seed, language_pair=pair)
            if update.source != source or update.epoch != source_epoch:
                raise PipelineError('Obsolete source event')
            if update.kind not in ('partial', 'final'):
                return
            who = participant(update)
            if who not in ('host', 'guest'):
                raise PipelineError('Speaker assignment required')
            if (type(update.turn_id) is not int or type(update.revision) is not int or update.revision < 1 or
                    not isinstance(update.text, str) or len(update.text) > MAX_TEXT):
                raise PipelineError('Invalid transcript update')
            if not update.text.strip():
                if update.kind == 'partial':
                    return
                raise PipelineError('Empty final transcript')
            previous = seen.get(update.turn_id)
            identity = (update.revision, update.text, who)
            same = previous is not None and previous[:3] == identity
            if previous is not None:
                if update.revision < previous[0] or (update.revision == previous[0] and not same):
                    raise PipelineError('Obsolete or conflicting transcript revision')
                if same and (previous[3] == 'final' or update.kind == 'partial'):
                    return
            elif len(seen) >= MAX_TURNS:
                raise PipelineError('Conversation turn limit reached')
            if update.kind == 'final' and queue.full():
                raise PipelineError('Translation queue full; capture stopped')
            seen[update.turn_id] = (*identity, update.kind)
            if not same:
                pending = {'id': update.turn_id, 'revision': update.revision, 'speaker': who,
                           'source': update.text, 'translation': '', 'replies': [], 'status': 'pending'}
                async with delivery_lock:
                    await emit({'type': 'partial', 'audience': 'host', 'turn': dict(pending)})
                    await emit({'type': 'partial', 'audience': 'guest', 'turn': dict(pending)})
            if update.kind == 'final':
                # Pending final source reaches the client before model work begins.
                try:
                    queue.put_nowait((update, who))
                except asyncio.QueueFull:
                    raise PipelineError('Translation queue full; capture stopped') from None

        async def translate():
            while True:
                item = await queue.get()
                try:
                    if item is None:
                        return
                    update, who = item
                    result = await self.conversation.submit_async(update, who, epoch=epoch)
                    if result is not None:
                        async with delivery_lock:
                            await emit({'type': 'turn', 'audience': 'host', 'turn': result})
                            guest = dict(result, replies=[])
                            await emit({'type': 'turn', 'audience': 'guest', 'turn': guest})
                finally:
                    queue.task_done()

        async def ready():
            await emit({'type': 'started'})

        try:
            consumer = asyncio.create_task(translate())
            speech_options = {}
            if pair != DEFAULT_PAIR:
                speech_options["language_bias"] = [LANGUAGES[code] for code in pair]
            capture = asyncio.create_task(self.speech.run(frames, ingest, source=source, consent=consent, on_ready=ready, **speech_options))
            tasks = [capture, consumer]
            done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for task in done:
                task.result()
            if consumer.done():
                raise PipelineError('Translation consumer stopped unexpectedly')
            receipt = capture.result()
            # Overall tail bounded even if an injected translator is defective.
            async with asyncio.timeout(60 * (self.queue_size + 1)):
                await queue.put(None)
                await consumer
            await emit({'type': 'completed'})
            return receipt
        except asyncio.CancelledError:
            raise
        except Exception:
            raise PipelineError('Conversation stopped; no automatic retry') from None
        finally:
            self.conversation.stop()
            for task in tasks:
                task.cancel()
            if tasks:
                await asyncio.gather(*tasks, return_exceptions=True)
            while not queue.empty():
                queue.get_nowait(); queue.task_done()
            self.running = False
            await emit({'type': 'stopped'})
