"""Generate an Azure voice audition aligned to an existing API replay.

Keys remain in memory. This changes voice audio, not recorded Meta results.
"""
import argparse
import io
import json
from pathlib import Path
import subprocess
import urllib.request
import wave
from xml.sax.saxutils import escape

RATE = 24000
VOICES = {'guest': 'es-ES-ElviraNeural', 'host': 'en-US-AndrewMultilingualNeural'}


def read_pcm(data):
    with wave.open(io.BytesIO(data)) as stream:
        if (stream.getframerate(), stream.getnchannels(), stream.getsampwidth()) != (RATE, 1, 2):
            raise ValueError('Expected 24 kHz mono signed 16-bit PCM')
        return stream.readframes(stream.getnframes())


def assemble(turns, clips, duration):
    result = bytearray(round(duration * RATE) * 2)
    for index, (turn, pcm) in enumerate(zip(turns, clips, strict=True)):
        start = round(turn['audio_start'] * RATE) * 2
        end = start + len(pcm)
        next_start = duration
        if index + 1 < len(turns):
            next_start = turns[index + 1]['audio_start']
        if end > round(next_start * RATE) * 2:
            raise ValueError(f'Voice {index} overlaps the next turn; regenerate deliberately')
        result[start:end] = pcm
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--timeline', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--account', required=True)
    parser.add_argument('--group', required=True)
    parser.add_argument('--region', required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    turns = json.loads(args.evidence.read_text())['turns']
    duration = json.loads(args.timeline.read_text())['duration']
    key = json.loads(subprocess.check_output([
        'az', 'cognitiveservices', 'account', 'keys', 'list', '-g', args.group,
        '-n', args.account, '-o', 'json']))['key1']
    clips = []
    receipt = []
    for index, turn in enumerate(turns):
        voice = VOICES[turn['speaker']]
        language = 'es-ES'
        if turn['speaker'] == 'host' and turn['input_script'].startswith('Sorry'):
            language = 'en-US'
        path = args.out / f'azure-{index}.wav'
        ssml = (f'<speak version="1.0" xml:lang="{language}"><voice name="{voice}">'
                f'<lang xml:lang="{language}">{escape(turn["input_script"])}</lang></voice></speak>')
        if not path.exists():
            request = urllib.request.Request(
                f'https://{args.region}.tts.speech.microsoft.com/cognitiveservices/v1',
                data=ssml.encode(), headers={
                    'Ocp-Apim-Subscription-Key': key,
                    'Content-Type': 'application/ssml+xml',
                    'X-Microsoft-OutputFormat': 'audio-24khz-48kbitrate-mono-mp3',
                    'User-Agent': 'BorderlessVoiceAudition'})
            with urllib.request.urlopen(request, timeout=45) as response:
                data = response.read()
            mp3 = args.out / f'azure-{index}.mp3'
            mp3.write_bytes(data)
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(mp3),
                            '-ar', str(RATE), '-ac', '1', '-c:a', 'pcm_s16le', str(path)], check=True)
            read_pcm(path.read_bytes())
        pcm = read_pcm(path.read_bytes())
        clips.append(pcm)
        receipt.append({'turn': index, 'voice': voice, 'language': language,
                        'text': turn['input_script'], 'audio_start': turn['audio_start'],
                        'duration': len(pcm) / (RATE * 2)})
        print(f'Azure turn {index + 1}: {len(pcm) / (RATE * 2):.2f}s', flush=True)
    pcm = assemble(turns, clips, duration)
    with wave.open(str(args.out / 'azure-conversation.wav'), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm)
    (args.out / 'azure-receipt.json').write_text(json.dumps({
        'disclosure': 'Azure voice audition of the same script. Existing visuals and Meta results are from original voices; Azure audio has not been reprocessed through Meta.',
        'duration': duration, 'turns': receipt,
        'characters': sum(len(t['input_script']) for t in turns),
    }, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
