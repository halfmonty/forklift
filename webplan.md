# WebAssembly and browser port implementation plan

## Purpose

This plan adds a browser build of Forklift Certified without turning the game
into a JavaScript application or replacing its existing Playdate rendering
calls. The Playdate `.pdx` build remains supported and behaviorally unchanged.

The intended reader is an engineer implementing the port. After reading this
document they should be able to add the web target in safe, testable slices,
know which compatibility functions are required, and know what constitutes
browser parity.

## Approach and boundaries

Use a Zig `web_playdate` compatibility runtime that supplies the small subset
of `PlaydateAPI` that the game actually calls. Compile the same game code for
`wasm32-freestanding`; initialize it with a synthetic `PlaydateAPI`; and let
the browser host deal only with canvas presentation, event collection, audio
output, persistent-storage bridging, and frame scheduling.

Keep every drawing operation in Zig. The runtime owns a Playdate-shaped,
one-bit 400-by-240 framebuffer with a 52-byte row stride (12,480 bytes). The
host copies that buffer once per animation frame, expands it to RGBA, and puts
it on a canvas. Do not route individual lines, triangles, or text calls through
JavaScript.

The first port deliberately excludes unused Playdate subsystems: sprites,
bitmaps, clipping/stencils, Lua, JSON, networking, and raw framebuffer APIs.
They can be added later to the shared compatibility runtime only when a game
uses them.

## Current compatibility inventory

The direct Playdate importers are the application entry point, panic handler,
renderer, input reader, progress store, game state, and the three audio
modules. The simulation, content definitions, camera, projection, compositor,
collision, jobs, campaign, scoring, and PDNA preset data do not need a
platform port.

| Surface | Calls currently required | Web implementation |
| --- | --- | --- |
| System lifecycle and memory | `realloc`, update callback, elapsed timer, error | WASM heap allocation; stored callback; host-provided monotonic time; console error/trap in debug |
| Input | buttons and crank change | State supplied through exported setters before each frame |
| Menus | add menu item, add options item, get/set value | Zig-owned opaque menu records, with browser controls added after core play works |
| Graphics | clear, line, rect, filled rect/triangle/ellipse, text, font | Zig software rasterizer into the one-bit framebuffer |
| Display | refresh rate | Accepted no-op; browser `requestAnimationFrame` controls cadence |
| Save file | stat/open/read/write/flush/unlink | One synchronous, byte-preserving virtual file backed by localStorage |
| Audio | native synth, instrument, LFO, envelope, sequence, track, control signal APIs | Initially valid no-op handles; later a Web Audio implementation or an explicit audio adapter |

Audio is intentionally not permitted to make the visual/gameplay web MVP fail
at initialization. The runtime must return non-null, safely disposable objects
for every handle required by the existing PDNA effect and song startup path.

## Target architecture

```text
shared game and simulation Zig
             |
      platform API import
        /              \
Playdate API         web_playdate API
    |                    |
Playdate OS      software framebuffer + runtime state
                         |
                   exported WASM ABI
                         |
       JavaScript: inputs, requestAnimationFrame, canvas,
                  storage bridge, Web Audio
```

The WASM ABI should be deliberately small and stable:

- `webInit()` constructs the fake API and calls the existing event handler with
  `EventInit` exactly once.
- `webSetInput(current_buttons, crank_delta_degrees)` receives input gathered
  by the host. The runtime derives pushed and released button masks from the
  previous state.
- `webSetElapsedTime(milliseconds)` supplies the elapsed time for the next game
  update. Clamp in the existing input path as it does today.
- `webFrame()` invokes the callback installed through `setUpdateCallback`.
- `webFramebufferPtr()` and `webFramebufferLen()` expose the stable framebuffer
  address and its 12,480-byte length. Re-read the memory buffer after WASM
  memory growth before using a typed-array view.
- Optional diagnostics exports expose the last runtime error and the requested
  display refresh rate; neither is required for game play.

Do not export game internals, raw pointers to temporary allocations, or a
JavaScript-callable rendering API.

## Proposed layout

Add a platform-selection module that is the only import target for game code.
The Playdate selection re-exports the existing API definitions unchanged; the
web selection supplies compatible types and the fake API. Replace the nine
current direct imports with that platform module, rather than using build
conditionals throughout gameplay code.

Suggested new areas:

```text
src/platform_api.zig              selected API facade
src/web_main.zig                  WASM exports and EventInit bootstrap
src/web/runtime.zig               API tables, lifecycle, timers, input, menus
src/web/framebuffer.zig           1-bit pixel access and primitive rasterizers
src/web/font.zig                  bundled browser font and UTF-8 text drawing
src/web/storage.zig               one-file synchronous save implementation
src/web/audio.zig                 handle-safe audio compatibility layer
web/index.html                    canvas and minimal control UI
web/main.js                       WASM loader, event handling, presentation
web/style.css                     responsive Playdate frame and controls
```

Keep browser tooling dependency-free unless a later deployment requirement
demands bundling. A static file server is sufficient for local development;
the production output should be a directory containing HTML, JavaScript, WASM,
and any required font/audio assets.

## Implementation sequence

### 1. Establish the target and import seam

1. Add a `web` build step to `build.zig` that compiles a `wasm32-freestanding`
   executable from the web entry point. Set an explicit initial memory size and
   export memory so the browser can read the framebuffer. Do not make this step
   depend on `PLAYDATE_SDK_PATH`; the existing Playdate build may continue to
   require it.
2. Add a separate `web-dev` or documented static-server command that serves the
   generated output with the MIME type required for `.wasm`.
3. Add `src/platform_api.zig` with build-selected imports. Preserve the
   existing complete Playdate definition file as the native source of truth.
4. Change every direct API importer to use the facade. This is a mechanical
   change; confirm the native Playdate build and host unit tests still compile
   before implementing any emulation.
5. Provide only the types needed to compile the web target: root API and
   subsystem tables, buttons, system event, callback types, menu/font/file
   handles, color/text types, and every audio opaque type/enumeration reached
   by the PDNA adapters. Match the existing function-pointer signatures and
   C ABI, not merely similarly named Zig functions.

Acceptance: `zig build test` succeeds, the native build remains selectable,
and `zig build web` emits a loadable WASM module without requiring Playdate SDK
environment variables.

### 2. Bootstrap the existing lifecycle

1. Implement static API tables and a static `PlaydateAPI`; all function pointer
   fields reached by startup must be non-null.
2. Implement `realloc` using an allocator appropriate for the freestanding
   target. Define ownership expectations: game allocations persist for the page
   lifetime; the MVP does not need browser-page teardown.
3. Have `webInit()` call the existing `eventHandler(&web_api, .EventInit, 0)`.
   It must be idempotent or explicitly reject duplicate calls, because a hot
   reload must not create duplicate game state and callbacks.
4. Implement `setUpdateCallback` as stored callback plus userdata; make
   `webFrame()` invoke it and ignore its return only after recording an error if
   it signals failure.
5. Implement elapsed-time state. The host sends a delta calculated from
   `performance.now()`; `getElapsedTime` returns it and `resetElapsedTime`
   clears it, matching the input reader's current use.
6. Implement `error` without variadic JavaScript calls: retain a fixed
   diagnostic message where feasible, log it through a minimal imported host
   function, and trap only in Debug mode.

Acceptance: the browser can load WASM, call `webInit`, call `webFrame`, and
reach the game update callback without null function calls or allocator errors.

### 3. Implement the framebuffer and primitive graphics

1. Allocate a zero-initialized `[LCD_ROWS * LCD_ROWSIZE]u8` buffer. Define and
   test bit order, white/black encoding, clipping to the visible 400-by-240
   bounds, and padding-byte behavior. Presentation must read only the first 50
   bytes of each row; preserve all 52 bytes to retain Playdate layout.
2. Implement a central `setPixel`/`getPixel` helper and use it for all
   primitives. Color support for this game is strictly solid black and white;
   reject or document unsupported pattern pointers rather than silently
   dereferencing them.
3. Implement `clear`, filled rectangles, outlined rectangles, width-one and
   width-greater-than-one lines, filled triangles, and filled ellipses with
   Playdate-compatible inclusive/exclusive edge conventions established by
   golden tests.
4. Use integer rasterization and clamp before indexing. The renderer submits
   projected floating-point values, so document its conversion rule (normally
   truncation to the C integer ABI) and test negative/off-screen coordinates.
5. Add `getFrame`, `getDisplayFrame`, `markUpdatedRows`, and `display` as
   compatible optional helpers once primitives work, even though current game
   code does not call them. `markUpdatedRows`/`display` may be no-ops for MVP.

Acceptance: deterministic unit tests compare framebuffer bytes for each
primitive, including clipping and row-stride padding. A browser frame visibly
draws the warehouse geometry rather than an empty canvas.

### 4. Add text before declaring visual parity

1. The game loads the system Roobert font and calls `drawText` on title,
   briefing, promotion, result, and debug screens. Provide a web-only font
   implementation that makes `loadFont` return a valid opaque handle for that
   known request and makes `setFont` retain it.
2. Prefer bundling a legally usable bitmap font with known glyph metrics. Draw
   glyphs into the same one-bit framebuffer in Zig; do not use Canvas text,
   which would produce different layout and bypass the framebuffer.
3. Support exactly the UTF-8/ASCII character set used by current strings,
   then fail visibly and safely for missing glyphs. Establish baseline, advance,
   newline, and return-value semantics for `drawText` from observed game
   layout. Expand Unicode only when content requires it.
4. Add screenshot/golden-frame tests for each UI state, or a deterministic test
   scene exercising all currently used characters.

Acceptance: all current title, briefing, shift result, promotion, campaign
completion, and debug text is legible, inside its intended layout, and drawn
through the framebuffer.

### 5. Implement host presentation and controls

1. Build `web/index.html` around a canvas whose backing resolution is exactly
   400 by 240. Scale it with CSS using nearest-neighbor image rendering and
   preserve its aspect ratio; do not change the game coordinate system.
2. In `web/main.js`, instantiate WASM, call `webInit`, and run one loop:
   collect state, calculate elapsed time, call the input/time exports, call
   `webFrame`, expand the 1-bit buffer to a reusable `ImageData`, then schedule
   the next `requestAnimationFrame`.
3. Map arrows to the D-pad, Z/Space to A, and X to B. Prevent default browser
   behavior only while the game canvas has focus. Clear held buttons on
   `blur`/`visibilitychange` to prevent stuck movement.
4. Provide crank input in this priority order: Q/E keyboard increments for
   reliable desktop use; mouse-wheel delta while focused; then an optional
   accessible pointer/touch crank control. Accumulate deltas until consumed by
   `webSetInput` and use a documented degrees-per-input-unit sensitivity.
5. Add a brief in-page control legend and a focusable start button. Browser
   audio must be resumed from this user gesture, even if the first MVP emits no
   sound.

Acceptance: a keyboard-only player can start a new campaign, drive, steer,
raise/lower forks, pick up/drop a pallet, rotate the camera while holding B,
and advance every text screen without scroll or stuck-input regressions.

### 6. Save progress and menu controls

1. Implement only `campaign_progress.bin` in a synchronous virtual file layer.
   Represent open file state in Zig; serialize byte writes through a narrow
   imported host function or an exported buffer protocol.
2. Store the exact existing encoded bytes under a namespaced localStorage key,
   base64-encoded only at the JavaScript storage boundary. Existing validation
   in `progress_store` remains authoritative; malformed, missing, or
   wrong-length values behave as no save.
3. Define storage failure behavior: private mode/quota/security errors make
   save return false without corrupting in-memory progress; the game stays
   playable. Add a visible diagnostic in development builds.
4. Implement Zig-owned opaque `PDMenuItem` records for Restart Job and
   Steering. Initially support values through exported commands; then present
   them as ordinary browser buttons/select controls and invoke the original
   registered callback with its stored userdata.

Acceptance: reload resumes a valid campaign, Reset/New Game clears the browser
save, invalid stored bytes do not crash, Restart Job works, and steering menu
selection affects vehicle behavior.

### 7. Stage audio deliberately

1. First ship a silent-but-safe compatibility layer: all allocations return
   distinct valid opaque handles, setters retain enough state for debugging,
   add/remove-source and sequence operations succeed, and free operations are
   idempotent or safely guarded. This enables the current PDNA initialization,
   effect calls, music start, and cleanup unchanged.
2. Add tests that execute `Audio.init`, `startMusic`, representative effects,
   and `deinit` on the web API. This prevents a later adapter change from
   reintroducing startup failure.
3. Select one audio follow-up after the game is playable:
   - Implement the used PDNA synth/sequence subset with Web Audio nodes via a
     narrow event bridge. This preserves source data and provides the closest
     browser result, but requires timing, envelope, LFO, and automation work.
   - Add a platform-neutral audio-event adapter and write a Web Audio renderer
     for those events. This is easier to maintain but is a small architectural
     change and must preserve native PDNA behavior.
   - Pre-render approved music/effects into bundled samples. This is simplest
     at runtime but loses live synthesis semantics and needs an asset pipeline.
4. Do not claim audio parity until effects, looping music, envelope behavior,
   and browser autoplay/resume behavior have been tested manually.

Acceptance for MVP: no audio API call crashes or prevents gameplay. Acceptance
for the audio follow-up: music and representative effects are audible only
after a user gesture and remain in sync through a full shift.

### 8. Harden, document, and automate delivery

1. Add host unit tests for framebuffer primitives, input edge transitions,
   elapsed-time reset, save-file round trips, menu callbacks, and no-op audio
   object lifecycle. Keep existing simulation tests platform-neutral.
2. Add browser integration tests, preferably with a headless browser, that load
   the built site, verify a nonblank framebuffer, send controls, save/reload,
   and verify canvas dimensions and focus behavior.
3. Add deterministic visual regression captures for a title screen, a gameplay
   frame, and one text-heavy state. Allow a documented tolerance only at the
   RGBA conversion boundary, not in the 1-bit framebuffer.
4. Add `zig build web`, development-server, and production-output instructions
   to the README. State browser support, controls, storage behavior, audio
   status, and the fact that the Playdate build is still the reference target.
5. Configure CI to run host tests plus web compilation on every change. Run
   browser tests where the CI environment provides a browser; keep the native
   Playdate package build in its existing SDK-capable workflow.

Acceptance: a clean checkout can produce the browser directory, serve it,
and play the game with documented controls; CI catches a broken web compile and
the native build path remains unaffected.

## Verification checklist

- Compile the Playdate/simulator target before and after the facade migration.
- Run all current host tests and new compatibility unit tests.
- Load the browser build from a real HTTP server, not `file://`.
- Test keyboard, focus loss, tab return, touch/pointer crank if provided, and
  a controller only if gamepad support is added.
- Complete at least one job and one full shift; exercise title, briefing,
  results, promotion, campaign-completion, restart, and steering controls.
- Reload after progress is saved; test a missing, corrupt, and obsolete save.
- Test at 100%, fractional browser zoom, and narrow/mobile viewport sizes.
- Check browser console for traps, out-of-bounds memory access, and storage or
  audio-resume errors.

## Risks and decisions to settle before implementation

1. **Font source and licensing:** choose a bitmap font that may be bundled, or
   obtain permission to package the exact required font. This is the largest
   visual-parity dependency because Canvas/system fonts are not deterministic.
2. **MVP audio policy:** decide whether the first browser release is explicitly
   silent, or whether synthesized audio is a launch requirement. The plan keeps
   this decision from delaying the renderer and controls.
3. **Browser support:** define the minimum supported desktop and mobile browsers
   before adding optional gamepad, touch-crank, or Web Audio features.
4. **Build deployment target:** choose the static-host destination separately
   from the port. The output layout should work on any static host and avoid
   locking gameplay code to a deployment platform.
5. **Compatibility scope:** treat the inventory above as a contract. Add a
   Playdate API function only after a code search proves it is needed, with a
   unit test for its browser semantics.

## Definition of done

The browser build is complete when a player can build and serve a static web
artifact, initialize the unchanged game lifecycle, see equivalent 400-by-240
monochrome gameplay and UI, use documented controls through a complete shift,
and retain validated campaign progress across reloads. The native Playdate
artifact and host tests must continue to work. Audio may be marked as a clearly
documented follow-up only if the browser runtime already provides safe,
non-crashing compatibility for the full currently used PDNA call sequence.
