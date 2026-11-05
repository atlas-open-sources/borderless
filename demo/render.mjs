export const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function choiceMarkup(r,i,view,place){return `<button class="${place==='hud'?'hudChoice':'replyOption'} ${view.focused===i?'focused':''}" data-choice="${i}" aria-pressed="${view.selected===i}"><b>${esc(r.text)}</b><span>${esc(r.gloss)}</span></button>`;}
export function archivedReplies(t) {
 if(t.speaker!=='lin'||!t.replies?.length)return '';
 return `<details class="pastReplies"><summary>Your reply ideas</summary>${t.replies.map(r=>`<div class="archivedReply"><b>${esc(r.text)}</b><span>${esc(r.gloss)}</span></div>`).join('')}</details>`;
}
export function bilingualMarkup(turn, hud = false) {
 const sourceClass = hud ? 'hudSource' : 'sourceText';
 const translationClass = hud ? 'hudtext' : 'translated';
 return `<div class="${sourceClass}">${esc(turn.source)}</div><div class="${translationClass}">${esc(turn.translation)}</div>`;
}
