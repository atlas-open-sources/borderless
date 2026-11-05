// Each variant owns its audio, simulator recordings and actual Meta transcript.
export function setupVoiceComparison({ phone, buttons, soundButton, status, onVariant }) {
  let muted = phone.muted;
  let selected = 'original';
  soundButton.addEventListener('click', function () {
    muted = !muted;
    phone.muted = muted;
    soundButton.textContent = muted ? 'Unmute' : 'Mute';
    soundButton.setAttribute('aria-pressed', String(muted));
  });
  for (const button of buttons) {
    button.addEventListener('click', function () {
      const variant = button.dataset.voice;
      if (variant === selected) return;
      selected = variant;
      for (const choice of buttons) choice.setAttribute('aria-pressed', String(choice === button));
      onVariant(variant);
      phone.muted = muted;
      status.textContent = `${variant === 'azure' ? 'Azure neural' : 'Original system'} voices → real Meta transcription, translation and private reply results. Measured within-turn delays preserved; added reading pauses removed. Recorded native simulator playback; no physical lens footage. Switching versions restarts the conversation because their timings differ.`;
    });
  }
}
