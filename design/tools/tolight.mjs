// Generates the light-theme artboards (*Light.dc.html) from the dark ones.
//
//   node design/tools/tolight.mjs
//
// Edit only the dark artboards; this rewrites every *Light.dc.html. Colours are
// mapped by ordered literal replacement: context-qualified rules first, so that
// ambiguous darks (page background vs. ink on amber) split correctly, then the
// generic token table. Anything left unmapped is reported and fails the run.
//
// A colour that must stay the same in both themes — the Lock Screen Live Activity's
// fixed ink and amber — is written as a value outside the table (#120F0D, #FFB03B)
// and listed in FIXED below.
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = join(dirname(fileURLToPath(import.meta.url)), '..');

const shared = [
  // --- ink on amber (must precede the page-background rule) ---
  ['stroke="#12100E"', 'stroke="#23201C"'],
  ['fill="#12100E"', 'fill="#23201C"'],
  ['color: #12100E', 'color: #23201C'],

  // --- context-qualified surfaces ---
  ['background: #171513; border: 1px solid #242120;', 'background: #F4EFE7; border: 1px solid #E8E1D6;'],
  ['border-top: 1px solid #221F1D; background: #171513;', 'border-top: 1px solid #E8E1D6; background: #FFFFFF;'],
  ['background: #171513; border-top: 1px solid #2A2724;', 'background: #FFFFFF; border-top: 1px solid #E8E1D6;'],
  ['height: 34px; border-radius: 12px; background: #1C1917;', 'height: 34px; border-radius: 12px; background: #D9D1C4;'],
  ['border-radius: 12px; background: #2A2724;', 'border-radius: 12px; background: #EFE9DF;'],
  ['height: 44px; border-radius: 12px; background: #1C1917;', 'height: 44px; border-radius: 12px; background: #F1EAE0;'],
  ['background: #FFFFFF; margin: 0 -9px; flex-shrink: 0; box-shadow: 0 2px 10px rgba(0,0,0,0.45);',
   'background: #FFFFFF; margin: 0 -9px; flex-shrink: 0; border: 1px solid #E0D8CB; box-sizing: border-box; box-shadow: 0 2px 8px rgba(0,0,0,0.16);'],
  ['background: #FFFFFF; margin: 0 -8px; flex-shrink: 0; box-shadow: 0 2px 10px rgba(0,0,0,0.45);',
   'background: #FFFFFF; margin: 0 -8px; flex-shrink: 0; border: 1px solid #E0D8CB; box-sizing: border-box; box-shadow: 0 2px 8px rgba(0,0,0,0.16);'],
  // Settings: segmented controls read as a recessed track in light
  ['background: #1C1917; border: 1px solid #2A2724; border-radius: 20px; padding: 6px;',
   'background: #F1EAE0; border: 1px solid #E8E1D6; border-radius: 20px; padding: 6px;'],
  ['height: 40px; border-radius: 14px; background: #332D28;', 'height: 40px; border-radius: 14px; background: #FFFFFF;'],
  ['background: #171513; border-radius: 14px; padding: 4px;', 'background: #F1EAE0; border-radius: 14px; padding: 4px;'],
  ['height: 36px; border-radius: 11px; background: #332D28;', 'height: 36px; border-radius: 11px; background: #FFFFFF;'],
  // off-toggle knob goes white, before the generic dim-grey rule
  ['width: 27px; height: 27px; border-radius: 50%; background: #6E665F;',
   'width: 27px; height: 27px; border-radius: 50%; background: #FFFFFF;'],

  // --- Ringing + Lock Screen: atmosphere ---
  ['radial-gradient(120% 62% at 50% 34%, #2A1C0C 0%, #16110C 58%, #0D0B09 100%)',
   'radial-gradient(120% 62% at 50% 34%, #FFEFD4 0%, #FBF5EB 58%, #F5EFE5 100%)'],
  ['stroke="#2E2519"', 'stroke="#EDE4D5"'],
  ['stroke="#FFB03A" stroke-width="10"', 'stroke="#E8940F" stroke-width="10"'],
  ['background: #1E1913; border: 1px solid #332812;', 'background: #FFF4E0; border: 1px solid #F0DFC0;'],
  ['#5F4A28', '#D9BE88'],

  // --- Sound sheet: backdrop + curve area fill ---
  ['background: #0B0A09;', 'background: #E7E0D5;'],
  ['fill="#3A2A12"', 'fill="#FCEBCE"'],

  // --- amber: text tones darken, fills deepen ---
  ['color: #FFB03A', 'color: #B0710A'],
  ['color: #FFC670', 'color: #8A5708'],
  ['#FFB03A', '#E8940F'],

  // --- amber-tinted surfaces ---
  ['#241C12', '#FFF4E0'],
  ['#3A2C18', '#F0DFC0'],
  ['#C79A55', '#9A6A0C'],

  // --- neutrals ---
  ['#1C1917', '#FFFFFF'],
  ['#171513', '#FFFFFF'],
  ['#262220', '#F0EAE0'],
  ['#2A2724', '#E8E1D6'],
  ['#332D28', '#E3DBCE'],
  ['#3A3530', '#CFC6B9'],
  ['#F7F3EE', '#1A1714'],
  ['#C9C0B7', '#4A443C'],
  ['#9A928A', '#6F665C'],
  ['#8A8279', '#7D746A'],
  ['#6E665F', '#938A7E'],
  ['#5F574F', '#A39A8E'],
  ['#4A443E', '#C7BEB2'],
  ['#3E3934', '#D3CABD'],
  ['rgba(0,0,0,0.45)', 'rgba(0,0,0,0.18)'],

  // --- page background last ---
  ['#12100E', '#FAF7F2'],
];

// Amber icon strokes need more weight on white than amber fills do.
const iconPass = [
  ['stroke="#E8940F"', 'stroke="#B0710A"'],
  ['fill="#E8940F"', 'fill="#B0710A"'],
  // ...except the ringing screen's volume ring, which stays vivid.
  ['stroke="#B0710A" stroke-width="10"', 'stroke="#E8940F" stroke-width="10"'],
];

// Settings shows Appearance on Auto in both themes — the first-launch default — so
// the twins carry the same selection and need no per-theme swap.
// The English artboards, and the Thai ones tothai.mjs writes from them.
const english = ['Main', 'EditAlarm', 'SoundSheet', 'Ringing', 'LockScreen', 'Sounds', 'Settings'];
const files = [...english, ...english.map((name) => `${name}Th`)];

const LIGHT = ['#FAF7F2', '#FFFFFF', '#F4EFE7', '#F1EAE0', '#F0EAE0', '#EFE9DF', '#E8E1D6', '#E7E0D5',
  '#E3DBCE', '#E0D8CB', '#D9D1C4', '#D3CABD', '#CFC6B9', '#C7BEB2', '#A39A8E', '#938A7E', '#7D746A',
  '#6F665C', '#4A443C', '#23201C', '#1A1714', '#E8940F', '#B0710A', '#8A5708', '#9A6A0C', '#FFF4E0',
  '#F0DFC0', '#FCEBCE', '#EDE4D5', '#D9BE88', '#FFEFD4', '#FBF5EB', '#F5EFE5'];
const FIXED = ['#120F0D', '#FFB03B'];
const allowed = new Set([...LIGHT, ...FIXED]);

let problems = 0;
for (const name of files) {
  let s = readFileSync(join(DIR, `${name}.dc.html`), 'utf8');
  for (const [from, to] of shared) s = s.split(from).join(to);
  for (const [from, to] of iconPass) s = s.split(from).join(to);

  const bad = [...new Set([...s.matchAll(/#[0-9A-F]{6}/g)].map((m) => m[0]).filter((c) => !allowed.has(c)))];
  if (bad.length) problems++;
  writeFileSync(join(DIR, `${name}Light.dc.html`), s);
  console.log(`${name}Light.dc.html`, bad.length ? 'UNMAPPED: ' + bad.join(' ') : 'ok');
}
process.exit(problems ? 1 : 0);
