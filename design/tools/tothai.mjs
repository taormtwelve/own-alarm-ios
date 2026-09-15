// Generates the Thai artboards (*Th.dc.html) from the dark English ones.
//
//   node design/tools/tothai.mjs && node design/tools/tolight.mjs
//
// Edit only the English dark artboards: this rewrites every *Th.dc.html, and tolight
// then writes the light twin of each. Every text node is looked up in THAI — the
// app's own Thai (ios/OwnAlarm/Model/Language.swift) plus the mockups' sample
// content. Text left in English is reported and fails the run.
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = join(dirname(fileURLToPath(import.meta.url)), '..');
const files = ['Main', 'EditAlarm', 'SoundSheet', 'Ringing', 'LockScreen', 'Sounds', 'Settings'];

// Names that read the same in Thai.
const KEEP = new Set(['English', 'OwnAlarm']);

// The editor's day pills, Sunday first, in page order — their English letters repeat.
const PILLS = ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'];

// Text nodes as written in the HTML, entities included.
const THAI = {
  // Tabs and titles
  'Alarms': 'นาฬิกาปลุก',
  'Sounds': 'เสียง',
  'Settings': 'การตั้งค่า',
  'Sound &amp; loudness': 'เสียงและความดัง',

  // Sample alarms: a Thai user's own tasks
  'Morning run': 'วิ่งตอนเช้า',
  'Take medication': 'กินยา',
  'Stand-up call': 'ประชุมสแตนด์อัพ',
  'Wind down &amp; charge phone': 'ผ่อนคลายและชาร์จโทรศัพท์',
  'Morning run &middot; 85%': 'วิ่งตอนเช้า &middot; 85%',
  '4 active &middot; volume set per task': 'เปิดอยู่ 4 รายการ &middot; ตั้งระดับเสียงแยกตามการปลุก',

  // Repeat days
  'Every day': 'ทุกวัน',
  'Mon &ndash; Fri': 'จันทร์ &ndash; ศุกร์',
  'Tue, Thu': 'อ., พฤ.',
  'Sun': 'อา.',

  // Tones
  'Siren': 'ไซเรน',
  'Marimba': 'มาริมบา',
  'Soft bell': 'ระฆังเบา',
  'Whisper': 'กระซิบ',
  'Harsh &middot; peaks fast &middot; 3s loop': 'แหลม &middot; ดังขึ้นเร็ว &middot; วน 3 วินาที',
  'Warm &middot; even &middot; 6s loop': 'นุ่ม &middot; สม่ำเสมอ &middot; วน 6 วินาที',
  'Quiet &middot; long decay &middot; 8s loop': 'เบา &middot; ค่อยๆ จางยาว &middot; วน 8 วินาที',
  'Barely there &middot; for night tasks': 'แผ่วเบา &middot; สำหรับการปลุกกลางคืน',
  'Harsh &middot; used by 1 alarm': 'แหลม &middot; ใช้กับนาฬิกาปลุก 1 รายการ',
  'Warm &middot; used by 1 alarm': 'นุ่ม &middot; ใช้กับนาฬิกาปลุก 1 รายการ',
  'Long decay &middot; used by 1 alarm': 'จางยาว &middot; ใช้กับนาฬิกาปลุก 1 รายการ',
  'Barely there &middot; used by 1 alarm': 'แผ่วเบา &middot; ใช้กับนาฬิกาปลุก 1 รายการ',

  // Editing an alarm
  'Cancel': 'ยกเลิก',
  'Save': 'บันทึก',
  'Task': 'การปลุก',
  'Repeat': 'ทำซ้ำ',
  'Sound': 'เสียง',
  'Volume for this task': 'ระดับเสียงของการปลุกนี้',
  'The maximum volume depends on your Ringer &amp; Alerts volume &mdash; adjust it in Settings &rsaquo; Sounds &amp; Haptics.':
    'ระดับเสียงสูงสุดขึ้นอยู่กับระดับเสียงเรียกเข้าและการแจ้งเตือนของคุณ &mdash; สามารถปรับได้ที่ การตั้งค่า &rsaquo; เสียงและการสั่น',
  'Test real alarm at 85%': 'ทดสอบปลุกจริงที่ 85%',
  'Test real alarm at 50%': 'ทดสอบปลุกจริงที่ 50%',
  'Vibrate': 'สั่น',
  "Buzzes while it rings &middot; on the Lock Screen, iOS's Haptics setting decides":
    'สั่นขณะปลุก &middot; บนหน้าจอล็อก ขึ้นอยู่กับการตั้งค่าการสั่นของ iOS',
  'Snooze': 'เลื่อนปลุก',
  'Snooze length': 'ระยะเลื่อนปลุก',
  '9 min': '9 นาที',

  // Sound sheet and Sounds tab
  'Alarm tones': 'เสียงปลุก',
  'Done': 'เสร็จสิ้น',
  'Music or Files': 'เพลงหรือไฟล์',
  'All tones': 'เสียงทั้งหมด',
  'Try it for real': 'ลองฟังของจริง',
  'Hear a tone for real before you trust it to wake you': 'ฟังเสียงจริงให้มั่นใจก่อนใช้ปลุก',
  'Tap a tone below to hear it &middot; set a level and it rings in 5 s as a real alarm. The maximum volume depends on your Ringer &amp; Alerts volume &mdash; adjust it in Settings &rsaquo; Sounds &amp; Haptics.':
    'แตะเสียงด้านล่างเพื่อฟัง &middot; ปรับระดับเสียง แล้วทดลองปลุกในอีก 5 วินาที ระดับเสียงสูงสุดขึ้นอยู่กับระดับเสียงเรียกเข้าและการแจ้งเตือนของคุณ &mdash; สามารถปรับได้ที่ การตั้งค่า &rsaquo; เสียงและการสั่น',
  'Test level': 'ระดับทดสอบ',
  'Add a song or recording': 'เพิ่มเพลงหรือเสียงบันทึก',
  'From Music or Files': 'จากเพลงหรือไฟล์',

  // Ringing and snoozed
  'Alarm ringing': 'นาฬิกากำลังปลุก',
  'Siren, at full task volume': 'ไซเรน ที่ระดับเสียงเต็มของการปลุก',
  'Snooze 9 min': 'เลื่อนปลุก 9 นาที',
  'Slide to stop': 'เลื่อนเพื่อหยุด',
  'Monday 14 September': 'วันจันทร์ที่ 14 กันยายน',
  'Snoozed': 'เลื่อนปลุกอยู่',
  'Morning run &middot; snoozed': 'วิ่งตอนเช้า &middot; เลื่อนปลุกแล้ว',
  'Rings again at 06:54 &middot; in 9 min': 'ปลุกอีกครั้งเวลา 06:54 &middot; อีก 9 นาที',
  'now': 'ตอนนี้',

  // Settings
  'Clock': 'นาฬิกา',
  'Time format': 'รูปแบบเวลา',
  '24-hour': '24 ชั่วโมง',
  'AM / PM': '12 ชั่วโมง',
  'Match device': 'ตามเครื่อง',
  'When an alarm rings': 'เมื่อนาฬิกาปลุกดัง',
  'Show on Lock Screen': 'แสดงบนหน้าจอล็อก',
  'Off, the alarm only takes over inside the app': 'หากปิด การปลุกจะแสดงเฉพาะในแอป',
  'Alarms permission': 'สิทธิ์นาฬิกาปลุก',
  'What lets an alarm ring through Silent': 'สิ่งที่ทำให้นาฬิกาปลุกดังผ่านโหมดเงียบ',
  'Allowed': 'อนุญาตแล้ว',
  'Appearance': 'ลักษณะที่ปรากฏ',
  'Dark': 'มืด',
  'Light': 'สว่าง',
  'Auto': 'อัตโนมัติ',
  'Language': 'ภาษา',
};

// A Thai font beside each face, for the glyphs the Latin faces lack.
const COMMON = [
  ['&display=swap', '&family=Noto+Sans+Thai:wght@400;500;600;700&display=swap'],
  ["font-family: 'Instrument Sans', system-ui", "font-family: 'Instrument Sans', 'Noto Sans Thai', system-ui"],
  ["font-family: 'Bricolage Grotesque', 'Helvetica Neue'", "font-family: 'Bricolage Grotesque', 'Noto Sans Thai', 'Helvetica Neue'"],
  ['<html>', '<html lang="th">'],
];

// Settings in Thai has ไทย chosen.
const segment = (label, chosen) => chosen
  ? `<div style="flex-grow: 1; height: 40px; border-radius: 14px; background: #332D28; display: flex; align-items: center; justify-content: center;">\n      <span style="font-size: 14px; font-weight: 600;">${label}</span>`
  : `<div style="flex-grow: 1; height: 40px; border-radius: 14px; display: flex; align-items: center; justify-content: center;">\n      <span style="font-size: 14px; font-weight: 500; color: #8A8279;">${label}</span>`;
const EXTRA = {
  Settings: [[
    `${segment('English', true)}\n    </div>\n    ${segment('ไทย', false)}`,
    `${segment('English', false)}\n    </div>\n    ${segment('ไทย', true)}`,
  ]],
};

let problems = 0;
for (const name of files) {
  const raw = readFileSync(join(DIR, `${name}.dc.html`), 'utf8');
  const crlf = raw.includes('\r\n');
  let s = raw.replace(/\r\n/g, '\n');
  for (const [from, to] of [...COMMON, ...(EXTRA[name] || [])]) {
    if (!s.includes(from)) { console.log(`${name}: not found: ${from.slice(0, 60)}`); problems++; }
    s = s.split(from).join(to);
  }

  const start = s.indexOf('</helmet>');
  let pills = 0;
  const left = [];
  const body = s.slice(start).replace(/>([^<>]+)</g, (whole, text) => {
    const words = text.trim();
    if (!/[A-Za-z]/.test(words.replace(/&[a-z]+;/g, ''))) return whole;
    if (/^[SMTWF]$/.test(words) && pills < PILLS.length) return `>${text.replace(words, () => PILLS[pills++])}<`;
    if (KEEP.has(words)) return whole;
    if (THAI[words] !== undefined) return `>${text.replace(words, () => THAI[words])}<`;
    left.push(words);
    return whole;
  });
  s = s.slice(0, start) + body;
  if (pills !== 0 && pills !== PILLS.length) left.push(`${pills} day pills, expected ${PILLS.length}`);
  if (left.length) problems++;

  writeFileSync(join(DIR, `${name}Th.dc.html`), crlf ? s.replace(/\n/g, '\r\n') : s);
  console.log(`${name}Th.dc.html`, left.length ? 'LEFT IN ENGLISH: ' + left.join(' | ') : 'ok');
}
if (problems) process.exit(1);
