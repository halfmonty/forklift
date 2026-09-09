import assert from "node:assert/strict";
import { readFileSync, statSync } from "node:fs";

const [wasmPath, htmlPath, jsPath, cssPath] = process.argv.slice(2);
for (const path of [wasmPath, htmlPath, jsPath, cssPath]) {
  assert.ok(path, "expected paths to the built browser artifacts");
  assert.ok(statSync(path).size > 0, `${path} must not be empty`);
}
const html = readFileSync(htmlPath, "utf8");
const javascript = readFileSync(jsPath, "utf8");
assert.match(html, /<canvas[^>]+width="400"[^>]+height="240"/);
assert.match(html, /id="screen"/);
assert.match(javascript, /KeyM/);
assert.match(javascript, /localStorage/);

const queuedNotes = [];
let audioSequenceStarts = 0;
let audioSequenceResets = 0;
let tempo = 0;
let loopSettings;
const imports = {
  env: {
    webRuntimeError(code) {
      throw new Error(`WASM runtime error ${code}`);
    },
    webStorageRead() { return -1; },
    webStorageWrite() { return 0; },
    webStorageClear() { return 0; },
    webAudioPlayNote() {},
    webAudioResetSequence() { audioSequenceResets += 1; },
    webAudioQueueSequenceNote(...event) { queuedNotes.push(event); },
    webAudioQueueSequenceControlPoint() {},
    webAudioSetSequenceTempo(value) { tempo = value; },
    webAudioSetSequenceLoops(start, end, loops) { loopSettings = [start, end, loops]; },
    webAudioStartSequence() { audioSequenceStarts += 1; },
    webAudioStopSequence() {},
    webAudioStopSynth() {},
  },
};

const { instance } = await WebAssembly.instantiate(readFileSync(wasmPath), imports);
const wasm = instance.exports;
assert.equal(wasm.webInit(), 1, "game initialization succeeds");
assert.equal(audioSequenceResets, 1, "the PDNA sequence is initialized once");
assert.equal(audioSequenceStarts, 1, "the PDNA sequence starts once");
assert.equal(queuedNotes.length, 57, "the complete PDNA song is queued");
assert.ok(tempo > 0, "the sequence has a positive tempo");
assert.deepEqual(loopSettings, [0, 63, 0], "the PDNA loop is preserved");
assert.ok(queuedNotes.some(([waveform]) => waveform === 3), "the percussion voice is queued");
const vibratoLead = queuedNotes.find((event) => event[10] === 2 && event[11] === 3);
assert.ok(vibratoLead, "lead notes carry their sine vibrato configuration");
assert.ok(Math.abs(vibratoLead[13] - (0.2 / 12)) < 0.0001, "vibrato depth is preserved");
assert.ok(Math.abs(vibratoLead[15] - 0.08) < 0.0001, "vibrato ramp is preserved");

wasm.webSetElapsedTime(16.667);
wasm.webSetInput(0, 0);
assert.equal(wasm.webFrame(), 1, "the initial game frame renders");
assert.equal(wasm.webFramebufferLen(), 52 * 240, "the framebuffer uses Playdate row stride");

const framebuffer = new Uint8Array(wasm.memory.buffer, wasm.webFramebufferPtr(), wasm.webFramebufferLen());
assert.ok(framebuffer.some((byte) => byte !== 0), "the initial framebuffer is nonblank");

function framebufferHash() {
  let hash = 0x811c9dc5;
  for (const byte of framebuffer) {
    hash ^= byte;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return `0x${hash.toString(16).padStart(8, "0")}`;
}

function renderFrame(buttons = 0) {
  wasm.webSetElapsedTime(16.667);
  wasm.webSetInput(buttons, 0);
  assert.equal(wasm.webFrame(), 1, "a visual-regression frame renders");
}

// These are FNV-1a hashes of the one-bit framebuffer, before its browser-only
// RGBA conversion. A rendering change must intentionally update a baseline.
assert.equal(framebufferHash(), "0xe7ad7bae", "title framebuffer baseline");
renderFrame(1 << 5);
renderFrame();
assert.equal(framebufferHash(), "0x24e5d444", "briefing framebuffer baseline");
renderFrame(1 << 5);
renderFrame();
renderFrame(1 << 5);
renderFrame();
assert.equal(framebufferHash(), "0x0398c528", "gameplay framebuffer baseline");

wasm.webActivateMenu(0);
wasm.webSetMenuValue(1, 2);
assert.equal(wasm.webFrame(), 1, "service-menu changes do not halt rendering");

console.log(`web integration: ${queuedNotes.length} PDNA events, ${framebuffer.length}-byte framebuffer`);
