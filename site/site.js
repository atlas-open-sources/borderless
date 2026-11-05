import { mountConversationScene } from './conversation-scene.mjs';
import { replayState, replayCaption } from './replay-timing.mjs';
import { setupVoiceComparison } from './voice-comparison.mjs';
const canvas = document.querySelector('#globe');
const context = canvas.getContext('2d');
const rotation = document.querySelector('#rotation');
const motion = matchMedia('(prefers-reduced-motion: reduce)');
let paused = motion.matches;
let visible = true;
let angle = 15;
let previous = 0;
let coastlines = [];
function updateButton() {
  rotation.textContent = paused ? 'Rotate globe' : 'Pause globe';
  rotation.setAttribute('aria-pressed', String(paused));
}
function project(lon, lat, radius, center) {
  const a = (lon - angle) * Math.PI / 180;
  const b = lat * Math.PI / 180;
  const tilt = 12 * Math.PI / 180;
  return {
    x: center + radius * Math.cos(b) * Math.sin(a),
    y: center - radius * (Math.sin(b) * Math.cos(tilt) - Math.cos(b) * Math.cos(a) * Math.sin(tilt)),
    front: Math.sin(b) * Math.sin(tilt) + Math.cos(b) * Math.cos(a) * Math.cos(tilt) >= 0,
  };
}
function draw() {
  const size = canvas.clientWidth;
  const ratio = Math.min(devicePixelRatio || 1, 2);
  if (canvas.width !== Math.round(size * ratio)) {
    canvas.width = Math.round(size * ratio);
    canvas.height = Math.round(size * ratio);
  }
  context.setTransform(ratio, 0, 0, ratio, 0, 0);
  context.clearRect(0, 0, size, size);
  const center = size / 2;
  const radius = size * .43;
  context.strokeStyle = '#1a1714';
  context.lineWidth = 1.25;
  context.lineCap = 'round';
  context.lineJoin = 'round';
  context.beginPath();
  context.arc(center, center, radius, 0, Math.PI * 2);
  context.stroke();
  for (const ring of coastlines) {
    context.beginPath();
    let pen = false;
    for (const [lon, lat] of ring) {
      const point = project(lon, lat, radius, center);
      if (point.front) {
        if (pen) context.lineTo(point.x, point.y);
        else context.moveTo(point.x, point.y);
        pen = true;
      } else pen = false;
    }
    context.stroke();
  }
}
function tick(time) {
  if (!paused && visible && !document.hidden) {
    if (previous) angle += Math.min(time - previous, 50) * .0025;
    draw();
  }
  previous = time;
  requestAnimationFrame(tick);
}
rotation.addEventListener('click', function () { paused = !paused; updateButton(); });
motion.addEventListener('change', function (event) { paused = event.matches; updateButton(); });
new IntersectionObserver(function (entries) { visible = entries[0].isIntersecting; }).observe(canvas);
new ResizeObserver(function () { if (coastlines.length) draw(); }).observe(canvas);
updateButton();
try {
  const response = await fetch('assets/coastlines.json');
  if (!response.ok) throw new Error('Coastlines unavailable');
  coastlines = await response.json();
  draw();
  canvas.parentElement.classList.add('ready');
  requestAnimationFrame(tick);
} catch {
  canvas.hidden = true;
  rotation.hidden = true;
}
for (const button of document.querySelectorAll('.reply')) {
  button.addEventListener('click', function () {
    for (const item of document.querySelectorAll('.reply')) {
      item.classList.toggle('selected', item === button);
      item.setAttribute('aria-pressed', String(item === button));
    }
    const reply = button.querySelector('strong').textContent;
    document.querySelector('.selection').textContent = `Your private cue: ${reply}`;
  });
}

const filmRecording = document.querySelector('#film video');
const phoneRecording = document.querySelector('#recording-phone');
const glassesRecordings = [...document.querySelectorAll('#recording-meta, #recording-g2')];
const recordings = [phoneRecording, ...glassesRecordings];
const recordingToggle = document.querySelector('#recording-toggle');
const recordingTime = document.querySelector('#recording-time');
const recordingClock = document.querySelector('#recording-clock');
const scene = mountConversationScene(document.querySelector('#conversation-scene'));
let measuredSegments = [];
let spokenEvents = [];
let cueRunning = false;
let cueGeneration = 0;
const cueAudio = document.querySelector('#ear-cue');
const learnerAudio = document.querySelector('#learner-voice');
const cueButton = document.querySelector('#ear-demo-play');
const cueStop = document.querySelector('#ear-demo-stop');
const cueStatus = document.querySelector('#ear-demo-status');
function updateScene() {
  if (cueRunning) return;
  const state = replayState(measuredSegments, phoneRecording.currentTime, !phoneRecording.paused);
  const segment = measuredSegments.find(item => item.index === state.index);
  const caption = replayCaption(spokenEvents, segment, phoneRecording.currentTime);
  scene.update({...state, source:caption?.source, translation:caption?.translation});
  const line = document.querySelector('#timing-readout');
  if (state.phase === 'waiting') line.textContent = `Measured wait · ${state.elapsed.toFixed(1)} s since speech ended · result arrived after ${state.latency.toFixed(1)} s`;
  else if (state.phase === 'speaking') line.textContent = 'Speech sent at real speaking speed · recorded API run';
  else if (state.phase === 'ready') line.textContent = `Result received · ${state.latency.toFixed(1)} s after speech ended`;
  else line.textContent = 'Ready · connection setup excluded; no added reading pauses.';
}
function stopCue() {
  cueGeneration += 1;
  cueAudio.pause(); learnerAudio.pause(); cueAudio.currentTime = 0; learnerAudio.currentTime = 0;
  cueRunning = false; cueButton.disabled = false; cueStop.disabled = true;
  cueStatus.textContent = 'Cue stopped. Play conversation to resume the measured replay.';
  updateScene();
}
cueStop.addEventListener('click', stopCue);
cueButton.addEventListener('click', async function () {
  pauseRecordings(); filmRecording.pause(); stopCue();
  document.querySelector('#conversation-scene').scrollIntoView({behavior:motion.matches ? 'instant' : 'smooth',block:'center'});
  cueRunning = true; cueButton.disabled = true; cueStop.disabled = false;
  cueAudio.muted = phoneRecording.muted; learnerAudio.muted = phoneRecording.muted;
  scene.update({phase:'selecting',speaker:'host',playing:true,source:'Sí, es mi primera vez, ¡me encanta!',translation:'Yes, it’s my first time. I love it!'});
  cueStatus.textContent = 'Band selection confirmed → Spanish ear cue. API replay clock paused.';
  const generation = cueGeneration;
  await new Promise(resolve => setTimeout(resolve, 750));
  if (!cueRunning || generation !== cueGeneration) return;
  try { await cueAudio.play(); }
  catch { stopCue(); cueStatus.textContent = 'Cue could not play. Try again.'; }
});
cueAudio.addEventListener('playing', function () {
  if (cueRunning) scene.update({phase:'listening',speaker:'host',playing:true,source:'Sí, es mi primera vez, ¡me encanta!',translation:'Spanish pronunciation cue · only the host hears this'});
});
cueAudio.addEventListener('ended', async function () {
  if (!cueRunning) return;
  scene.update({phase:'speaking',speaker:'host',playing:true,source:'Sí, es mi primera vez, ¡me encanta!',translation:'English-voiced learner attempt · synthetic accent audition'});
  cueStatus.textContent = 'Now the host says it. English-accent audition; replay clock still paused.';
  try { await learnerAudio.play(); } catch { stopCue(); }
});
learnerAudio.addEventListener('ended', function () {
  stopCue();
  cueStatus.textContent = 'Hear → speak demo complete. Play conversation to resume actual API timing.';
  scene.update({phase:'ready',speaker:'host',playing:false,source:'Sí, es mi primera vez, ¡me encanta!',translation:'The cue helps you speak. It does not speak to the guest for you.'});
});
for (const audio of [cueAudio, learnerAudio]) audio.addEventListener('error', function () { if (cueRunning) { stopCue(); cueStatus.textContent = 'Pronunciation sample could not load.'; } });
phoneRecording.addEventListener('timeupdate', updateScene);
phoneRecording.addEventListener('seeked', updateScene);
phoneRecording.addEventListener('play', updateScene);
phoneRecording.addEventListener('pause', updateScene);

function pauseRecordings() {
  recordings.forEach(video => video.pause());
  recordingToggle.textContent = 'Play conversation';
}
function alignRecordings(force = false) {
  for (const video of glassesRecordings) {
    if (force || Math.abs(video.currentTime - phoneRecording.currentTime) > 0.15) {
      video.currentTime = phoneRecording.currentTime;
    }
  }
}
recordingToggle.addEventListener('click', async function () {
  if (cueRunning) stopCue();
  if (!phoneRecording.paused) { pauseRecordings(); return; }
  if (phoneRecording.ended) phoneRecording.currentTime = 0;
  alignRecordings(true);
  try {
    await Promise.all(recordings.map(video => video.play()));
    recordingToggle.textContent = 'Pause conversation';
  } catch {
    pauseRecordings();
    document.querySelector('#recording-status').textContent = 'Playback could not start. Please try Play conversation again.';
  }
});
recordingTime.addEventListener('input', function () {
  if (cueRunning) stopCue();
  phoneRecording.currentTime = Number(recordingTime.value);
  alignRecordings(true);
});
function updateRecordingDuration() {
  if (Number.isFinite(phoneRecording.duration)) recordingTime.max = String(phoneRecording.duration);
}
phoneRecording.addEventListener('loadedmetadata', updateRecordingDuration);
updateRecordingDuration();
phoneRecording.addEventListener('timeupdate', function () {
  recordingTime.value = String(phoneRecording.currentTime);
  recordingClock.value = `${Math.floor(phoneRecording.currentTime / 60)}:${String(Math.floor(phoneRecording.currentTime % 60)).padStart(2, '0')}`;
  alignRecordings();
});
phoneRecording.addEventListener('ended', pauseRecordings);
recordings.forEach(video => video.addEventListener('error', function () {
  pauseRecordings();
  document.querySelector('#recording-status').textContent = 'A recording could not load. Reload the page to try again.';
}));
document.addEventListener('visibilitychange', function () {
  if (document.hidden) { pauseRecordings(); if (cueRunning) stopCue(); }
});

const soundButton = document.querySelector('#recording-sound');
soundButton.addEventListener('click', function () { queueMicrotask(() => { cueAudio.muted=phoneRecording.muted; learnerAudio.muted=phoneRecording.muted; }); });
setupVoiceComparison({
  phone: phoneRecording,
  buttons: [...document.querySelectorAll('[data-voice]')],
  soundButton,
  status: document.querySelector('#recording-status'),
  onVariant(variant) {
    stopCue(); pauseRecordings();
    const prefix = variant === 'azure' ? 'azure-' : '';
    for (const [index, name] of ['phone', 'meta', 'g2'].entries()) {
      recordings[index].src = `assets/measured-${variant}-${name}.mp4`;
      recordings[index].poster = `assets/${prefix}${name}-poster.png`;
      recordings[index].load();
    }
    recordingTime.value = '0';
    recordingClock.value = '0:00';
    loadTranscript(`assets/measured-${variant}-transcript.json`);
  },
});
phoneRecording.addEventListener('pause', function () {
  recordingToggle.textContent = 'Play conversation';
  glassesRecordings.forEach(video => video.pause());
});

let transcriptVersion = 0;
async function loadTranscript(path) {
  const version = ++transcriptVersion;
  spokenEvents = [];
  measuredSegments = [];
  updateScene();

  try {
    const response = await fetch(path);
    if (!response.ok) throw new Error('Transcript unavailable');
    const data = await response.json();
    if (version !== transcriptVersion) return;
    spokenEvents = data.events;
    measuredSegments = data.segments ?? [];
    updateScene();
  
  } catch {
    if (version === transcriptVersion) document.querySelector('#timing-readout').textContent = 'Bubble captions unavailable. Captions remain in the recorded app.';
  }
}
await loadTranscript('assets/measured-original-transcript.json');
try {
  const response = await fetch('assets/learner-result.json');
  if (response.ok) { const result = await response.json(); document.querySelector('#learner-result').textContent = `Meta heard the learner sample: “${result.source}” → “${result.translation}”. This sample was separately processed through Meta.`; }
} catch {}

// Only one recording may own playback at a time.
phoneRecording.addEventListener("play", function () { filmRecording.pause(); });
filmRecording.addEventListener("play", function () { if (cueRunning) stopCue(); pauseRecordings(); });
