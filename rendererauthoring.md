# Web Render Authoring Tool: Implementation Plan

## Reader, outcome, and constraints

This plan is for the engineer building Forklift Certified's browser-based
renderer authoring tool. After completing it, they should be able to create a
reusable 2.5D object or a screen-space graphic, preview it as a one-bit
Playdate render, export it deterministically, and use the generated native
Zig without hand-translating SDK calls.

The tool serves authoring; it is not part of the shipped game. The Playdate
SDK and hardware remain the rendering authority. The browser is the fast
iteration surface and must use the same projection, drawing semantics, font,
and named pattern catalog as the native renderer wherever the tool claims
fidelity.

Preserve these constraints throughout:

- The target framebuffer is exactly 400 by 240 and one bit per pixel.
- Native rendering and generated assets use no runtime document parsing,
  dynamic allocation, or unbounded temporary storage.
- The Playdate stack is small. Generated modules use fixed, conservative
  command and vertex limits and issue drawing calls in a streaming fashion.
- The editor uses the repository's lightweight browser stack: ES modules,
  DOM controls, and Canvas for display. It adds no UI framework.
- The game, not an asset document, decides mechanic state and scene ordering.

## Product boundaries

The editor has two document kinds with a shared primitive, style, validation,
and export foundation.

| Document kind | Purpose | Coordinate system | Typical output |
| --- | --- | --- | --- |
| `world_render` | Reusable 2.5D objects rendered in a warehouse | Local world `x`, `y`, and `z`, projected at runtime | pressure plate, gate, conveyor marker, prop |
| `screen_graphic` | Fixed Playdate-screen graphics | 400 by 240 screen pixels | HUD panel, status icon, logo, badge |

Do not build a general warehouse-layout editor, an Aseprite replacement, a
runtime JSON renderer, arbitrary custom pattern painting, freehand pixel art,
imported bitmap editing, document nesting, or a general 3D depth sorter in
the first release. Those can be added once concrete content shows their value.

The first release supports a deliberately small, verified Playdate-safe
drawing subset:

- black, white, clear, and named predefined patterns;
- lines with supported widths;
- filled and outlined polygons/quads;
- world-space lines and polygons whose vertices carry `z`;
- convenience authoring shapes for ground rectangles, raised panels, and
  rectangular prisms, expanded to general primitives before export;
- clipping where the common drawing façade supports it; and
- text through one explicitly selected shared bitmap font.

Unsupported SDK capabilities are not representable in a document. Image,
sprite, stencil, arbitrary bitmap-pattern, and additional-font support each
need their own parity work before being exposed.

## Authoring document contract

Editable source documents live as tracked, versioned `.render.json` files.
They are authoritative; generated Zig is a reproducible build artifact.
Every document begins with an integer `schema_version` and its `kind`.

The browser migrates supported older schemas forward when opening a document.
The generator rejects a document newer than it understands. Re-exporting
always writes the newest schema. This makes schema evolution explicit rather
than relying on inferred JSON shapes.

Each document declares:

- a stable asset name and a semantic render pass;
- a local command list in explicit painter's order;
- a typed placement contract;
- named style references from the shared catalog;
- named variants; and
- a bounded typed parameter list.

`world_render` geometry is always local to a caller-supplied placement
contract, not baked into one warehouse's coordinates. A common contract may
be `bounds: Rect` and `base_z: f32`; an object needing only a point can use
`position: Vec2`. The preview supplies an editable sample placement. At
runtime the generated function derives all world positions from that input and
uses the live camera state, so the graphic remains correct while the camera
rotates.

`screen_graphic` commands are authored in screen pixels. They do not receive
or depend on the world camera.

Parameters are limited to `bool`, integer, `f32`, named enum, `Vec2`, `Rect`,
and text. They may select variants, control visibility, and drive declared
coordinates, dimensions, height, and text. They cannot inject Zig expressions
or add arbitrary commands. This keeps the export statically understandable.

Variants represent authored states; game code selects them. For example, an
active pressure plate document exports one function accepting `active: bool`.
It does not know why the plate is active.

## Shared render model

Introduce a narrow shared authoring-draw façade between generated modules and
the Playdate API. It maps one-for-one to the approved SDK operations while
owning rounding, point conversion, clipping policy, named pattern lookup, and
explicit font selection. Generated modules call this façade rather than
calling arbitrary `playdate.graphics` members directly.

The existing projection module remains the sole 2.5D projection calculation.
World commands use the current camera and its existing tuning at draw time.
The editor never reimplements that projection in JavaScript.

Create one hand-authored pattern catalog as the source of truth. A catalog
entry has a stable name, its eight bytes, and preview metadata. The browser
receives a manifest derived from that catalog. Documents refer only to names.
Adding a curated pattern requires a catalog change and native/web parity
coverage; individual documents never embed pattern bytes.

Before editor text is enabled, establish one explicit bitmap font shared by
native and web rendering. The game currently relies on a native default font
while the browser façade uses its own small font; that difference must be
removed. Documents store text, position, and alignment. The shared façade
selects the known font before rendering it.

The general serialized primitive vocabulary is intentionally small:

```text
world_line, world_polygon, screen_line, screen_polygon, text
```

World vertices contain `x`, `y`, and `z`. Higher-level editor tools expand
ground rectangles, raised panels, and prisms into this vocabulary. The
generator therefore has one rendering path per primitive instead of acquiring
mechanic-specific export code.

## Browser editor architecture

Add a separate `web-editor` build target and page. It shares the projection,
framebuffer, font, pattern catalog, and drawing façade with the game web
build, but does not load the campaign, game loop, or gameplay UI.

The browser JavaScript owns document loading, editing state, DOM controls,
pointer/keyboard interaction, undo/redo, and local drafts. It validates and
normalizes an edited document into a bounded binary command buffer. The
editor-specific Zig/WASM module accepts that buffer, interprets it with the
shared façade into the same one-bit framebuffer model, and exposes the
framebuffer to Canvas for display.

This boundary has two important properties:

1. Editing is immediate and ergonomic without recompiling Zig/WASM after
   every drag.
2. JavaScript does not duplicate projection or Playdate-style raster rules.

Use a primary 400 by 240 one-bit canvas preview. The browser may scale that
canvas with nearest-neighbor display for comfortable inspection, but it must
not anti-alias the source pixels. Editor handles, grids, selections, and other
authoring overlays render separately and never enter an exported framebuffer.

The editor keeps a localStorage draft and a full undo/redo history for each
operation. Imported/exported `.render.json` files remain the only repository
authority. The interface visibly marks a draft that differs from the last
imported or exported document.

## Editing and preview workflow

The editor needs both direct manipulation and exact numeric editing:

- select commands and variants in a layer/command list;
- drag to move, resize rectangle bounds, and manipulate polygon vertices;
- edit exact coordinates, `z`, line width, style, pass, variant, and parameter
  bindings in an inspector;
- snap world work to a configurable world grid and screen work to whole
  pixels; and
- create, remove, reorder, duplicate, and undo commands.

For world documents, provide an interactive camera plus a fixed rotation
strip of representative game angles. The strip is part of normal asset review
and golden fixtures. It reveals thin lines, silhouettes, and accidental
overdraw that a single favorable angle hides. The preview reports selected
commands projecting outside the framebuffer but permits deliberate clipping.

World previews use a small built-in reference scene: floor grid, pallet-scale
box, forklift footprint, destination zone, optional occluder wall, and the
editable placement sample. Do not load full warehouse definitions in this
release. Final scene integration remains a game smoke test.

Each document declares one semantic render pass, initially aligned with the
scene's existing before-warehouse, after-warehouse, dynamic, and HUD-style
passes. The document controls local painter's order only. The game places the
result into its scene pass and retains responsibility for cross-object
occlusion and ordering.

## Export and game integration

Provide a deterministic local generation command. It reads every tracked
`.render.json` document, validates schema and budgets, and writes one
generated Zig module per document. Generated modules are checked in so their
diffs are reviewable, but ordinary builds verify freshness rather than silently
rewriting them. A dedicated update command performs regeneration.

Generated files are never hand-edited. They contain a header identifying their
source document and generator version. Hand-written wrappers own semantic
names, game-specific control flow, composition, and selection of parameters;
they call the generated module's stable `draw(...)` API.

Document composition is intentionally manual in v1: a wrapper calls multiple
generated assets in the required order. This avoids document dependency
graphs, cyclic-reference validation, parameter forwarding, and coordinate
space ambiguity. Add acyclic component references only after repeated real
use demonstrates the need.

The generator enforces conservative documented budgets: maximum commands per
document, polygon vertices per command, variants, parameters, and command
buffer bytes. It emits static data and streaming calls only. Any budget
increase requires a motivating asset and a device-safe memory review.

Slice 0 sets the initial document limits at 64 commands, 8 variants, 8
parameters, and a 1,024-byte normalized editor command buffer. Later slices
add a distinct polygon-vertex limit when the binary command protocol exists.

## Verification and review

Every supported primitive and style has three layers of evidence:

1. Schema, migration, command-buffer, and generator tests validate accepted
   input, rejection of malformed/budget-exceeding input, and deterministic
   Zig output.
2. Deterministic one-bit framebuffer golden tests render fixtures through the
   editor WASM façade. Fixtures cover primitives, styles, clipping, font,
   parameter variants, and representative camera angles.
3. A simulator or hardware smoke check is required when a new primitive
   family is introduced or shared façade behavior changes. It is not required
   for every ordinary content-document edit.

Store golden framebuffers as compact one-bit artifacts, not large screenshots.
Tests compare bytes and report differences; they never rewrite a golden.
Provide an explicit `update-render-goldens` build step for intentional visual
updates.

Use these first acceptance assets:

1. A pressure plate with active and inactive variants, a local bounds
   contract, and rotation-strip checks.
2. A compact HUD/status panel proving screen coordinates, the explicit shared
   font, and text parameters.
3. A monochrome Forklift Certified badge or logo proving layered 2D geometry
   and named pattern selection.

## Implementation slices

Every slice ends with host tests, the existing web integration check, and any
new editor check relevant to the changed boundary. Format changed Zig and
browser source before accepting the slice.

### Slice 0 — contracts and baseline

1. Record the current native and web rendering baselines.
2. Define document-kind, schema-version, parameter, style-name, render-pass,
   and bounded-command vocabulary contracts.
3. Specify initial limits and failure messages.
4. Add tests for document validation and command-buffer capacity boundaries.

Exit criteria: the persisted format, unsupported-feature policy, and memory
limits are executable contracts rather than editor assumptions.

### Slice 1 — shared native/web authoring foundation

1. Create the shared authoring-draw façade over approved SDK operations.
2. Route the web framebuffer implementation through equivalent façade
   semantics.
3. Add the curated named 8 by 8 pattern catalog and browser manifest.
4. Establish one explicit shared bitmap font for native and web use.
5. Add primitive/style/font parity fixtures.

Exit criteria: a small hand-written fixture renders the expected one-bit
framebuffer in web and displays correctly in the simulator.

### Slice 2 — editor renderer WASM boundary

1. Add the separate editor build/page and its browser bootstrap.
2. Define the bounded normalized command-buffer binary format.
3. Export the editor-WASM functions for loading commands, choosing preview
   camera/placement/parameters, rendering, and reading the framebuffer.
4. Implement world and screen primitive interpretation through the shared
   façade and shared projection module.
5. Add deterministic framebuffer goldens, including the rotation strip.

Exit criteria: a static fixture command buffer renders identically through the
editor framebuffer on repeatable host/web checks.

### Slice 3 — document I/O and deterministic generator

1. Implement schema-versioned JSON import/export and forward migrations.
2. Implement a local generator that validates documents and writes generated
   Zig modules with provenance headers.
3. Add build freshness verification and explicit generation/update commands.
4. Add generated-only ownership guidance and wrapper examples.
5. Test stable output, stale-output detection, invalid document rejection, and
   schema migration.

Exit criteria: a checked-in document produces a repeatable generated module
that a hand-written game wrapper can call on native and web targets.

### Slice 4 — usable screen-graphic editor

1. Build the document list, import/export, draft state indicator, local draft,
   undo/redo, command list, and inspector.
2. Add screen canvas selection, whole-pixel snapping, direct move/resize, and
   polygon-vertex editing.
3. Support named styles, command ordering, text, variants, and typed
   parameters in the preview.
4. Author and export the HUD/status fixture and the badge/logo fixture.

Exit criteria: an engineer can create and revise both acceptance screen assets
without manually writing drawing calls.

### Slice 5 — usable world-render editor

1. Add local placement contracts, world grid snapping, `z` editing, and
   general world line/polygon editing.
2. Add convenience tools for ground rectangles, raised panels, and prisms.
3. Add interactive camera controls, reference-scene controls, and the fixed
   rotation strip.
4. Add render-pass selection and local painter-order inspection.
5. Author/export the pressure plate fixture and integrate it through a
   hand-written mechanic wrapper.

Exit criteria: the pressure plate is designed in local world coordinates,
looks correct at the selected camera angles, and renders in a warehouse using
the live game camera.

### Slice 6 — workflow hardening

1. Improve validation diagnostics so bad commands identify their document,
   variant, and command index.
2. Add editor-side budget displays and out-of-frame indicators.
3. Add the explicit golden-update workflow and documentation for adding a
   primitive, pattern, font, or acceptance asset.
4. Run simulator and hardware smoke checks for the pressure plate, HUD, and
   badge/logo.
5. Record any native/web raster differences and either eliminate them or mark
   the capability unsupported.

Exit criteria: a new contributor can add an approved primitive or authored
asset, regenerate safely, review the visual change, and test it on the target
without relying on undocumented browser behavior.

## Future extensions

Only pursue these after the initial assets show a concrete need: additional
curated patterns, circles/ellipses after SDK/web parity coverage, imported
one-bit bitmaps, a pixel-art mode, additional fonts, document components,
full-warehouse preview contexts, and broader Playdate graphics APIs. Each
extension must first define its native fidelity contract, schema impact,
memory budget, generator output, and visual tests.
