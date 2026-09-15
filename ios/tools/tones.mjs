// Synthesizes the six tones added after the first four: Sunrise, Music box, Birdsong,
// Chimes, Sonar and Beeps.
//
//   node ios/tools/tones.mjs      writes ios/OwnAlarm/Resources/<id>.wav
//
// Mono, 44.1 kHz, 16-bit PCM — the format of the original tones. Each file starts and
// ends in silence, so it loops without a click, and is normalised to a peak in the
// originals' range (0.4–0.65): when an alarm rings the app rescales every tone to the
// same ceiling anyway (ScaledSound), so this only keeps previews level with the rest.
// Seeded, so the files come out the same on every run.
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const OUT = join(dirname(fileURLToPath(import.meta.url)), '..', 'OwnAlarm', 'Resources');
const RATE = 44100;
const TAU = Math.PI * 2;

const track = (seconds) => new Float64Array(Math.round(seconds * RATE));

/** Adds a voice `fn(t)` — t in seconds from `at` — for `length` seconds. */
function add(buf, at, length, fn) {
  const start = Math.round(at * RATE);
  const n = Math.round(length * RATE);
  for (let i = 0; i < n && start + i < buf.length; i++) buf[start + i] += fn(i / RATE, i);
}

/** A few milliseconds in and out, so no voice starts or stops with a click. */
const edges = (t, length, rise = 0.004, fall = 0.012) => Math.max(0, Math.min(1, t / rise, (length - t) / fall));

/** "A4" → 440 Hz. */
function hz(name) {
  const [, letter, sharp, octave] = /^([A-G])(#?)(\d)$/.exec(name);
  const semis = { C: -9, D: -7, E: -5, F: -4, G: -2, A: 0, B: 2 }[letter] + (sharp ? 1 : 0) + (Number(octave) - 4) * 12;
  return 440 * 2 ** (semis / 12);
}

function seeded(seed) {
  let s = seed >>> 0;
  return () => ((s = (Math.imul(s, 1664525) + 1013904223) >>> 0) / 2 ** 32);
}

/** Scales to `peak` and fades the last `tail` seconds to exact silence. */
function finish(buf, peak, tail = 0.05) {
  let max = 0;
  for (const v of buf) max = Math.max(max, Math.abs(v));
  const gain = peak / max;
  const fadeFrom = buf.length - Math.round(tail * RATE);
  for (let i = 0; i < buf.length; i++) {
    const fade = i < fadeFrom ? 1 : (buf.length - 1 - i) / (buf.length - 1 - fadeFrom);
    buf[i] *= gain * fade;
  }
  return buf;
}

// --- The tones -------------------------------------------------------------------

/** A warm major-ninth chord that swells from nothing over six seconds, then settles. */
function sunrise() {
  const length = 8;
  const buf = track(length);
  const chord = ['C4', 'G4', 'B4', 'D5', 'E5'].map(hz);
  add(buf, 0, length, (t) => {
    const swell = t < 6 ? (t / 6) ** 2 : 0.5 * (1 + Math.cos(Math.PI * (t - 6) / 2));
    const breathe = 1 + 0.08 * Math.sin(TAU * 0.5 * t);
    let v = 0;
    chord.forEach((f, k) => {
      for (const detune of [-0.6, 0.6]) {
        const p = TAU * (f + detune) * t + k;
        v += Math.sin(p) + 0.22 * Math.sin(2 * p) + 0.07 * Math.sin(3 * p);
      }
    });
    return v * swell * breathe;
  });
  return finish(buf, 0.45, 0.2);
}

/** A little four-bar tune on music-box tines. */
function musicBox() {
  const length = 6.5;
  const buf = track(length);
  const tune = [
    ['G5', 0.0], ['C6', 0.35], ['E6', 0.7],
    ['D6', 1.05], ['C6', 1.4], ['A5', 1.75],
    ['G5', 2.1], ['A5', 2.45], ['C6', 2.8],
    ['E6', 3.15], ['D6', 3.5], ['C6', 3.85],
  ];
  const partials = [[1, 1, 0.9], [2, 0.4, 0.35], [3.01, 0.18, 0.2], [5.4, 0.08, 0.08]];
  for (const [name, at] of tune) {
    const f = hz(name);
    const ring = 2.4;
    add(buf, at, ring, (t) => {
      let v = 0;
      for (const [ratio, amp, decay] of partials) v += amp * Math.exp(-t / decay) * Math.sin(TAU * f * ratio * t);
      return v * edges(t, ring, 0.002, 0.05);
    });
  }
  return finish(buf, 0.45, 0.3);
}

/** Chirps and trills: quick sweeps high in the treble, in phrases with rests between. */
function birdsong() {
  const length = 6;
  const buf = track(length);
  const random = seeded(7);
  const chirp = (at, from, to, dur, amp = 1) => {
    let phase = 0;
    add(buf, at, dur, (t) => {
      const f = from + (to - from) * (t / dur);
      phase += TAU * f / RATE;
      const shape = Math.sin(Math.PI * t / dur) ** 2;
      return amp * shape * (Math.sin(phase) + 0.1 * Math.sin(2 * phase));
    });
  };
  // Three rising calls.
  for (let k = 0; k < 3; k++) chirp(0.2 + k * 0.13, 2700 + random() * 200, 3900 + random() * 300, 0.08);
  // A trill.
  for (let k = 0; k < 9; k++) chirp(1.2 + k * 0.055, k % 2 ? 4300 : 3900, k % 2 ? 3900 : 4300, 0.045, 0.8);
  // Two long falling whistles.
  chirp(2.5, 4500, 2900, 0.2);
  chirp(2.85, 4300, 2800, 0.22, 0.9);
  // The rising calls again, higher.
  for (let k = 0; k < 3; k++) chirp(3.8 + k * 0.12, 3000 + random() * 200, 4300 + random() * 300, 0.07);
  // A lower trill to close.
  for (let k = 0; k < 7; k++) chirp(4.75 + k * 0.06, k % 2 ? 3300 : 3000, k % 2 ? 3000 : 3300, 0.05, 0.7);
  return finish(buf, 0.5);
}

/** Tubular chimes: a rising arpeggio, then an answer, each note ringing out. */
function chimes() {
  const length = 5;
  const buf = track(length);
  const strikes = [['C6', 0], ['E6', 0.22], ['G6', 0.44], ['C7', 0.66], ['G6', 1.8], ['C7', 2.02]];
  const partials = [[1, 1, 1.4], [2.76, 0.5, 0.8], [5.4, 0.25, 0.4], [8.93, 0.12, 0.2]];
  for (const [name, at] of strikes) {
    const f = hz(name);
    const ring = length - at;
    add(buf, at, ring, (t) => {
      let v = 0;
      for (const [ratio, amp, decay] of partials) {
        if (f * ratio > 16000) continue;
        v += amp * Math.exp(-t / decay) * Math.sin(TAU * f * ratio * t);
      }
      return v * edges(t, ring, 0.002, 0.3);
    });
  }
  return finish(buf, 0.55, 0.5);
}

/** A clear ping every 1.5 seconds, each with two fading echoes. */
function sonar() {
  const length = 6;
  const buf = track(length);
  const ping = (at, amp) => add(buf, at, 1.2, (t) => {
    const v = Math.sin(TAU * 1320 * t) + 0.15 * Math.exp(-t / 0.08) * Math.sin(TAU * 2640 * t);
    return amp * v * Math.exp(-t / 0.25) * edges(t, 1.2, 0.003, 0.05);
  });
  for (const at of [0, 1.5, 3, 4.5]) {
    ping(at, 1);
    ping(at + 0.32, 0.3);
    ping(at + 0.64, 0.1);
  }
  return finish(buf, 0.55, 0.1);
}

/** The classic digital alarm: four short beeps, a rest, again. */
function beeps() {
  const length = 4;
  const buf = track(length);
  const f = 2400;
  for (let group = 0; group < 4; group++) {
    for (let k = 0; k < 4; k++) {
      const at = group + k * 0.16;
      add(buf, at, 0.09, (t) => {
        // A square wave built from its first odd harmonics, so it stays clean.
        let v = 0;
        for (const n of [1, 3, 5, 7]) v += Math.sin(TAU * f * n * t) / n;
        return v * edges(t, 0.09, 0.003, 0.004);
      });
    }
  }
  return finish(buf, 0.6);
}

// --- Writing ---------------------------------------------------------------------

function wav(samples) {
  const data = Buffer.alloc(samples.length * 2);
  samples.forEach((v, i) => data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, v)) * 32767), i * 2));
  const head = Buffer.alloc(44);
  head.write('RIFF', 0);
  head.writeUInt32LE(36 + data.length, 4);
  head.write('WAVE', 8);
  head.write('fmt ', 12);
  head.writeUInt32LE(16, 16);
  head.writeUInt16LE(1, 20);        // linear PCM
  head.writeUInt16LE(1, 22);        // mono
  head.writeUInt32LE(RATE, 24);
  head.writeUInt32LE(RATE * 2, 28);
  head.writeUInt16LE(2, 32);
  head.writeUInt16LE(16, 34);
  head.write('data', 36);
  head.writeUInt32LE(data.length, 40);
  return Buffer.concat([head, data]);
}

const tones = { sunrise, 'music-box': musicBox, birdsong, chimes, sonar, beeps };
for (const [id, make] of Object.entries(tones)) {
  const samples = make();
  const edge = (from, to) => {
    let max = 0;
    for (let i = from; i < to; i++) max = Math.max(max, Math.abs(samples[i]));
    return max;
  };
  const peak = edge(0, samples.length);
  let sum = 0;
  for (const v of samples) sum += v * v;
  // What loops cleanly: the first and last samples, which meet at the loop point.
  const ends = Math.max(Math.abs(samples[0]), Math.abs(samples[samples.length - 1]));
  writeFileSync(join(OUT, `${id}.wav`), wav(samples));
  console.log(`${id.padEnd(10)} ${(samples.length / RATE).toFixed(1)} s  peak ${peak.toFixed(2)}  rms ${Math.sqrt(sum / samples.length).toFixed(3)}  ends ${ends.toFixed(4)}`);
}
