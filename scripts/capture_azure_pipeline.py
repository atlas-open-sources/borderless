"""Actual Azure speech -> Meta ASR -> translation/replies, with no playback audio."""
import asyncio
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request
from xml.sax.saxutils import escape
from scripts.capture_audio_conversation import capture
from scripts.generate_azure_comparison import read_pcm, VOICES

ROOT = Path(__file__).resolve().parents[1]
OLD = ROOT / 'artifacts/2026-10-29/235216-codex-08270d12'


def main(out):
    originals = json.loads((OLD / 'azure-receipt.json').read_text())['turns']
    key = None
    def synthesize(index, speaker, script, wav):
        nonlocal key
        voice = VOICES[speaker]
        if originals[index]['text'] == script:
            shutil.copyfile(OLD / f'azure-{index}.wav', wav)
            return voice
        if key is None:
            key = json.loads(subprocess.check_output([
                'az', 'cognitiveservices', 'account', 'keys', 'list', '-g',
                os.environ['BORDERLESS_AZURE_GROUP'], '-n', os.environ['BORDERLESS_AZURE_ACCOUNT'],
                '-o', 'json']))['key1']
        # Only dynamically selected Spanish replies require new synthesis.
        ssml = f'<speak version="1.0" xml:lang="es-ES"><voice name="{voice}"><lang xml:lang="es-ES">{escape(script)}</lang></voice></speak>'
        request = urllib.request.Request('https://swedencentral.tts.speech.microsoft.com/cognitiveservices/v1',
            data=ssml.encode(), headers={'Ocp-Apim-Subscription-Key': key,
            'Content-Type':'application/ssml+xml', 'X-Microsoft-OutputFormat':'audio-24khz-48kbitrate-mono-mp3',
            'User-Agent':'BorderlessAzureReplay'})
        with urllib.request.urlopen(request, timeout=45) as response:
            data = response.read()
        mp3 = wav.with_suffix('.mp3')
        mp3.write_bytes(data)
        subprocess.run(['ffmpeg','-v','error','-y','-i',str(mp3),'-ar','24000','-ac','1','-c:a','pcm_s16le',str(wav)],check=True)
        read_pcm(wav.read_bytes())
        return voice
    asyncio.run(capture(out, synthesize))


if __name__ == '__main__':
    main(Path(sys.argv[1]).resolve())
