# Playdate API for Browser/WASM: Implementation Priorities

## Purpose

This roadmap is for contributors extending the Zig Playdate API facade into a
generically useful browser/WASM target. The goal is not merely to run Forklift
Certified: a conventional Zig Playdate game should compile with the same API
shape and run in a browser without being rewritten around web-specific calls.

After reading this document, a contributor should be able to select the next
API family to implement, understand why it is ordered there, and define the
browser semantics and tests required before adding it.

## Compatibility contract

This target is a compatibility layer, not a literal Playdate hardware emulator.
It must preserve the API signatures, lifetime rules, callback ordering, and
observable game behavior where a browser has an equivalent. Hardware-only or
service-backed features must fail predictably or expose a documented browser
approximation; they must never silently claim unavailable capabilities.

Every API member has one of three states:

- **Supported:** its documented behavior is implemented and tested in WASM.
- **Declared but unsupported:** it exists so a game can identify the capability,
  but reports a stable failure or unavailable value when called.
- **Absent:** it is not yet part of the browser facade and a caller will not
  compile until the API is deliberately added.

The current target supports the bootstrap lifecycle, elapsed time, button edges,
crank delta, basic menus, a 400-by-240 one-bit framebuffer, primitive drawing,
basic text, one save-file path, and a narrow Web Audio synth/sequence bridge.
That is sufficient for Forklift Certified, but not yet for a typical asset- and
sprite-driven Playdate game.

## Priority order

### P0 — Complete facade inventory and capability reporting

Add the complete root API shape and all shared types from the Zig Playdate
definitions before expanding behavior. Every top-level subsystem—system, file,
graphics, sprite, display, sound, Lua, JSON, scoreboards, and network—needs a
browser facade entry with a documented support state.

Implement a small capability/version query for browser-only diagnostics; do not
change the native Playdate API to make games depend on it. Unsupported function
pointers should be intentional stubs with consistent return values, not null
pointers or accidental link failures.

Why first: it prevents each game from discovering missing structs and ABI types
piecemeal, while making the remaining roadmap measurable.

Done when: an automated inventory compares the browser declarations with the
native Zig definitions and every omitted member is explicitly recorded as
unsupported or intentionally excluded.

### P1 — Bitmap, font, and drawing-state foundation

Support the graphics APIs most general Playdate games need to render assets:

- Bitmap creation, loading, copying, freeing, masks, raw bitmap data, bitmap
  tables, and tilemaps.
- Drawing bitmaps with flip, tile, scale, rotation, draw mode, patterns,
  stencil, clipping, draw offsets, and off-screen graphics contexts.
- Text measurement, tracking, leading, font pages/glyph metrics, and bundled
  font assets rather than a fallback-only font.
- Remaining primitive operations such as polygon, pixel, rotated/scaled bitmap,
  and framebuffer-to-bitmap helpers.

Keep rendering in Zig against the Playdate-format one-bit framebuffer. Browser
JavaScript should only present that framebuffer and load approved assets.

Why second: image and tile rendering are more common than custom vector drawing
in Playdate games, and they are prerequisites for sprite support.

Done when: a representative bitmap-and-tilemap game renders without Canvas
calls from game code, asset/mask ownership is correct, and framebuffer visual
baselines catch one-bit rendering regressions.

### P2 — Sprite system and collision world

Implement the sprite API on top of the P1 bitmap primitives:

- Sprite allocation, ownership, image/tilemap assignment, bounds, z-order,
  visibility, clipping, draw/update callbacks, userdata, and dirty regions.
- Frame update/draw ordering, always-redraw behavior, and draw-mode/stencil
  inheritance.
- Collision rectangles, response callbacks, move/check collision semantics,
  overlap and line/rectangle queries, and result-array ownership.

Why third: sprites and their collision world are a primary Playdate gameplay
model. Implementing them before bitmap lifetime and draw state would duplicate
the renderer and create incompatible behavior.

Done when: ordering, callback timing, collision responses, and query results
match a small native reference fixture; a game can use sprites without knowing
whether it runs on device or in a browser.

### P3 — File system, memory, and resource loading

Replace the single-save store with a browser-backed Playdate-like file layer:

- Named files and directories, read/write/append semantics, cursor behavior,
  `stat`, rename, unlink, list-files, and error reporting.
- Atomic persistence with IndexedDB as the durable backing store, with an
  intentional localStorage fallback only for small saves.
- Asset reads from the deployed game package separated from writable save data.
- Full reallocation semantics, including resize and free, rather than
  allocation-only startup support.

Why fourth: generic games need multiple saves, settings, JSON, and assets. A
correct file layer also enables graphics and audio loaders to use normal API
calls rather than special browser paths.

Done when: missing, corrupt, interrupted-write, rename, directory, and
multi-file cases are tested in a real browser; committed saves survive reload
without exposing partially written data.

### P4 — Broad sound foundation

Extend the current Web Audio bridge from its PDNA subset to common Playdate
sound use:

- Independent channels and sources, volume/pan, callbacks, play state, and
  proper object lifetime.
- Samples, sample players, and file players with loading, looping, playback
  rate, offsets, ranges, fades, and finish callbacks.
- Per-object synth state, note-off, transpose, pitch bend, instruments,
  sequences, tracks, and finite-loop completion behavior.
- Envelopes, LFOs, control signals, effects, and modulation with documented
  Web Audio approximations.

Why fifth: audio is important, but a game can often run silently while the
graphics, sprites, and assets required to see it are still absent. Autoplay
requires audio startup to remain user-gesture gated.

Done when: sample-based and synth-based reference fixtures play correctly after
a gesture, stop cleanly, preserve loop/callback semantics, and remain stable
through background/foreground transitions.

### P5 — System, display, and input parity

Add browser equivalents for the commonly useful system APIs:

- Current time, epoch time, language, logging/error formatting, button
  callbacks, menu mutation, and pause/resume/terminate lifecycle events.
- Crank angle and docked state, gamepad input, visibility/focus handling, and
  documented keyboard/touch mappings.
- Permission-gated accelerometer support and stable unavailable behavior where
  device sensors cannot be used.
- Display scale, inversion/flipping, refresh diagnostics, and safe browser
  approximations for power/lock settings.

Why sixth: the current input loop is enough for many games, but this makes the
target feel like a coherent platform instead of a keyboard-only demo.

Done when: focus loss cannot leave input stuck, denied sensor permission is
non-fatal, lifecycle callbacks have deterministic ordering, and every hardware
approximation is documented in the browser controls UI.

### P6 — JSON and common utility services

Implement the JSON encoder/decoder, including callback-driven decode traversal,
reader/writer streams, errors, and ownership. Pair it with the P3 file layer so
games can load ordinary JSON content through the same paths on device and web.

Why seventh: JSON is broadly useful for data-driven games but is not required
to establish rendering, sprites, or the save foundation.

Done when: round-trip, malformed input, streaming reader, callback order, and
native fixture compatibility are covered.

### P7 — Video playback

Implement video and video-stream APIs only after P3 provides robust packaged
asset access. Prefer browser video decoding behind a Playdate-shaped frame
interface; define supported codecs and seek/streaming limitations up front.

Why eighth: video is specialized and browser codecs vary, but it has a viable
browser counterpart once resource loading exists.

Done when: loading, frame timing, looping, seeking, and end-of-stream behavior
are tested for the documented codec subset.

### P8 — Network and scoreboards

Treat network and scoreboards as opt-in host integrations, not automatic
substitutes for Playdate services:

- HTTP can map to `fetch` with explicit CORS, cancellation, response-size, and
  offline semantics.
- TCP needs a documented browser transport substitute, such as WebSocket, or a
  reliable unsupported result.
- Scoreboards require an application-owned backend and credentials model; a
  browser facade must not impersonate Playdate’s service.

Why ninth: browser networking exists, but API and security behavior cannot be
made compatible without a deployment-specific service decision.

Done when: each enabled service has an explicit endpoint/auth policy and tests
for offline, denied, malformed, and cancelled requests.

### P9 — Lua integration

Do not promise the Playdate Lua runtime inside a generic Zig/WASM facade. If a
game uses the Lua API, choose and document a compatible Lua VM, ABI boundary,
asset packaging model, and callback/GC ownership rules first.

Why last: this is a second language runtime with significant size, security,
and lifecycle implications. It is not a small API-stub task.

Done when: a deliberately supported Lua game fixture loads its scripts, calls
registered Zig functions, manages objects safely, and reports script errors in
the browser.

## Explicitly deferred until requested

These APIs should remain declared-but-unsupported or absent until a concrete
game needs them: microphone capture, custom sound signal generators, custom
audio effect processors, wavetable synthesis, MIDI-file import, device serial
features, camera-like peripherals, and vendor-specific online services.

## Rules for every implementation

1. Add or update the facade declaration and its support-state entry first.
2. Preserve native signatures and ownership rules at the game boundary.
3. Define browser-specific behavior before implementation, especially for
   permissions, async browser APIs, and unavailable hardware.
4. Add deterministic host tests and a built-WASM integration test; use a
   browser test for lifecycle, persistence, input, audio, or permission paths.
5. Update this roadmap when an API family changes support state.
