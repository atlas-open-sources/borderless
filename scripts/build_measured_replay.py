"""Remove presentation padding only; retain every within-turn provider timestamp."""
import json
import math
from pathlib import Path
import subprocess
import wave

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    'original': ('artifacts/2026-10-29/220539-codex-28d26b8d', ''),
    'azure': ('artifacts/2026-11-01/013950-codex-d8a2bb4a', 'azure-'),
}

def plan(evidence, durations):
    result, cursor = [], 0.0
    for index, (turn, spoken_duration) in enumerate(zip(evidence['turns'], durations, strict=True)):
        finals = [e['at'] for e in turn['events'] if e['event']['type'] == 'turn' and e['event'].get('audience') == 'host']
        partials = [e['at'] for e in turn['events'] if e['event']['type'] == 'partial' and e['event'].get('audience') == 'host']
        # One video-frame quantization, not a fabricated conversational pause.
        duration = math.ceil(max(spoken_duration + .5, max(finals)) * 30) / 30
        result.append(dict(index=index, speaker=turn['speaker'], start=cursor,
            end=cursor+duration, sourceStart=turn['audio_start'],
            speechEnd=cursor+spoken_duration, firstPartial=cursor+min(partials),
            resultAt=cursor+max(finals), latency=max(finals)-spoken_duration,
            text=turn['input_script']))
        cursor += duration
    return result

def build(name, artifact):
    relative, prefix = SOURCES[name]
    source = ROOT / relative
    evidence = json.loads((source/'provider-evidence.json').read_text())
    timeline = json.loads((source/'audio-conversation.json').read_text())
    durations=[]
    for index in range(len(evidence['turns'])):
        with wave.open(str(source/f'voice-{index}.wav')) as w:
            durations.append(w.getnframes()/w.getframerate())
    segments=plan(evidence,durations)
    events=[]
    for e in timeline['events']:
        segment=segments[int(e['turn']['id'].split('-')[1])]
        events.append(dict(e, at=round(e['at']-segment['sourceStart']+segment['start'],4)))
    data=dict(duration=segments[-1]['end'],events=events,segments=segments,
        disclosure='Recorded API timing from provider readiness. Four-second presentation gaps and opening/end padding removed. Connection and speech synthesis setup excluded. Up to one frame rounding per turn. Not a live API call or hardware recording.')
    (ROOT/f'site/assets/measured-{name}-transcript.json').write_text(json.dumps(data,ensure_ascii=False,indent=2))
    for device in ['phone','meta','g2']:
        original=ROOT/f'site/assets/{prefix}{device}-render.mp4'
        clips=[]
        for segment in segments:
            clip=artifact/f'{name}-{device}-{segment["index"]}.mp4'
            command=['ffmpeg','-y','-ss',str(segment['sourceStart']),'-i',str(original),'-t',str(segment['end']-segment['start']),'-vf','setpts=PTS-STARTPTS','-c:v','libx264','-preset','fast','-crf','18','-r','30','-g','30','-pix_fmt','yuv420p']
            if device=='phone': command += ['-af','asetpts=PTS-STARTPTS','-c:a','aac','-b:a','128k']
            else: command+=['-an']
            subprocess.run(command+[str(clip),'-loglevel','error'],check=True)
            clips.append(clip)
        concat=artifact/f'{name}-{device}.txt'
        concat.write_text(''.join(f"file '{p}'\n" for p in clips))
        subprocess.run(['ffmpeg','-y','-f','concat','-safe','0','-i',str(concat),'-c','copy','-movflags','+faststart',str(ROOT/f'site/assets/measured-{name}-{device}.mp4'),'-loglevel','error'],check=True)
    print(name, 'measured duration',data['duration'],flush=True)
    return data

if __name__=='__main__':
    import sys
    output=Path(sys.argv[1]).resolve(); output.mkdir(parents=True,exist_ok=True)
    for variant in SOURCES: build(variant,output)
