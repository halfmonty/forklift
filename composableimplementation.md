# Composable Warehouse Runtime: Implementation Plan

## Reader, outcome, and constraints

This plan is for the engineer implementing the migration described in
`composable.md`. After completing it, they should be able to add a warehouse
mechanic by giving a descriptor static content, a narrowly owned simulation
system, and semantic render submissions—without extending the game shell's
active-play switchboard.

The work has two outcomes:

1. Existing ordered-delivery shifts behave identically through a bounded
   `WarehouseRuntime`.
2. A conveyor warehouse proves that an independently simulated floor cargo
   item can return to the established pickup, delivery, collision, and render
   paths.

Preserve the native and web targets throughout. The Playdate stack is small,
so all runtime queues and scene storage are fixed-capacity, frame-owned or
game-owned data. Do not add a general allocator, dynamic level loading,
runtime plugin registry, or ECS framework.

## Target ownership model

The current `Game` owns both campaign presentation and the complete active
shift. Split those responsibilities as follows:

| Owner | Responsibilities | Must not own |
| --- | --- | --- |
| `Game` shell | Playdate API, menus, title/briefing/result/promotion flow, save/load, audio playback, persistent camera, and calling the renderer | Forklift, live cargo, job state, timer, collision counter, or active-shift rule sequencing |
| `WarehouseRuntime` | The mutable `World`, phase order, active objective/job state, event and command buffers, reset/start-job, and semantic effect requests | Playdate API calls, save writes, raw drawing, campaign routing |
| Warehouse descriptor | Static geometry adapter, bounds/spawn, shift data, runtime setup, systems, and static render contributors | Mutable per-shift state |
| Systems | A documented, phase-specific transformation of world state | Direct platform calls or bypassing another system's writes |
| Render scene | Semantic entries assembled from settled state and rendered in pass order | Simulation state mutations |

The shell may inspect a small `StepResult` after each step: objective/job
transition, shift completion, and semantic sound requests. It converts those
facts into briefings, result screens, and audio calls.

## Implementation shape

Create a `runtime` module group with these concrete types. Keep existing
vehicle, cargo, collision, camera, projection, static-level, compositor, and
campaign types as the compatibility primitives during the migration.

```zig
pub const CargoId = enum(u8) { primary = 0 };

pub const CargoStore = struct {
    items: [1]?cargo.Pallet = .{null};
    // get, getPtr, activeId iterator, spawn, clear; reject a second insertion.
};

pub const World = struct {
    forklift: vehicle.Forklift,
    cargo: CargoStore,
    objective: ObjectiveRuntime,
    shift_elapsed_seconds: f32,
    collision_impacts: u32,
    impact_origin: ?math2.Vec2,
    dynamic_actors: DynamicActorStore,
    transient: TransientState,
};
```

`DynamicActorStore` is an explicit empty placeholder in the first migration;
do not prematurely model robots or trains. `ObjectiveRuntime` initially wraps
the existing job index and delivery state, plus the current destination. Its
public behavior is an objective anchor, job label, completion predicate, and
start/reset operation. Only the delivery-to-zone case is implemented.

Use these initial capacities and store them in named constants near their
types: one live cargo item, zero dynamic actors, 16 events, 16 commands, and
128 semantic scene entries. Queue/scene overflow must panic in debug-safe
builds and expose an incrementing dropped/overflow count in non-debug builds;
never silently corrupt memory. Revisit a capacity only with a mechanic and a
test that needs it.

Define an API-neutral `Frame` by translating the existing input snapshot once:

```zig
pub const Frame = struct {
    dt: f32,
    held: Buttons,
    pushed: Buttons,
    crank_delta_deg: f32,
    camera_mode: bool,
    steering_ratio: vehicle.SteeringRatio,
};
```

The runtime derives `MotionIntent` and `VehicleModifiers`; the shell does not
pre-apply gameplay rules. Camera rotation remains in the shell, because it is
presentation state, but the frame's `camera_mode` prevents drive/fork intent
exactly as it does today.

Use tagged unions, not string keys, for events and deferred commands. Start
with only the variants exercised by migrated behavior and conveyors:

```zig
pub const Event = union(enum) {
    pallet_engaged: void,
    fork_height_moved: void,
    cargo_dropped: CargoId,
    cargo_transported: CargoId,
    objective_completed: void,
    collision_impact: void,
};
pub const Command = union(enum) {
    transport_cargo: struct { id: CargoId, displacement: math2.Vec2 },
};
```

Commands are collected by systems and applied at the end of phase five. A
transport command is rejected if its cargo is carried, no longer exists,
another transport command already won for that cargo this frame, or its
proposed oriented footprint intersects a static solid. Rejection leaves cargo
at its current position. Events describe the accepted result; authoritative
state remains in `World`.

## Ordered runtime phases

Make phase order an enum and run it from one `step` function. Each system
declaration names its phase and reads/writes, so ownership can be reviewed
without tracing the implementation.

| Phase | System responsibility | Exclusive writes |
| --- | --- | --- |
| 1. Frame/intents | Reset transient buffers; derive player and camera-gated intent | transient intent/modifiers |
| 2. Modifiers | Apply load and future mechanic modifiers | transient modifiers |
| 3. Vehicle/forks | Integrate vehicle; attempt a legal fork-height change | forklift except collision response |
| 4. Solid collision | Revert vehicle, carried cargo, and speed on collision; count rearmed impact | collision response fields |
| 5. Carry/transport | Follow carried cargo; run conveyor transport; apply accepted cargo transport commands | cargo position only for transport |
| 6. Interactions | Pickup/drop and trigger contacts | cargo carry state and pickup offsets |
| 7. Objectives/accounting | Advance delivery state, timer, score inputs, and completion events | objective and shift accounting |
| 8. Scene submission | Build a scene from settled state | scene buffers only |

The compatibility delivery system must retain the current ordering nuances:
the carried pallet follows before collision rollback, rollback restores the
previous pallet state, interaction follows collision, and carried cargo
follows again after a successful pickup/drop interaction. Encode these as
tests before refactoring them.

## Slice-by-slice execution

Every slice is a separate commit. Before merging a slice, run `zig build test`
and `zig build web-test`; also run `zig build run` and perform the listed smoke
checks whenever controls, camera, or visuals change. Record exact results in
the commit or handoff note.

### Slice 0 — baseline and executable regression script

1. Run the existing host and web checks without changes and record their
   output.
2. Add only low-level tests that capture already-observable behavior: a job's
   initial pallet state, reset restoring spawn and waiting state, delivery
   transition, collision rollback state, and fork-height restrictions.
3. Write a concise manual script covering every production cargo type,
   cardinal and diagonal camera views, complete-shift scoring, restart, and
   saved-progress continuation.

Exit criteria: no production behavior change; the script is practical in the
simulator and on hardware.

#### Manual regression procedure

1. Run the native simulator and begin a new campaign. Advance through the
   initial briefing and verify the shift starts with the forklift and pallet
   at their authored positions.
2. Drive forward and reverse, then hold the camera button while using all four
   directions and the crank. Confirm drive input is suppressed in camera mode
   and the view changes without moving the forklift.
3. At clear floor space, raise and lower the forks through every height. Repeat
   near a rack with forks or carried cargo intersecting a shelf; the forbidden
   height crossing must be rejected.
4. Pick up, carry, and drop the standard and heavy cargo in the production
   campaign. In the existing stress-test configuration, repeat for the long
   cargo and a rack-supported pallet.
5. Drive a carried pallet into a solid at more than one approach angle. Confirm
   forklift position, heading, speed, and cargo return to their last valid
   state, and that a sustained contact counts as one impact until rearmed.
6. Deliver every job in a shift, including the briefing before the heavy job;
   verify job labels, score/result values, promotion, and return flow.
7. During an active job, use the system-menu restart action. Confirm the
   forklift, camera, pallet, job state, timer, and collision state reset.
8. Complete or advance campaign progress, return to the title screen, choose
   Continue, and confirm the saved location is resumed. Repeat on hardware
   before accepting any later slice that changes controls or rendering.

### Slice 1 — introduce world state and a parity adapter

1. Add the runtime module, `CargoId`, capacity-one `CargoStore`, `World`, and
   delivery-only `ObjectiveRuntime`.
2. Add a factory that receives the existing shift definition and descriptor
   spawn data, constructs a world, and loads its first job. Make reset and
   start-next-job use that factory path.
3. Add read-only parity accessors while `Game` still renders and steps through
   the old path. The adapter may expose the primary pallet and destination,
   but it must not create a second mutable pallet.
4. Move the mutable forklift, pallet, job state/index, elapsed time, impact
   bookkeeping, and result inputs into the runtime by the end of this slice.
   `Game` accesses them through the runtime only.

Tests: world construction and reset equal the prior shift's spawn/support,
cargo definition, objective state, timer, and collision state; inserting a
second cargo returns the documented capacity error.

Exit criteria: debugger-visible gameplay state has one authoritative home,
but the old update/draw call flow remains usable.

### Slice 2 — extract `WarehouseRuntime.step`

1. Introduce `Frame`, `StepResult`, and `step`. Initially implement it as a
   parity sequence rather than a reusable system list.
2. Move active-play update logic into `step` in its existing order. It owns
   restart/current-job setup and returns completion or sound facts instead of
   invoking audio or campaign code.
3. Reduce the playing branch in `Game` to input translation, camera update,
   runtime step, response handling, camera follow, and draw invocation.
4. Keep title, briefings, results, promotion, campaign routing, and progress
   persistence unchanged in the shell. A runtime completion must drive the
   same before-job briefing and end-of-shift scoring transitions as before.

Tests: scripted frames cover drive/collision rollback, successful pickup,
drop/delivery, next-job transition, and final-job completion. Assert emitted
sound facts rather than mocking the platform audio API.

Exit criteria: a normal shift has identical gameplay results and shell flow
through the runtime.

### Slice 3 — install named systems, phases, and queues

1. Replace the parity body with the eight named phases above, retaining the
   same implementation functions where possible.
2. Add fixed `EventBuffer` and `CommandBuffer`, explicit overflow behavior,
   and a per-frame accepted-transport marker for every cargo slot.
3. Route existing pallet-engagement, fork-height, collision-impact, and
   objective-completion facts through events/`StepResult` only where they
   already cross the runtime/shell boundary.
4. Enforce write ownership with contexts limited to the system's need. In
   particular, only collision can restore vehicle state, only interactions can
   alter carried/floor state, and only objectives can mark completion.

Tests: phase-order probe systems append a known trace; a delivery invoked via
the compatibility entry and via the system list has the same final world;
queue-full behavior is deterministic; duplicate transport commands resolve
according to the documented first-command-wins rule.

Exit criteria: the public phase order and conflict policy are executable
contracts, not comments.

### Slice 4 — replace stage switches with descriptors

1. Define a uniform `WarehouseDescriptor` that contains stage identity,
   bounds, forklift spawn, static-level adapter, shift definitions, runtime
   setup callback, phase systems, and render/HUD contributors.
2. Convert every existing warehouse content module into a descriptor. Reuse
   the compile-time static-level tuple internally; descriptors expose stable
   function-pointer-style adapters so campaign code is no longer a family of
   stage-ID switches.
3. Change the stage registry to look up descriptors by the existing stage ID.
   Preserve campaign ordering, stage IDs, shift IDs, and invalid-save fallback
   behavior exactly.
4. Delete a switch only after all its cases are represented by descriptors;
   do not leave two dispatch routes that can disagree.

Tests: iterate the active campaign and instantiate each descriptor; verify
lookup for every valid ID and the invalid-ID fallback; exercise continue,
restart, next shift, promotion, and campaign completion using descriptors.

Exit criteria: registering a warehouse is one registry entry plus its
descriptor, without editing shared query/draw switch families.

### Slice 5 — introduce semantic scene submission

1. Add a fixed-capacity `RenderScene` with pass-tagged entries: static ground,
   opaque surfaces, actors/cargo, foreground, world overlay, and HUD.
2. Adapt current static level drawing, destination, decorative pallets,
   dynamic forklift/cargo composition, debug HUD, and FPS HUD into entries.
   Entries describe an operation and data; contributors do not call graphics.
3. Render the scene using the current renderer and compositor. Preserve the
   special forklift/pallet surface fragmentation as a dedicated actor entry
   before general actor sorting is introduced.
4. Compare frame baselines deliberately at cardinal and diagonal yaw, then
   remove the direct warehouse drawing path.

Tests: pass ordering, scene-capacity overflow, static-surface collection, and
the existing compositor tests. Review web framebuffer changes manually; only
commit approved baseline changes with their visual reason.

Exit criteria: settled runtime state is the sole source for scene submission,
with equivalent culling and foreground occlusion.

### Slice 6 — remove migration scaffolding

1. Delete old active-shift fields and update code from `Game`.
2. Delete compatibility accessors and stage dispatch routes once no production
   caller uses them.
3. Retain only static-level authoring adapters that reduce content boilerplate.
4. Run a full regression pass using the Slice 0 script and verify no active
   state is mirrored between shell and runtime.

Exit criteria: `Game` is a shell; runtime is the single active-shift owner;
all campaign stages use descriptors and all gameplay rendering uses scenes.

## Slice 7 — conveyor vertical slice

Do this only after Slice 6 is accepted. Keep it a single mechanic and a
single authored proof warehouse.

### Static data and content

Add `Conveyor { bounds, direction, speed }` to descriptor-owned static data.
Validate at compile time or startup that direction is normalized within a
small epsilon, speed is positive, and the selected maximum frame displacement
cannot pass a thin solid. If that bound cannot be guaranteed, split movement
into bounded substeps before collision testing.

Author a compact conveyor stage with a wall/rack boundary that prevents
forklift bypass, a drop apron at each end, a far-side retrieval area, one
standard cargo spawn, a normal delivery zone, and a briefing that says floor
cargo moves while carried cargo and the forklift do not. Add IDs through the
same descriptor/campaign route, not a special campaign rule.

### Simulation

Run `conveyorSystem` in phase five after carried cargo follows forks and
before interaction contacts. Iterate active cargo IDs. An eligible item is
floor cargo whose center lies in a conveyor rectangle; its full oriented
footprint remains the collision shape. For each item:

1. Calculate `direction * speed * frame.dt`.
2. Submit one `transport_cargo` command.
3. At the phase boundary, test the proposed footprint against descriptor
   solids.
4. Accept the position only when clear, otherwise leave it in place.
5. Emit `cargo_transported` only after accepted non-zero movement.

The first version has no belt handoff policy: choose the first declared belt
whose region contains the center, assert that conveyor regions do not overlap
in authored content, and document that restriction beside the data type.

### Rendering

Add a conveyor render contributor that submits a ground-pass entry. The
renderer draws a rectangular border plus repeated direction chevrons. Start
with static graybox marks; an optional deterministic phase derives from shift
elapsed time and resets with the runtime. The belt must not create collision
geometry by itself—the surrounding content owns the puzzle walls.

### Tests and playtest

Host tests must prove fixed-dt distance, no movement outside a belt, no
movement while carried, collision rejection without overlap, deterministic
replay, normal pickup after transport, and successful normal delivery after
transport. Test the static overlap constraint and scene pass/capacity too.

In simulator and hardware, verify readability at native resolution, no visual
jitter or teleport, no forklift transport, reliable drop/re-pickup at both
ends, useful camera/occlusion, predictable restart, and the web scripted
sequence. Do not add animation or tune speed until the graybox route succeeds
on hardware.

## Completion evidence and handoff

For every slice, leave a short handoff containing the completed slice, next
slice, commit identifier, commands and results, simulator/hardware/web checks
performed, selected capacities, new ordering/conflict invariants, approved
visual baseline changes, and known parity deviations. Do not call a slice
complete without current `zig build test` and `zig build web-test` output.

Reassess the bounded-world design only after evidence: many dynamic types need
arbitrary component combinations, cross-type queries recur, or `World` fields
become demonstrably artificial. Until then, add a focused store and system for
the mechanic in hand.
