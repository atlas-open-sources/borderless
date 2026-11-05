/** Timing is derived from captured events, never synthetic network latency. */
export function replayState(segments, time, playing) {
  const segment = segments.findLast(s => time >= s.start);
  if (!segment || time <= 0) return {phase:'idle', playing:false};
  let phase = 'speaking';
  if (time >= segment.speechEnd) phase = time < segment.resultAt ? 'waiting' : 'ready';
  return {phase, speaker:segment.speaker, playing, elapsed:Math.max(0,time-segment.speechEnd),
    latency:segment.latency, index:segment.index};
}

/** Never show future text or carry the other speaker's previous turn into a bubble. */
export function replayCaption(events, segment, time) {
  if (!segment || time <= 0) return undefined;
  return events.findLast(event => event.at <= time && event.at >= segment.start && (event.turn.speaker === 'alex' || event.turn.speaker === 'host') === (segment.speaker === 'alex' || segment.speaker === 'host'))?.turn;
}
