// Draws the app icon — a minimal, thin-outline alarm clock — and writes the three
// variants iOS uses (light, dark, tinted) into the asset catalog.
//
//   node design/tools/appicon.mjs [--preview path/to/preview.png]
//
// Pure Node, no image libraries: every shape is a signed distance, sampled 4×4 per
// pixel for smooth edges, and the result is written as an opaque RGB PNG (iOS masks
// the corners itself). The same icon is what notifications show beside the app name.
import { writeFileSync } from 'node:fs';
import { deflateSync } from 'node:zlib';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const OUT = join(ROOT, 'ios/OwnAlarm/Assets.xcassets/AppIcon.appiconset');
const SIZE = 1024;

// ---- Geometry (on the 1024 canvas) -------------------------------------------------
// One stroke weight throughout: thin enough to read as outline, thick enough to
// survive the 40 px notification icon.
const STROKE = 40;
const C = { x: 512, y: 566 };          // clock centre, a little low to leave room for the bells
const R = 292;                          // face radius
const deg = d => (d * Math.PI) / 180;

// Screen angles: 0° points right, angles grow clockwise (y is down).
const shapes = [
  { kind: 'ring', cx: C.x, cy: C.y, r: R },
  // Hands at ten past ten's minimal cousin: hour up, minute to the right.
  { kind: 'segment', ax: C.x, ay: C.y, bx: C.x, by: C.y - 150 },
  { kind: 'segment', ax: C.x, ay: C.y, bx: C.x + 112, by: C.y },
  // Two bells: short arcs sitting just off the face, upper left and upper right.
  { kind: 'arc', cx: C.x - 214, cy: C.y - 214, r: 118, from: deg(190), to: deg(280) },
  { kind: 'arc', cx: C.x + 214, cy: C.y - 214, r: 118, from: deg(260), to: deg(350) },
  // Two short feet.
  { kind: 'segment', ax: C.x - 190, ay: C.y + 236, bx: C.x - 244, by: C.y + 300 },
  { kind: 'segment', ax: C.x + 190, ay: C.y + 236, bx: C.x + 244, by: C.y + 300 },
];

function segmentDistance(px, py, s) {
  const vx = s.bx - s.ax, vy = s.by - s.ay;
  const t = Math.max(0, Math.min(1, ((px - s.ax) * vx + (py - s.ay) * vy) / (vx * vx + vy * vy)));
  return Math.hypot(px - (s.ax + t * vx), py - (s.ay + t * vy));
}

function arcDistance(px, py, s) {
  let a = Math.atan2(py - s.cy, px - s.cx);
  if (a < 0) a += 2 * Math.PI;
  const inside = s.from <= s.to ? a >= s.from && a <= s.to : a >= s.from || a <= s.to;
  if (inside) return Math.abs(Math.hypot(px - s.cx, py - s.cy) - s.r);
  // Round caps: distance to the nearer end.
  const ends = [s.from, s.to].map(t => [s.cx + s.r * Math.cos(t), s.cy + s.r * Math.sin(t)]);
  return Math.min(...ends.map(([ex, ey]) => Math.hypot(px - ex, py - ey)));
}

/** Distance from (px, py) to the nearest stroke centre line. */
function distance(px, py) {
  let best = Infinity;
  for (const s of shapes) {
    let d;
    if (s.kind === 'ring') d = Math.abs(Math.hypot(px - s.cx, py - s.cy) - s.r);
    else if (s.kind === 'segment') d = segmentDistance(px, py, s);
    else d = arcDistance(px, py, s);
    if (d < best) best = d;
  }
  return best;
}

// Coverage of the stroke at every pixel, computed once and shared by all variants.
function coverage() {
  const cov = new Float32Array(SIZE * SIZE);
  const half = STROKE / 2;
  const n = 4;
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      // Far from every stroke: skip the supersampling.
      const centre = distance(x + 0.5, y + 0.5);
      if (centre > half + 1.5) continue;
      if (centre < half - 1.5) { cov[y * SIZE + x] = 1; continue; }
      let hit = 0;
      for (let sy = 0; sy < n; sy++) {
        for (let sx = 0; sx < n; sx++) {
          if (distance(x + (sx + 0.5) / n, y + (sy + 0.5) / n) <= half) hit++;
        }
      }
      cov[y * SIZE + x] = hit / (n * n);
    }
  }
  return cov;
}

// ---- Colour -----------------------------------------------------------------------
const hex = h => [(h >> 16) & 255, (h >> 8) & 255, h & 255];
const mix = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);

// Light: the app's amber, lifting slightly towards the top; white line.
// Dark: the app's near-black ink with the amber line. Tinted: grey scale — iOS tints
// by brightness — black ground, white line.
const variants = [
  { file: 'AppIcon.png', top: hex(0xF4A93E), bottom: hex(0xE08B0C), line: hex(0xFFFFFF) },
  { file: 'AppIcon-Dark.png', top: hex(0x1E1A16), bottom: hex(0x12100E), line: hex(0xFFB03A) },
  { file: 'AppIcon-Tinted.png', top: hex(0x141414), bottom: hex(0x000000), line: hex(0xFFFFFF) },
];

function render(v, cov) {
  const px = Buffer.alloc(SIZE * SIZE * 3);
  for (let y = 0; y < SIZE; y++) {
    const ground = mix(v.top, v.bottom, y / (SIZE - 1));
    for (let x = 0; x < SIZE; x++) {
      const c = mix(ground, v.line, cov[y * SIZE + x]);
      const i = (y * SIZE + x) * 3;
      px[i] = Math.round(c[0]); px[i + 1] = Math.round(c[1]); px[i + 2] = Math.round(c[2]);
    }
  }
  return px;
}

// ---- PNG ----------------------------------------------------------------------------
const CRC = new Uint32Array(256).map((_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
function crc32(buf) {
  let c = 0xFFFFFFFF;
  for (const b of buf) c = CRC[(c ^ b) & 255] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}
function png(rgb, w, h) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;   // 8-bit RGB
  const raw = Buffer.alloc(h * (w * 3 + 1));
  for (let y = 0; y < h; y++) rgb.copy(raw, y * (w * 3 + 1) + 1, y * w * 3, (y + 1) * w * 3);
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', ihdr), chunk('IDAT', deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ---- Preview: each variant at home-screen and notification size, corners masked ----
function downsample(rgb, size) {
  const out = Buffer.alloc(size * size * 3), f = SIZE / size;
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const acc = [0, 0, 0]; let n = 0;
    for (let yy = Math.floor(y * f); yy < Math.floor((y + 1) * f); yy++)
      for (let xx = Math.floor(x * f); xx < Math.floor((x + 1) * f); xx++) {
        const i = (yy * SIZE + xx) * 3; acc[0] += rgb[i]; acc[1] += rgb[i + 1]; acc[2] += rgb[i + 2]; n++;
      }
    const o = (y * size + x) * 3; out[o] = acc[0] / n; out[o + 1] = acc[1] / n; out[o + 2] = acc[2] / n;
  }
  return out;
}
function preview(images, path) {
  const tiles = [240, 60];            // home screen, notification
  const gap = 24, w = gap + images.length * (tiles[0] + gap), h = gap * 3 + tiles[0] + tiles[1];
  const canvas = Buffer.alloc(w * h * 3, 235);
  images.forEach((rgb, col) => {
    let top = gap;
    for (const size of tiles) {
      const small = downsample(rgb, size), radius = size * 0.225;
      const left = gap + col * (tiles[0] + gap) + (tiles[0] - size) / 2;
      for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
        const dx = Math.max(radius - x - 0.5, 0, x + 0.5 - (size - radius));
        const dy = Math.max(radius - y - 0.5, 0, y + 0.5 - (size - radius));
        const a = Math.max(0, Math.min(1, radius - Math.hypot(dx, dy) + 0.5));
        const o = ((top + y) * w + left + x) * 3, i = (y * size + x) * 3;
        for (let k = 0; k < 3; k++) canvas[o + k] = canvas[o + k] * (1 - a) + small[i + k] * a;
      }
      top += size + gap;
    }
  });
  writeFileSync(path, png(canvas, w, h));
}

const cov = coverage();
const images = variants.map(v => {
  const rgb = render(v, cov);
  writeFileSync(join(OUT, v.file), png(rgb, SIZE, SIZE));
  console.log('wrote', v.file);
  return rgb;
});
const at = process.argv.indexOf('--preview');
if (at > 0 && process.argv[at + 1]) {
  preview(images, process.argv[at + 1]);
  console.log('preview', process.argv[at + 1]);
}
