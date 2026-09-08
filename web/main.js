const WIDTH = 400;
const HEIGHT = 240;
const ROW_STRIDE = 52;
const BUTTONS = {
  ArrowLeft: 1 << 0,
  ArrowRight: 1 << 1,
  ArrowUp: 1 << 2,
  ArrowDown: 1 << 3,
  KeyX: 1 << 4,
  KeyZ: 1 << 5,
  Space: 1 << 5,
};

const canvas = document.querySelector("#screen");
const context = canvas.getContext("2d", { alpha: false });
const image = context.createImageData(WIDTH, HEIGHT);
const startButton = document.querySelector("#start");
const status = document.querySelector("#status");
const crank = document.querySelector("#crank");
const restartJob = document.querySelector("#restart-job");
const steering = document.querySelector("#steering");
const servicePanel = document.querySelector("#service-panel");
const STORAGE_KEY = "forklift-certified/campaign_progress.bin/v1";

let wasm;
let running = false;
let raf;
let previousTimestamp = 0;
let heldButtons = 0;
let crankDelta = 0;
let previousCrankValue = Number(crank.value);
let audioContext;
const activeSequenceSources = new Set();
const activeEffectSources = new Set();
const musicSequence = {
  notes: [],
  tempo: 1,
  loopStart: 0,
  loopEnd: 0,
  loops: 0,
  nextStart: 0,
  running: false,
  timer: undefined,
  controls: new Map(),
};

function setStatus(message) {
  status.textContent = message;
}

function toggleServicePanel() {
  servicePanel.hidden = !servicePanel.hidden;
  setStatus(`Service panel ${servicePanel.hidden ? "closed" : "open"}.`);
}

function storageRead(pointer, capacity) {
  try {
    const encoded = localStorage.getItem(STORAGE_KEY);
    if (encoded === null) return -1;
    const binary = atob(encoded);
    if (binary.length > capacity) return -1;
    const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
    new Uint8Array(wasm.memory.buffer, pointer, bytes.length).set(bytes);
    return bytes.length;
  } catch (error) {
    console.warn("Unable to read campaign progress", error);
    return -1;
  }
}

function storageWrite(pointer, length) {
  try {
    const bytes = new Uint8Array(wasm.memory.buffer, pointer, length);
    let binary = "";
    for (const byte of bytes) binary += String.fromCharCode(byte);
    localStorage.setItem(STORAGE_KEY, btoa(binary));
    return 0;
  } catch (error) {
    console.warn("Unable to save campaign progress", error);
    setStatus("Progress could not be saved in this browser.");
    return -1;
  }
}

function storageClear() {
  try {
    localStorage.removeItem(STORAGE_KEY);
    return 0;
  } catch (error) {
    console.warn("Unable to clear campaign progress", error);
    setStatus("Progress could not be cleared in this browser.");
    return -1;
  }
}

async function prepareAudio() {
  try {
    if (!audioContext) audioContext = new AudioContext();
    if (audioContext.state !== "running") await audioContext.resume();
    return audioContext.state === "running";
  } catch (error) {
    console.warn("Web Audio is unavailable; continuing without sound", error);
    return false;
  }
}

function lfoConfig(type, rate, center, depth, holdoff, ramp, phase, retrigger) {
  return type < 0 ? null : { type, rate, center, depth, holdoff, ramp, phase, retrigger };
}

function lfoShape(type, phase) {
  const cycle = phase - Math.floor(phase);
  if (type === 0) return cycle < 0.5 ? 1 : -1;
  if (type === 1) return 1 - 4 * Math.abs(cycle - 0.5);
  if (type === 3) {
    const sample = Math.sin(Math.floor(phase) * 12.9898) * 43758.5453;
    return (sample - Math.floor(sample)) * 2 - 1;
  }
  if (type === 4) return cycle * 2 - 1;
  if (type === 5) return 1 - cycle * 2;
  return Math.sin(cycle * Math.PI * 2);
}

function controlValueAt(points, step) {
  if (!points || points.length === 0) return 0;
  let prior = points[0];
  for (let index = 1; index < points.length; index += 1) {
    const next = points[index];
    if (step < next.step) {
      if (!next.interpolate) return prior.value;
      const progress = (step - prior.step) / Math.max(1, next.step - prior.step);
      return prior.value + (next.value - prior.value) * progress;
    }
    prior = next;
  }
  return prior.value;
}

function stopSources(sources) {
  for (const source of sources) {
    try { source.stop(); } catch { /* Source already ended. */ }
  }
  sources.clear();
}

function scheduleAudioNote(waveform, note, velocity, duration, attack, decay, sustain, release, volume, options = {}) {
  if (!audioContext || audioContext.state !== "running") return;
  const now = Math.max(audioContext.currentTime, options.startAt ?? audioContext.currentTime);
  const releaseStart = now + Math.max(duration, attack + decay);
  const stopAt = releaseStart + Math.max(release, 0.01) + 0.03;
  const gain = audioContext.createGain();
  const modulationGain = audioContext.createGain();
  const peak = Math.min(0.45, Math.max(0, velocity * volume) * 0.35);
  gain.gain.setValueAtTime(0.0001, now);
  gain.gain.linearRampToValueAtTime(peak, now + Math.max(attack, 0.002));
  gain.gain.setTargetAtTime(peak * Math.max(0, sustain), now + Math.max(attack, 0.002), Math.max(decay, 0.005));
  gain.gain.setValueAtTime(Math.max(0.0001, peak * Math.max(0, sustain)), releaseStart);
  gain.gain.exponentialRampToValueAtTime(0.0001, stopAt);
  gain.connect(modulationGain);
  modulationGain.connect(audioContext.destination);
  modulationGain.gain.setValueAtTime(1, now);

  let source;
  if (waveform === 3) {
    const sampleCount = Math.ceil(audioContext.sampleRate * (stopAt - now));
    const buffer = audioContext.createBuffer(1, sampleCount, audioContext.sampleRate);
    const data = buffer.getChannelData(0);
    for (let index = 0; index < data.length; index += 1) data[index] = Math.random() * 2 - 1;
    source = audioContext.createBufferSource();
    source.buffer = buffer;
  } else {
    source = audioContext.createOscillator();
    source.type = ["square", "triangle", "sine", "sine", "sawtooth"][waveform] ?? "sine";
    const baseFrequency = 440 * (2 ** ((note - 69) / 12));
    const interval = 1 / 60;
    for (let elapsed = 0; elapsed <= stopAt - now; elapsed += interval) {
      const lfo = options.frequencyLfo;
      const delayed = lfo && elapsed >= lfo.holdoff;
      const ramp = delayed && lfo.ramp > 0 ? Math.min(1, (elapsed - lfo.holdoff) / lfo.ramp) : 1;
      const lfoPhase = !lfo ? 0 : (lfo.retrigger ? lfo.phase + elapsed * lfo.rate : lfo.phase + (now + elapsed) * lfo.rate);
      const lfoValue = delayed ? (lfo.center + lfo.depth * ramp * lfoShape(lfo.type, lfoPhase)) : 0;
      const step = (options.step ?? 0) + elapsed * (options.tempo ?? 1);
      source.frequency.setValueAtTime(baseFrequency * (2 ** (lfoValue + controlValueAt(options.controlPoints, step))), now + elapsed);
    }
  }
  if (options.amplitudeLfo) {
    const lfo = options.amplitudeLfo;
    const interval = 1 / 60;
    for (let elapsed = 0; elapsed <= stopAt - now; elapsed += interval) {
      const delayed = elapsed >= lfo.holdoff;
      const ramp = delayed && lfo.ramp > 0 ? Math.min(1, (elapsed - lfo.holdoff) / lfo.ramp) : 1;
      const lfoPhase = lfo.retrigger ? lfo.phase + elapsed * lfo.rate : lfo.phase + (now + elapsed) * lfo.rate;
      const value = delayed ? lfo.center + lfo.depth * ramp * lfoShape(lfo.type, lfoPhase) : 1;
      modulationGain.gain.setValueAtTime(Math.max(0, value), now + elapsed);
    }
  }
  source.connect(gain);
  const sourcePool = options.sourcePool;
  if (sourcePool) {
    sourcePool.add(source);
    source.addEventListener("ended", () => sourcePool.delete(source), { once: true });
  }
  source.start(now);
  source.stop(stopAt);
}

function playAudioNote(waveform, note, velocity, duration, attack, decay, sustain, release, volume,
  frequencyLfoType, frequencyLfoRate, frequencyLfoCenter, frequencyLfoDepth, frequencyLfoHoldoff, frequencyLfoRamp, frequencyLfoPhase, frequencyLfoRetrigger,
  amplitudeLfoType, amplitudeLfoRate, amplitudeLfoCenter, amplitudeLfoDepth, amplitudeLfoHoldoff, amplitudeLfoRamp, amplitudeLfoPhase, amplitudeLfoRetrigger) {
  scheduleAudioNote(waveform, note, velocity, duration, attack, decay, sustain, release, volume, {
    frequencyLfo: lfoConfig(frequencyLfoType, frequencyLfoRate, frequencyLfoCenter, frequencyLfoDepth, frequencyLfoHoldoff, frequencyLfoRamp, frequencyLfoPhase, frequencyLfoRetrigger),
    amplitudeLfo: lfoConfig(amplitudeLfoType, amplitudeLfoRate, amplitudeLfoCenter, amplitudeLfoDepth, amplitudeLfoHoldoff, amplitudeLfoRamp, amplitudeLfoPhase, amplitudeLfoRetrigger),
    sourcePool: activeEffectSources,
  });
}

function stopSynth() {
  stopSources(activeEffectSources);
}

function stopSequence() {
  musicSequence.running = false;
  if (musicSequence.timer !== undefined) window.clearTimeout(musicSequence.timer);
  musicSequence.timer = undefined;
  stopSources(activeSequenceSources);
}

function resetSequence() {
  stopSequence();
  musicSequence.notes = [];
  musicSequence.tempo = 1;
  musicSequence.loopStart = 0;
  musicSequence.loopEnd = 0;
  musicSequence.loops = 0;
  musicSequence.nextStart = 0;
  musicSequence.controls.clear();
}

function queueSequenceNote(waveform, note, velocity, step, length, attack, decay, sustain, release, volume,
  frequencyLfoType, frequencyLfoRate, frequencyLfoCenter, frequencyLfoDepth, frequencyLfoHoldoff, frequencyLfoRamp, frequencyLfoPhase, frequencyLfoRetrigger,
  amplitudeLfoType, amplitudeLfoRate, amplitudeLfoCenter, amplitudeLfoDepth, amplitudeLfoHoldoff, amplitudeLfoRamp, amplitudeLfoPhase, amplitudeLfoRetrigger, trackIndex) {
  musicSequence.notes.push({
    waveform, note, velocity, step, length, attack, decay, sustain, release, volume, trackIndex,
    frequencyLfo: lfoConfig(frequencyLfoType, frequencyLfoRate, frequencyLfoCenter, frequencyLfoDepth, frequencyLfoHoldoff, frequencyLfoRamp, frequencyLfoPhase, frequencyLfoRetrigger),
    amplitudeLfo: lfoConfig(amplitudeLfoType, amplitudeLfoRate, amplitudeLfoCenter, amplitudeLfoDepth, amplitudeLfoHoldoff, amplitudeLfoRamp, amplitudeLfoPhase, amplitudeLfoRetrigger),
  });
}

function queueSequenceControlPoint(trackIndex, step, value, interpolate) {
  const points = musicSequence.controls.get(trackIndex) ?? [];
  points.push({ step, value, interpolate: Boolean(interpolate) });
  points.sort((left, right) => left.step - right.step);
  musicSequence.controls.set(trackIndex, points);
}

function setSequenceTempo(stepsPerSecond) {
  if (Number.isFinite(stepsPerSecond) && stepsPerSecond > 0) musicSequence.tempo = stepsPerSecond;
}

function setSequenceLoops(loopStart, loopEnd, loops) {
  musicSequence.loopStart = Math.max(0, loopStart);
  musicSequence.loopEnd = Math.max(musicSequence.loopStart, loopEnd);
  musicSequence.loops = loops;
}

function scheduleSequenceCycle() {
  if (!musicSequence.running || !audioContext || audioContext.state !== "running") return;
  const startAt = Math.max(audioContext.currentTime + 0.05, musicSequence.nextStart);
  const loopSteps = musicSequence.loopEnd - musicSequence.loopStart + 1;
  const loopDuration = loopSteps / musicSequence.tempo;

  for (const event of musicSequence.notes) {
    if (event.step < musicSequence.loopStart || event.step > musicSequence.loopEnd) continue;
    scheduleAudioNote(
      event.waveform,
      event.note,
      event.velocity,
      event.length / musicSequence.tempo,
      event.attack,
      event.decay,
      event.sustain,
      event.release,
      event.volume,
      {
        startAt: startAt + (event.step - musicSequence.loopStart) / musicSequence.tempo,
        frequencyLfo: event.frequencyLfo,
        amplitudeLfo: event.amplitudeLfo,
        controlPoints: musicSequence.controls.get(event.trackIndex),
        step: event.step,
        tempo: musicSequence.tempo,
        sourcePool: activeSequenceSources,
      },
    );
  }

  musicSequence.nextStart = startAt + loopDuration;
  const delay = Math.max(0, (musicSequence.nextStart - audioContext.currentTime - 0.05) * 1000);
  musicSequence.timer = window.setTimeout(scheduleSequenceCycle, delay);
}

function startSequence() {
  stopSequence();
  if (!audioContext || audioContext.state !== "running" || musicSequence.notes.length === 0) return;
  musicSequence.running = true;
  musicSequence.nextStart = audioContext.currentTime + 0.05;
  scheduleSequenceCycle();
}

function present() {
  // WASM memory can grow, invalidating an existing typed-array view.
  const framebuffer = new Uint8Array(
    wasm.memory.buffer,
    wasm.webFramebufferPtr(),
    wasm.webFramebufferLen(),
  );
  const rgba = image.data;
  let output = 0;
  for (let y = 0; y < HEIGHT; y += 1) {
    const row = y * ROW_STRIDE;
    for (let x = 0; x < WIDTH; x += 1) {
      const byte = framebuffer[row + (x >> 3)];
      const isBlack = (byte & (0x80 >> (x & 7))) !== 0;
      const value = isBlack ? 23 : 231;
      rgba[output] = value;
      rgba[output + 1] = isBlack ? 33 : 232;
      rgba[output + 2] = isBlack ? 25 : 213;
      rgba[output + 3] = 255;
      output += 4;
    }
  }
  context.putImageData(image, 0, 0);
}

function frame(timestamp) {
  const elapsed = previousTimestamp === 0 ? 16.667 : timestamp - previousTimestamp;
  previousTimestamp = timestamp;
  wasm.webSetElapsedTime(elapsed);
  wasm.webSetInput(heldButtons, crankDelta);
  crankDelta = 0;
  if (wasm.webFrame() !== 1) {
    running = false;
    setStatus(`Game halted (runtime error ${wasm.webLastErrorCode()}).`);
    return;
  }
  present();
  raf = requestAnimationFrame(frame);
}

function shouldCaptureInput() {
  return running && (document.activeElement === canvas || document.activeElement === crank);
}

document.addEventListener("keydown", (event) => {
  if (running && event.code === "KeyM") {
    toggleServicePanel();
    event.preventDefault();
    return;
  }
  if (!shouldCaptureInput()) return;
  if (event.code === "KeyQ") crankDelta -= 4;
  if (event.code === "KeyE") crankDelta += 4;
  const button = BUTTONS[event.code];
  if (button !== undefined) heldButtons |= button;
  if (button !== undefined || event.code === "KeyQ" || event.code === "KeyE") event.preventDefault();
});

document.addEventListener("keyup", (event) => {
  const button = BUTTONS[event.code];
  if (button === undefined) return;
  heldButtons &= ~button;
  if (shouldCaptureInput()) event.preventDefault();
});

canvas.addEventListener("wheel", (event) => {
  if (!shouldCaptureInput()) return;
  crankDelta += event.deltaY * -0.05;
  event.preventDefault();
}, { passive: false });

crank.addEventListener("input", () => {
  const current = Number(crank.value);
  crankDelta += current - previousCrankValue;
  previousCrankValue = current;
});

window.addEventListener("blur", () => { heldButtons = 0; });
document.addEventListener("visibilitychange", () => {
  if (document.hidden) heldButtons = 0;
});

async function start() {
  startButton.disabled = true;
  setStatus("Loading WASM runtime…");
  try {
    const audioReady = await prepareAudio();
    const response = await fetch("forklift-certified.wasm");
    if (!response.ok) throw new Error(`WASM request failed (${response.status})`);
    const imports = {
      env: {
        webRuntimeError(code) {
          console.error("Forklift runtime error", code);
          setStatus(`Runtime error ${code}. See console.`);
        },
        webStorageRead: storageRead,
        webStorageWrite: storageWrite,
        webStorageClear: storageClear,
        webAudioPlayNote: playAudioNote,
        webAudioResetSequence: resetSequence,
        webAudioQueueSequenceNote: queueSequenceNote,
        webAudioQueueSequenceControlPoint: queueSequenceControlPoint,
        webAudioSetSequenceTempo: setSequenceTempo,
        webAudioSetSequenceLoops: setSequenceLoops,
        webAudioStartSequence: startSequence,
        webAudioStopSequence: stopSequence,
        webAudioStopSynth: stopSynth,
      },
    };
    const bytes = await response.arrayBuffer();
    const result = await WebAssembly.instantiate(bytes, imports);
    wasm = result.instance.exports;
    if (wasm.webInit() !== 1) throw new Error(`Initialization failed (${wasm.webLastErrorCode()})`);
    running = true;
    previousTimestamp = 0;
    canvas.focus();
    restartJob.disabled = false;
    steering.disabled = false;
    setStatus(audioReady ? "Running — music and effects ready" : "Running — audio unavailable");
    raf = requestAnimationFrame(frame);
  } catch (error) {
    console.error(error);
    setStatus(`Unable to start: ${error.message}`);
    startButton.disabled = false;
  }
}

startButton.addEventListener("click", start);
restartJob.addEventListener("click", () => {
  if (!running) return;
  wasm.webActivateMenu(0);
  canvas.focus();
});
steering.addEventListener("change", () => {
  if (!running) return;
  wasm.webSetMenuValue(1, Number(steering.value));
  canvas.focus();
});
window.addEventListener("beforeunload", () => {
  cancelAnimationFrame(raf);
  stopSequence();
});
