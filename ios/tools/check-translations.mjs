// Checks the app's Thai against its code.
//
//   node ios/tools/check-translations.mjs
//
// Every line the app shows is English in the code, passed through the language —
// t("Save"), language("Stop"), t.around("…"), .callAsFunction("…"). This finds each of
// those lines, and fails if one has no Thai in OwnAlarm/Model/Language.swift or its
// {0}, {1} differ. It also lists English still written straight into a view, and Thai
// lines nothing uses any more.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const IOS = join(dirname(fileURLToPath(import.meta.url)), '..');
const STR = String.raw`"((?:[^"\\\n]|\\.)*)"`;

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return swiftFiles(path);
    return name.endsWith('.swift') ? [path] : [];
  });
}

// The table: ("English", "Thai") pairs, possibly split over two lines.
const languageFile = readFileSync(join(IOS, 'OwnAlarm/Model/Language.swift'), 'utf8');
const block = languageFile.slice(languageFile.indexOf('static let thaiLines'));
const table = new Map();
const repeated = [];
for (const m of block.matchAll(new RegExp(String.raw`\(\s*${STR}\s*,\s*${STR}\s*\)`, 'g'))) {
  if (table.has(m[1])) repeated.push(m[1]);
  table.set(m[1], m[2]);
}

const sources = [...swiftFiles(join(IOS, 'OwnAlarm')), ...swiftFiles(join(IOS, 'OwnAlarmWidgets'))];
const calls = new RegExp(String.raw`(?:\bt|\blanguage|\.callAsFunction|\.around)\(\s*${STR}`, 'g');
const straight = new RegExp(String.raw`(?:\bText|\bButton|\bLabel|\bToggle|\bStepper|\bDatePicker|\bTextField|\bsection|\.navigationTitle|\.accessibilityLabel|\.accessibilityValue|\.alert|\btitle:|\bsubtitle:|\bSectionLabel\(text:)\(?\s*${STR}`, 'g');

const used = new Set();
const missing = [];
const interpolated = [];
const english = [];
const literals = new Set();
for (const file of sources) {
  const code = readFileSync(file, 'utf8');
  const where = relative(IOS, file).replace(/\\/g, '/');
  for (const m of code.matchAll(new RegExp(STR, 'g'))) literals.add(m[1]);
  if (file.endsWith('Language.swift')) continue;
  for (const m of code.matchAll(calls)) {
    const key = m[1];
    if (key.includes('\\(')) { interpolated.push(`${where}: ${key}`); continue; }
    used.add(key);
    if (!table.has(key)) missing.push(`${where}: ${key}`);
  }
  for (const m of code.matchAll(straight)) {
    // App Intents parameter titles are metadata, never shown (the intents are not
    // discoverable); an interpolation such as \(alarm.volumePercent)% is not words.
    if (code.slice(Math.max(0, m.index - 11), m.index) === '@Parameter(') continue;
    const words = m[1].replace(/\\\(.*\)/g, '');
    if (/[A-Za-z]{2}/.test(words) && !words.startsWith('ownalarm')) english.push(`${where}: ${m[1]}`);
  }
}

const placeholders = (s) => (s.match(/\{\d+\}/g) || []).sort().join(' ');
const mismatched = [...table].filter(([k, v]) => placeholders(k) !== placeholders(v)).map(([k]) => k);
const unused = [...table.keys()].filter((k) => !used.has(k) && !literals.has(k));

const report = (title, items) => {
  if (!items.length) return;
  console.log(`\n${title} (${items.length})`);
  for (const item of items) console.log(`  ${item}`);
};
console.log(`${table.size} Thai lines; ${used.size} lines translated through the language in code.`);
report('NO THAI for', missing);
report('INTERPOLATED key (use {0} instead)', interpolated);
report('PLACEHOLDERS differ', mismatched);
report('REPEATED in the table', repeated);
report('English written straight into a view', english);
report('Thai lines nothing uses', unused);
const failed = missing.length + interpolated.length + mismatched.length + repeated.length + english.length;
console.log(failed ? '\nFAIL' : '\nOK');
process.exit(failed ? 1 : 0);
