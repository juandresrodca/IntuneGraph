// Renders the IntuneGraph demo graph to an animated GIF for the README.
// Reuses the same force-directed layout + styling as the in-tool HTML viewer,
// but runs headless with @napi-rs/canvas and encodes with gifenc (no ffmpeg).
//
//   npm install && npm run build   ->  ../../docs/img/demo.gif

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createCanvas } from '@napi-rs/canvas';
import gifenc from 'gifenc';
const { GIFEncoder, quantize, applyPalette } = gifenc;

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT = join(__dirname, '..', '..', 'docs', 'img', 'demo.gif');

const W = 900, H = 500;
const BG = '#0a0e16';
const TYPE_COLORS = {
  Device: '#58a6ff', User: '#c792ea', Group: '#9fef00', Filter: '#d2a8ff',
  ConfigPolicy: '#ffb454', CompliancePolicy: '#56d4dd', App: '#ff7b72', Script: '#f778ba', Builtin: '#c9d4e3'
};
const TYPE_RADIUS = { Device: 6, User: 6, Group: 11, Filter: 8, ConfigPolicy: 12, CompliancePolicy: 12, App: 12, Script: 9, Builtin: 13 };
const LABELLED = new Set(['Group', 'App', 'ConfigPolicy', 'CompliancePolicy', 'Script', 'Filter', 'Builtin']);

const graph = JSON.parse(readFileSync(join(__dirname, 'graph.json'), 'utf8').replace(/^﻿/, ''));
const nodeById = {};
const nodes = graph.nodes.map((n, i) => {
  const a = (i / graph.nodes.length) * Math.PI * 2;
  const o = { ...n, x: Math.cos(a) * 160 + (Math.random() - 0.5) * 30, y: Math.sin(a) * 160 + (Math.random() - 0.5) * 30, vx: 0, vy: 0 };
  nodeById[n.id] = o; return o;
});
const edges = graph.edges.filter(e => nodeById[e.from] && nodeById[e.to]);

let alpha = 1;
function step() {
  for (let i = 0; i < nodes.length; i++) {
    const a = nodes[i];
    for (let j = i + 1; j < nodes.length; j++) {
      const b = nodes[j];
      let dx = a.x - b.x, dy = a.y - b.y; let d2 = dx * dx + dy * dy || 0.01;
      const rep = 2600 * alpha / d2; const d = Math.sqrt(d2);
      const fx = dx / d * rep, fy = dy / d * rep;
      a.vx += fx; a.vy += fy; b.vx -= fx; b.vy -= fy;
    }
  }
  for (const e of edges) {
    const a = nodeById[e.from], b = nodeById[e.to];
    let dx = b.x - a.x, dy = b.y - a.y; const d = Math.sqrt(dx * dx + dy * dy) || 0.01;
    const target = e.type === 'memberOf' ? 70 : 120;
    const f = (d - target) * 0.02 * alpha;
    const fx = dx / d * f, fy = dy / d * f;
    a.vx += fx; a.vy += fy; b.vx -= fx; b.vy -= fy;
  }
  for (const n of nodes) { n.vx *= 0.9; n.vy *= 0.9; n.x += n.vx; n.y += n.vy; n.vx *= 0.5; n.vy *= 0.5; }
  alpha *= 0.985; if (alpha < 0.02) alpha = 0.02;
}

// Camera that fits the graph into the frame (with padding), eased over time.
let cam = null;
function fitCamera(ease) {
  let minx = Infinity, miny = Infinity, maxx = -Infinity, maxy = -Infinity;
  for (const n of nodes) { minx = Math.min(minx, n.x); miny = Math.min(miny, n.y); maxx = Math.max(maxx, n.x); maxy = Math.max(maxy, n.y); }
  const pad = 70, gw = (maxx - minx) || 1, gh = (maxy - miny) || 1;
  const scale = Math.min((W - pad * 2) / gw, (H - 120) / gh, 2.2);
  const cx = (minx + maxx) / 2, cy = (miny + maxy) / 2;
  const target = { scale, cx, cy };
  if (!cam || !ease) { cam = target; return; }
  cam.scale += (target.scale - cam.scale) * ease;
  cam.cx += (target.cx - cam.cx) * ease;
  cam.cy += (target.cy - cam.cy) * ease;
}

const canvas = createCanvas(W, H);
const ctx = canvas.getContext('2d');

function drawFrame(highlightId) {
  ctx.fillStyle = BG; ctx.fillRect(0, 0, W, H);

  // radial glow washes (blue top-right, green bottom-left)
  let g = ctx.createRadialGradient(W * 0.85, -40, 0, W * 0.85, -40, 520);
  g.addColorStop(0, 'rgba(88,166,255,0.10)'); g.addColorStop(1, 'rgba(88,166,255,0)');
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
  g = ctx.createRadialGradient(-30, H + 40, 0, -30, H + 40, 480);
  g.addColorStop(0, 'rgba(159,239,0,0.06)'); g.addColorStop(1, 'rgba(159,239,0,0)');
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);

  // (grid omitted in the GIF: anti-aliased 1px lines inflate the palette and file
  //  size across every frame; the live HTML viewer keeps the grid, where it's free.)

  // header: green accent bar + wordmark
  ctx.fillStyle = '#9fef00'; ctx.fillRect(0, 0, 3, 52);
  ctx.fillStyle = '#9fef00'; ctx.font = 'bold 18px sans-serif';
  ctx.fillText('IntuneGraph', 24, 34);
  ctx.fillStyle = '#7c8aa0'; ctx.font = '13px sans-serif';
  ctx.fillText(`Silver Chariot Corporate  ·  ${nodes.length} nodes · ${edges.length} edges`, 138, 34);

  ctx.save();
  ctx.translate(W / 2, H / 2 + 28);
  ctx.scale(cam.scale, cam.scale);
  ctx.translate(-cam.cx, -cam.cy);

  const focus = highlightId ? neighborhood(highlightId) : null;

  for (const e of edges) {
    const a = nodeById[e.from], b = nodeById[e.to];
    const dim = focus && !(focus.has(a.id) && focus.has(b.id));
    ctx.globalAlpha = dim ? 0.06 : 0.55;
    ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y);
    if (e.type === 'memberOf') { ctx.strokeStyle = '#2f3f61'; ctx.lineWidth = 0.7 / cam.scale + 0.3; ctx.setLineDash([]); }
    else if (e.type === 'filteredBy') { ctx.strokeStyle = '#ffb454'; ctx.lineWidth = 1; ctx.setLineDash([1.5, 3]); }
    else if (e.properties && e.properties.mode === 'exclude') { ctx.strokeStyle = '#ff7b72'; ctx.lineWidth = 1.4; ctx.setLineDash([5, 4]); }
    else { ctx.strokeStyle = '#9fef00'; ctx.lineWidth = 1.4; ctx.setLineDash([]); }
    ctx.stroke();
  }
  ctx.setLineDash([]);

  for (const n of nodes) {
    const dim = focus && !focus.has(n.id);
    const r = TYPE_RADIUS[n.type] || 8;
    ctx.globalAlpha = dim ? 0.14 : 1;
    ctx.beginPath(); ctx.arc(n.x, n.y, r, 0, Math.PI * 2);
    ctx.fillStyle = TYPE_COLORS[n.type] || '#ccc'; ctx.fill();
    if (n.id === highlightId) { ctx.lineWidth = 2.5 / cam.scale; ctx.strokeStyle = '#fff'; ctx.stroke(); }
    else if (n.properties && n.properties.missing) { ctx.lineWidth = 2 / cam.scale; ctx.strokeStyle = '#ff7b72'; ctx.stroke(); }
    if (!dim && LABELLED.has(n.type) && cam.scale > 0.45) {
      ctx.globalAlpha = 0.92; ctx.fillStyle = '#c9d4e3';
      ctx.font = `${Math.max(9, 10 / cam.scale)}px sans-serif`;
      ctx.fillText(n.name || n.id, n.x + r + 3, n.y + 3.5);
    }
  }
  ctx.restore();
  ctx.globalAlpha = 1;

  // caption
  ctx.fillStyle = '#56657d'; ctx.font = '12px sans-serif';
  ctx.fillText('github.com/juandresrodca/IntuneGraph', 24, H - 18);
}
function neighborhood(id) {
  const s = new Set([id]);
  for (const e of edges) { if (e.from === id) s.add(e.to); if (e.to === id) s.add(e.from); }
  return s;
}

// ---- render frames ----
const gif = GIFEncoder();
function push(delay) {
  const { data } = ctx.getImageData(0, 0, W, H);
  const palette = quantize(data, 256);
  const index = applyPalette(data, palette);
  gif.writeFrame(index, W, H, { palette, delay });
}

// warm the layout a little before the first captured frame
for (let i = 0; i < 20; i++) step();
fitCamera();

// phase 1: settling
for (let f = 0; f < 34; f++) { step(); step(); fitCamera(0.25); drawFrame(null); push(70); }
// hold settled
for (let i = 0; i < 6; i++) step();
fitCamera(0.4);
for (let f = 0; f < 6; f++) { drawFrame(null); push(90); }
// phase 2: highlight a couple of key nodes (the "why" story)
const finance = nodes.find(n => n.name === 'SG-Finance');
const lob = nodes.find(n => n.name === 'LOB Finance App');
for (const hl of [finance, lob]) {
  if (!hl) continue;
  for (let f = 0; f < 12; f++) { drawFrame(hl.id); push(f < 2 ? 60 : 120); }
}
// return to full view, hold
for (let f = 0; f < 8; f++) { drawFrame(null); push(120); }

gif.finish();
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, gif.bytes());
const kb = (gif.bytes().length / 1024).toFixed(0);
console.log(`Wrote ${OUT} (${kb} KB, ${nodes.length} nodes)`);
