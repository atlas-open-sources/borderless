/** An illustrated explanation, driven by the same clock as the recorded interfaces. */
export function describeConversationScene({ phase = 'idle', speaker = 'guest', elapsed = 0, latency } = {}) {
  const host = speaker === 'host' || speaker === 'alex';
  const titles = {
    idle: 'A little help. A real conversation.',
    speaking: host ? 'You say it. They understand.' : 'Listen to their question.',
    waiting: 'Finding the words…',
    selecting: 'A small gesture. Your choice.',
    listening: 'Hear it first. Then say it.',
    ready: host ? 'Sofía reads it in Spanish.' : 'The words are yours now.',
  };
  const descriptions = {
    idle: 'Two people, one phone. Follow the conversation with the displays below.',
    speaking: host ? 'Your voice goes to their bilingual display. Your reply ideas stay with you.' : 'Their Spanish becomes English in your display. The original stays beside it.',
    waiting: 'Speech recognition, translation and reply ideas are arriving through the recorded API pipeline.',
    selecting: 'Use the wrist band to choose one of the two private replies on your Meta display.',
    listening: 'With pronunciation help enabled, a Spanish voice models your chosen reply through the glasses speakers.',
    ready: 'Read the reply yourself, or say something different. Translation follows what you actually say.',
  };
  const safePhase = Object.hasOwn(titles, phase) ? phase : 'idle';
  let detail = 'Illustrated interaction · not physical glasses footage';
  if (safePhase === 'waiting') detail = `${Math.max(0, elapsed).toFixed(1)}s since speech ended${Number.isFinite(latency) ? ` · recorded result at ${latency.toFixed(1)}s` : ''}`;
  if (safePhase === 'listening') detail = 'Optional pronunciation cue · glasses audio routing still needs hardware verification';
  if (safePhase === 'selecting') detail = 'Illustrated band gesture · selection does not speak for you';
  return { phase: safePhase, speaker: host ? 'host' : 'guest', title: titles[safePhase], description: descriptions[safePhase], detail };
}

export function mountConversationScene(container) {
  container.classList.add('conversation-scene');
  container.innerHTML = `
    <div class="cs-art">
      <div class="cs-bubble" aria-live="off"><span class="cs-bubble-person"></span><p class="cs-bubble-source"></p><p class="cs-bubble-translation"></p><span class="cs-bubble-note"></span></div>
      <div class="cs-cinema">
        <svg class="cs-illustration cs-flat-scene" viewBox="0 0 760 400" role="img" aria-label="Simple animated café illustration. Thick brown Meta frames have a small lower-right display cue in the wearer’s right lens. Rounded black G2 frames have green display cues in both lenses.">
          <defs>
            <pattern id="cs-tortoise" width="21" height="15" patternUnits="userSpaceOnUse"><rect width="21" height="15" fill="#624733"/><path d="m1 3 9-3 5 6-7 5-8-3m15 9 6-4 3 6-6 4" fill="#886343" opacity=".6"/></pattern>
          </defs>
          <path d="M55 300V108a85 85 0 0 1 170 0v192M535 300V108a85 85 0 0 1 170 0v192" fill="#ebe5d9"/>
          <path d="M70 289V111a70 70 0 0 1 140 0v178M550 289V111a70 70 0 0 1 140 0v178" fill="#e3e8de"/>
          <path d="M140 44v247m-70-130h140M620 44v247m-70-130h140" stroke="#faf7ef" stroke-width="8"/>
          <ellipse cx="380" cy="359" rx="268" ry="12" fill="#ddd4c4"/>
          <g class="cs-person cs-person-host">
            <path d="M137 351l14-84q9-47 71-47 60 0 73 47l16 84" fill="#4e7ec9"/>
            <path d="M208 193v35q17 19 32-1v-35" fill="#dcaa86"/>
            <path d="M173 119q0-60 54-60 57 0 56 62l-4 54q-8 46-48 44-44-2-51-46z" fill="#edbf9b"/>
            <path d="M174 135q-20-31-8-59 9-25 37-22 34-21 62 5 30 15 17 56l-14-23q-33 17-76 10l-5 36" fill="#53463b"/>
            <ellipse cx="175" cy="157" rx="12" ry="17" fill="#e5af87"/>
            <path d="m271 151 10 15-12 2" fill="none" stroke="#c8916e" stroke-width="3" stroke-linecap="round"/>
            <path class="cs-mouth cs-host-mouth" d="M239 187q12 8 23-1" fill="none" stroke="#804d3b" stroke-width="3" stroke-linecap="round"/>
            <ellipse cx="207" cy="144" rx="4" ry="6" fill="#3c342d"/><ellipse cx="260" cy="145" rx="4" ry="6" fill="#3c342d"/>
            <g class="cs-meta-frame">
              <path d="m179 127-19 5 1 12 19 3m99-17 12 5-1 13-12-4" fill="#644832"/>
              <path d="M180 124q22-6 46 2l4 9h8l5-9q19-5 37 2l-5 34q-4 14-22 13-18-1-18-32h-6q-2 33-24 32-21-1-23-15z M188 132q18-4 32 1l2 24q-1 11-17 11-15-1-16-12zm58 2q13-4 26 0l-3 24q-2 10-15 9-12-1-12-12z" fill-rule="evenodd" fill="url(#cs-tortoise)" stroke="#4e392c" stroke-width="2"/>
              <path d="M188 132q18-4 32 1l2 24q-1 11-17 11-15-1-16-12zm58 2q13-4 26 0l-3 24q-2 10-15 9-12-1-12-12z" fill="#f4eee3" fill-opacity=".25" stroke="#aa8762" stroke-width="1"/>
              <circle cx="182" cy="133" r="3.4" fill="#212426" stroke="#c3b39a" stroke-width="1"/><circle cx="279" cy="136" r="3" fill="#252827" stroke="#c3b39a" stroke-width="1"/>
              <!-- Frontal view: wearer's right lens is on viewer's left. -->
              <g class="cs-meta-optic" data-lens="wearer-right" data-position="lower-right"><rect x="208" y="153" width="11" height="10" rx="1" fill="#b7dafa" fill-opacity=".7"/><path d="M210 156h7m-7 3h5" stroke="#315c92" stroke-width="1.2"/></g>
            </g>
            <path d="M165 275q-10 47 26 43l58-17" fill="none" stroke="#426db5" stroke-width="29" stroke-linecap="round"/>
            <path d="m233 300 25-11q15-5 19 4 1 7-12 13l-26 10" fill="#edbf9b"/>
            <path d="m231 299 7 20" stroke="#777467" stroke-width="12"/>
            <g class="cs-pinch-hand"><path d="M276 272q17 17 1 30l-18 4" fill="none" stroke="#4e7ec9" stroke-width="24" stroke-linecap="round"/><path d="m264 302-13-4-6-13q-3-7-7-4-4 2-1 8l6 17q6 8 16 5l15-7" fill="#edbf9b"/></g>
          </g>
          <g class="cs-person cs-person-guest">
            <path d="M465 351l14-85q12-46 68-46 57 0 71 46l16 85" fill="#729b77"/>
            <path d="M531 195v33q16 17 30-1v-34" fill="#b97c59"/>
            <path d="M490 125q-4-69 57-69 60 0 61 71l7 112-49-29" fill="#443831"/>
            <path d="M493 120q0-49 51-49 49 0 50 51l-4 53q-7 45-47 44-40-1-47-44z" fill="#d99b74"/>
            <path d="M487 123q-9-45 25-62 37-18 63 5 27 12 22 63-20-8-25-35-35 28-85 29" fill="#443831"/>
            <ellipse cx="591" cy="157" rx="11" ry="17" fill="#cf8e68"/>
            <path d="m500 151-12 14 12 4" fill="none" stroke="#a96b4d" stroke-width="3" stroke-linecap="round"/>
            <path class="cs-mouth cs-guest-mouth" d="M507 187q12 8 24-1" fill="none" stroke="#794833" stroke-width="3" stroke-linecap="round"/>
            <ellipse cx="514" cy="145" rx="4" ry="6" fill="#352d28"/><ellipse cx="566" cy="145" rx="4" ry="6" fill="#352d28"/>
            <g class="cs-g2-frame">
              <path d="m586 131 17 4 1 13" fill="none" stroke="#303231" stroke-width="4"/>
              <path d="M488 130q8-12 24-12 16 0 24 12 6 10 0 27-7 20-22 20-18-1-25-20-5-15-1-27zm60 0q8-12 23-11 16 0 24 13 4 13-2 28-7 18-22 18-18-1-25-21-5-17 2-27z" fill="#d9e7df" fill-opacity=".18" stroke="#303231" stroke-width="5"/>
              <path d="M537 135q4-5 9 0" fill="none" stroke="#303231" stroke-width="5"/>
              <rect x="480" y="129" width="9" height="7" rx="1.5" fill="#747775"/><rect x="593" y="131" width="9" height="7" rx="1.5" fill="#747775"/>
              <ellipse cx="537" cy="151" rx="2" ry="5" fill="#d5d6ce"/><ellipse cx="546" cy="151" rx="2" ry="5" fill="#d5d6ce"/>
              <g class="cs-g2-optic" data-lens="left"><rect x="501" y="148" width="26" height="12" rx="2" fill="#71cf7d" fill-opacity=".25"/><path d="M504 152h20m-20 4h14" stroke="#45ac5c" stroke-width="1.8"/></g>
              <g class="cs-g2-optic" data-lens="right"><rect x="557" y="148" width="26" height="12" rx="2" fill="#71cf7d" fill-opacity=".25"/><path d="M560 152h20m-20 4h14" stroke="#45ac5c" stroke-width="1.8"/></g>
            </g>
            <path d="M493 277q-12 35 22 39l48 3" fill="none" stroke="#608967" stroke-width="27" stroke-linecap="round"/><path d="m550 311 25 1q16 3 10 13-5 6-19 4l-19-7" fill="#d99b74"/>
          </g>
          <path d="M371 312h20v45h-20z" fill="#b69b7a"/><ellipse cx="382" cy="301" rx="102" ry="23" fill="#c9ad88"/>
          <path d="m350 287 43-5 22 17-43 7z" fill="#313635" stroke="#f9f4e9" stroke-width="2"/><path d="m360 289 30-3 13 10-30 4z" fill="#c7d9dd"/>
          <path d="M302 278h21v17q-10 7-21 0zm136 0h21v17q-10 7-21 0z" fill="#fffaf1"/>
          <g class="cs-ear-waves" fill="none" stroke="#3872bc" stroke-width="3" stroke-linecap="round"><path d="M152 143q-10 13 0 26m-10-33q-16 20 0 40"/></g>
        </svg>
        <div class="cs-speaker-indicator cs-indicator-host" aria-hidden="true"><span class="cs-waveform"><i></i><i></i><i></i><i></i><i></i></span><span>You’re speaking</span></div>
        <div class="cs-speaker-indicator cs-indicator-guest" aria-hidden="true"><span class="cs-waveform"><i></i><i></i><i></i><i></i><i></i></span><span>Sofía is speaking</span></div>
        <div class="cs-private-cue" aria-hidden="true"><span class="cs-cue-ring"></span><span>Only in your ear</span></div>
        <div class="cs-gesture-cue" aria-hidden="true"><span class="cs-cue-ring"></span><span>Pinch to choose</span></div>
        <div class="cs-wearer-labels"><span>You<small>Brown · Meta Display</small></span><span>Sofía<small>Black · Even G2</small></span></div>
        <span class="cs-art-caption">Illustrated experience</span>
      </div>
    </div>
    <div class="cs-story"><div class="cs-step"><span class="cs-status-dot"></span><span class="cs-phase-label">Follow the conversation</span></div><h3 class="cs-title"></h3><p class="cs-description"></p><p class="cs-detail"></p></div>`;
  const fields = Object.fromEntries(['title', 'description', 'detail', 'phase-label'].map(key => [key, container.querySelector(`.cs-${key}`)]));
  const bubble = Object.fromEntries(['person','source','translation','note'].map(key => [key, container.querySelector(`.cs-bubble-${key}`)]));
  function update(input = {}) {
    const state = describeConversationScene(input);
    container.dataset.phase = state.phase;
    container.dataset.speaker = state.speaker;
    container.dataset.playing = String(Boolean(input.playing));
    for (const key of ['title', 'description', 'detail']) fields[key].textContent = state[key];

    bubble.person.textContent = state.phase === 'listening' ? 'Only in your ear' : state.speaker === 'host' ? 'You · English speaker' : 'Sofía · Spanish speaker';
    bubble.source.textContent = input.source || (state.phase === 'idle' ? 'A table for two. A whole new conversation.' : 'Listening to the conversation…');
    bubble.translation.textContent = input.translation || '';
    bubble.note.textContent = state.phase === 'idle' ? 'Press play below to join us in Madrid.' : state.phase === 'waiting' ? (input.translation ? 'The rest of this turn is being processed' : 'Waiting for the recorded translation') : state.phase === 'selecting' ? 'Private reply · not spoken yet' : '';
    const labels = { idle: 'Follow the conversation', speaking: 'Speaking', waiting: 'Measured API wait', selecting: 'Choose a reply', listening: 'Optional ear cue', ready: state.speaker === 'host' ? 'Translation delivered' : 'Ready to reply' };
    fields['phase-label'].textContent = labels[state.phase];
  }
  update();
  return { update, destroy() { container.replaceChildren(); container.classList.remove('conversation-scene'); } };
}
