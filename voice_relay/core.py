"""Bounded, single-owner ENDPOINTING/CUMULATIVE stream state.

A transport must serialize all calls and capture epoch in its callbacks. This core
neither opens a socket nor accounts for provider charges. Times are monotonic.
"""
from dataclasses import dataclass
import math

PCM_BYTES_PER_SECOND = 48_000
MAX_FRAME_BYTES = 4_800
MAX_TEXT_CHARS = 16_384
MAX_TURNS = 256


class StreamError(ValueError):
    """Rejected local lifecycle, input, or provider event."""


@dataclass(frozen=True)
class Update:
    kind: str
    epoch: int
    source: str
    turn_id: int
    revision: int
    text: str


@dataclass
class _Turn:
    text: str = ''
    revision: int = 0
    ended: bool = False
    complete: bool = False


class VoiceStream:
    """Explicit consent, source epochs, bounded PCM, and revisable turn output."""

    def __init__(self, max_seconds=60, drain_seconds=5):
        if not 0 < max_seconds <= 300 or not 0 < drain_seconds <= 30:
            raise StreamError('Invalid duration limit')
        self.max_seconds = max_seconds
        self.drain_seconds = drain_seconds
        self.epoch = 0
        self.active = False
        self.consent = False
        self.source = ''
        self.turns = {}
        self.current_turn = None
        self.bytes_accepted = 0
        self.draining = False
        self.deadline = 0
        self.last_time = 0

    def start(self, source, *, consent, now):
        if self.active:
            raise StreamError('Stop the previous source before opening another')
        if consent is not True or not isinstance(source, str) or not source or len(source) > 128:
            raise StreamError('Explicit consent and a bounded source ID are required')
        self._valid_time(now)
        self.epoch += 1
        self.active = True
        self.consent = True
        self.source = source
        self.turns.clear()
        self.current_turn = None
        self.bytes_accepted = 0
        self.draining = False
        self.last_time = now
        self.deadline = now + self.max_seconds
        return self.epoch

    def stop(self):
        self.active = False
        self.consent = False
        self.epoch += 1
        self.turns.clear()
        self.current_turn = None
        self.draining = False

    def revoke(self):
        self.stop()

    @staticmethod
    def _valid_time(now):
        if isinstance(now, bool) or not isinstance(now, (int, float)) or not math.isfinite(now):
            raise StreamError('A finite monotonic time is required')

    def _gate(self, epoch, now):
        if not self.active or not self.consent or epoch != self.epoch:
            raise StreamError('Inactive or obsolete stream')
        self._valid_time(now)
        if now < self.last_time:
            raise StreamError('Clock moved backwards')
        self.last_time = now
        if now > self.deadline:
            self.stop()
            raise StreamError('Stream deadline exceeded')

    def accept_pcm(self, pcm, *, epoch, now):
        """Call immediately before sending; does not retain or transmit samples."""
        self._gate(epoch, now)
        if self.draining:
            raise StreamError('Input already ended')
        if not isinstance(pcm, bytes) or not pcm or len(pcm) % 2 or len(pcm) > MAX_FRAME_BYTES:
            raise StreamError('Expected bounded mono PCM16 frame')
        proposed = self.bytes_accepted + len(pcm)
        if proposed > int(self.max_seconds * PCM_BYTES_PER_SECOND):
            self.stop()
            raise StreamError('PCM duration cap exceeded')
        self.bytes_accepted = proposed
        return len(pcm)

    def finish_input(self, *, epoch, now):
        """Transport sends endStream once, then drains within this deadline."""
        self._gate(epoch, now)
        if self.draining:
            raise StreamError('Input already ended')
        self.draining = True
        self.deadline = now + self.drain_seconds

    @staticmethod
    def _integer(value):
        return isinstance(value, int) and not isinstance(value, bool)

    def receive(self, event, *, epoch, now):
        """Normalize validated provider events; None means no presentation change."""
        self._gate(epoch, now)
        if not isinstance(event, dict):
            raise StreamError('Expected provider object')
        kind = event.get('type')
        if kind == 'error':
            self.stop()
            raise StreamError('Provider stopped the stream')
        known = ('speechStart', 'speechEnd', 'speechComplete', 'transcript', 'audioProgress')
        if kind not in known:
            return None
        processed = event.get('audioProcessedMs')
        if not self._integer(processed) or processed < 0:
            raise StreamError('Invalid audio progress')
        if kind == 'audioProgress':
            return None
        turn_id = self.current_turn if kind == 'transcript' else event.get('turnId')
        if not self._integer(turn_id) or not -(2**31) <= turn_id < 2**31:
            raise StreamError('Missing or invalid turn identity')
        if kind == 'speechStart':
            if turn_id in self.turns:
                raise StreamError('Duplicate turn start')
            if len(self.turns) >= MAX_TURNS:
                self.stop()
                raise StreamError('Turn cap exceeded')
            self.turns[turn_id] = _Turn()
            self.current_turn = turn_id
            return Update('started', epoch, self.source, turn_id, 0, '')
        turn = self.turns.get(turn_id)
        # Live ENDPOINTING can emit a final transcript after speechComplete.
        # It has no turn ID and cannot revise an authoritative completed turn.
        if turn is not None and turn.complete and kind == 'transcript':
            if (event.get('final') is not True or
                    not isinstance(event.get('transcript'), str) or
                    len(event['transcript']) > MAX_TEXT_CHARS):
                raise StreamError('Invalid trailing transcript')
            return None
        if turn is None or turn.complete:
            raise StreamError('Unknown or completed turn')
        if kind == 'speechEnd':
            if turn.ended:
                raise StreamError('Duplicate turn end')
            turn.ended = True
            return Update('ended', epoch, self.source, turn_id, turn.revision, turn.text)
        text = event.get('transcript')
        if not isinstance(text, str) or len(text) > MAX_TEXT_CHARS:
            raise StreamError('Invalid or oversized transcript')
        if kind == 'transcript' and not isinstance(event.get('final'), bool):
            raise StreamError('Missing transcript stability')
        # Cumulative hypotheses replace, never append. A transcript final flag is
        # not turn completion in ENDPOINTING mode; speechComplete is authoritative.
        turn.text = text
        turn.revision += 1
        turn.complete = kind == 'speechComplete'
        return Update('final' if turn.complete else 'partial', epoch, self.source,
                      turn_id, turn.revision, text)
