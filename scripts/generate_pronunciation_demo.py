"""Bounded Azure samples: Spanish coaching cue and English-accent learner audition."""
import json
import os
from pathlib import Path
import subprocess
import sys
import urllib.request
from xml.sax.saxutils import escape

TEXT='Sí, es mi primera vez, ¡me encanta!'

def main(out):
    out.mkdir(parents=True,exist_ok=True)
    key=json.loads(subprocess.check_output(['az','cognitiveservices','account','keys','list','-g',os.environ['BORDERLESS_AZURE_GROUP'],'-n',os.environ['BORDERLESS_AZURE_ACCOUNT'],'-o','json']))['key1']
    words=[('Sí','siː'),('es','ɛs'),('mi','miː'),('primera','pɹɪˈmɛɹə'),('vez','vɛs'),('me','mɛ'),('encanta','ɛnˈkæntə')]
    learner=' '.join(f'<phoneme alphabet="ipa" ph="{ph}">{text}</phoneme>' for text,ph in words)
    specs=[('spanish-cue','es-ES','es-ES-AlvaroNeural',escape(TEXT)),('learner-attempt','en-US','en-US-GuyNeural',learner)]
    for name,lang,voice,body in specs:
        dest=out/f'{name}.mp3'
        if not dest.exists():
            ssml=f'<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="{lang}"><voice name="{voice}"><prosody rate="-8%">{body}</prosody></voice></speak>'
            req=urllib.request.Request('https://swedencentral.tts.speech.microsoft.com/cognitiveservices/v1',data=ssml.encode(),headers={'Ocp-Apim-Subscription-Key':key,'Content-Type':'application/ssml+xml','X-Microsoft-OutputFormat':'audio-24khz-48kbitrate-mono-mp3','User-Agent':'BorderlessPronunciationDemo'})
            with urllib.request.urlopen(req,timeout=45) as response: dest.write_bytes(response.read())
        subprocess.run(['ffmpeg','-y','-i',str(dest),'-ar','24000','-ac','1','-c:a','pcm_s16le',str(out/f'{name}.wav'),'-loglevel','error'],check=True)
        subprocess.run(['ffmpeg','-y','-i',str(dest),'-c:a','aac',str(Path('site/assets')/f'{name}.m4a'),'-loglevel','error'],check=True)
        print(name,voice,flush=True)
    (out/'voice-receipt.json').write_text(json.dumps({'text':TEXT,'cue':'es-ES-AlvaroNeural, Spanish pronunciation','attempt':'en-US-GuyNeural, hand-authored English IPA approximations; synthetic learner audition, not an automatic accent capability','sources':['https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-synthesis-markup-pronunciation']},indent=2))

if __name__=='__main__': main(Path(sys.argv[1]))
