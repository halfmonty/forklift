# Composable Warehouse Runtime: Migration and First Mechanic Plan

## Purpose and reader

This is the implementation plan for the warehouse-mechanics phase of Forklift
Certified. It is written for an engineer or agent arriving with no prior
conversation context. After reading it, they should be able to migrate the
current single-pallet delivery loop to the composable runtime in safe slices,
then implement and validate the first new warehouse mechanic.

The first mechanic is **conveyors**. A conveyor makes cargo move through a
route the player cannot complete by carrying it normally. It is the best first
proof because it exercises the three architectural promises at once: a
stateful world object, a reusable simulation rule, and a new world-rendering
submission. It is intentionally not combined with portals, doors, power,
robots, or multiple loose pallets.

## Decision

Use a fixed-capacity, data-oriented `World` with explicit, phased composable
mechanics. A warehouse is a compile-time blueprint that selects its static
geometry, runtime setup, simulation systems, render contributors, and HUD
contributors.

This is not a full ECS and is deliberately compatible with adopting
component-style storage later if evidence requires it. Static geometry remains
compile-time authored. Dynamic things have stable bounded identities in the
world. The game shell owns campaign flow, Playdate input, menus, save data,
and final presentation; the runtime owns active-shift simulation.

Do not introduce a general allocator, a dynamic plugin system, runtime-loaded
levels, inheritance hierarchy, or a general ECS registry in this migration.
The Playdate's constrained stack and the game’s static authored content make
fixed capacities and compile-time composition the appropriate default.

## Current state and migration goal

Today, active play is coordinated by `Game`: vehicle motion, fork changes,
collision rollback, pickup/drop, the single pallet, the current job, camera
following, and scene drawing are all in one update path. A stage dispatcher
also contains repeated stage-specific branches for world queries and drawing.
The existing `StaticLevel` object tuple is useful for immutable racks, shelves,
obstacles, and decoration, but it has no runtime state or update lifecycle.

The target shape is:

```text
Game shell
  campaign/menu/save/platform input
             |
             v
Warehouse runtime
  World + ordered systems + events/commands + objective state
             |
             v
Render scene
  ground | opaque surfaces | actors | foreground | overlay | HUD
```

The first migration must reproduce current behavior exactly: one forklift,
one active cargo item, ordered delivery jobs, current collision behavior,
fork-height rules, camera behavior, scoring, briefings, and presentation. A
structural change is not permission to change handling or rules.

## Architectural contracts

### World and identity

`World` is the sole mutable state of an active shift. Begin with explicit
fields rather than generic stores:

```zig
const World = struct {
    forklift: vehicle.Forklift,
    cargo: CargoStore,
    objectives: ObjectiveRuntime,
    dynamic_actors: DynamicActorStore,
    transient: TransientState,
};
```

`CargoStore` may initially have capacity one, but it must address cargo by a
stable `CargoId` rather than by “the pallet field.” Raise capacity only when a
mechanic needs it. `DynamicActorStore` may initially be empty; it reserves the
correct ownership point for robots, trains, gates, batteries, and other moving
or stateful objects. All stores are fixed-capacity arrays with explicit
capacity errors/assertions during development. No per-frame allocation.

Keep the present `vehicle`, `cargo`, collision, camera, and projection math as
small, mostly pure modules. The runtime orchestrates them; mechanics do not
duplicate their math.

### Input and motion intent

Translate platform input once into a runtime `Frame` containing `dt`, player
buttons, crank delta, and camera-mode state. Before vehicle integration,
mechanics can alter a `MotionIntent` and `VehicleModifiers`:

```zig
const MotionIntent = struct { crank_delta_deg: f32, forward: bool, reverse: bool };
const VehicleModifiers = struct {
    steering_sign: f32 = 1,
    forward_allowed: bool = true,
    reverse_allowed: bool = true,
    acceleration_multiplier: f32 = 1,
    traction_multiplier: f32 = 1,
};
```

This is the extension point for ice, broken steering, no reverse, battery
limits, and fragile-load handling. Base vehicle integration must not gain a
new flag for every warehouse gimmick.

### Fixed simulation phases

Every runtime runs these phases in this order. Add a phase only when a real
mechanic proves it necessary.

1. Reset/read frame and derive input intent.
2. Apply control and load modifiers.
3. Integrate forklift motion and fork-height intent.
4. Resolve solid collision and rollback/response.
5. Follow carried cargo and apply transport effects to eligible floor cargo.
6. Detect contacts and process interactions (pickup, drop, triggers, scans).
7. Update objectives, score/timers, and emit one-way events.
8. Submit the render scene and HUD from the settled world state.

The runtime, not individual mechanics, owns phase order. A mechanic may
request a command for a later phase, but should not move an actor while another
system is iterating contacts. This prevents portals, conveyors, gates, and
future moving platforms from fighting over state.

### Events and commands

Use a small typed union for facts that occurred and a separate typed union for
deferred changes. Examples include `cargo_dropped`, `cargo_entered_zone`,
`objective_completed`, `gate_changed`, `teleport_requested`, and
`cargo_transport_requested`. Events are notifications, not a replacement for
reading authoritative world state. Commands are applied at a documented phase
boundary and must state conflict behavior.

Examples of rules to document in code and tests:

- A solid collision wins over a transport request that would end inside it.
- A carried cargo item is not conveyor-transportable.
- A cargo item may receive at most one transport command per frame unless a
  future mechanic explicitly defines composition.
- Objective completion is evaluated after interactions and transport are
  settled.

### Objectives

Replace the assumption that every job is a pallet inside a rectangle with an
active objective that exposes an anchor and completion predicate. The initial
delivery objective adapts the current rectangle containment rule unchanged.

```zig
const Objective = union(enum) {
    deliver_cargo_to_zone: DeliverCargoToZone,
    reach_location: ReachLocation,
    restore_power: RestorePower,
    inspect_cargo: InspectCargo,
};
```

Only implement `deliver_cargo_to_zone` during migration. The other cases name
the intended direction and must not be built early. The objective anchor later
feeds the off-screen objective indicator without HUD code knowing about a job
rectangle.

### Warehouse blueprint and systems

Each stage supplies a uniform descriptor: stage metadata, world bounds,
forklift spawn, static level provider, shift/job data, runtime setup, systems,
and render/HUD contributors. It can use a compile-time tuple internally; the
campaign sees a uniform stage/runtime factory.

A system has a narrow phase-specific context, not direct access to `Game` or
the Playdate API. A render contributor submits semantic scene entries rather
than issuing raw graphics calls. This lets the compositor retain its existing
special forklift-and-cargo ordering while the scene grows to include belts,
robots, gates, trains, portal effects, darkness, and HUD.

### Render scene

Create a fixed-capacity semantic `RenderScene`. Its passes are:

1. ground/static background;
2. opaque surfaces used by the existing height-aware compositor;
3. actors and cargo;
4. foreground objects;
5. world overlays such as darkness or portal effects;
6. HUD, including the objective arrow.

Preserve the existing compositor behavior for the forklift and active cargo
first. Do not attempt to solve arbitrary depth sorting for every future actor
in this migration. Add semantic actor submissions and extend sorting only when
the first mechanic needs it.

## Migration plan

Each slice should compile independently, preserve the native and web targets,
and be committed separately. Run host tests and the web integration check at
the end of every slice. Run a hardware/simulator smoke test whenever input,
camera, or rendered behavior changes.

Use these commands from the repository root:

```sh
zig build test
zig build web-test
zig build run
```

The first command executes platform-neutral tests. The second builds the web
artifact and runs its integration checks. The third requires a configured
Playdate SDK and launches the native simulator; use it for manual checks. A
hardware build is required for control feel and native-screen readability
before accepting a mechanic that changes either.

### Slice 0: Baseline and safety net

Record the current test results and make a short manual regression script:

- start a shift, drive forward/reverse, and rotate camera;
- raise/lower forks near a rack;
- pick up, carry, and drop standard, heavy, and long cargo;
- deliver each existing job and finish a shift;
- restart mid-job and verify the initial state returns;
- load/continue campaign progress.

Add host tests only for behavior that is currently untested and easy to
express without graphics: initial job spawn, reset behavior, delivery
transition, collision rollback input/output, and current fork constraints.
Do not change production behavior in this slice.

Acceptance: the current test suite, browser integration check, and manual
script pass before architectural work begins.

### Slice 1: Introduce runtime data without changing behavior

Add runtime-owned `World`, a one-element `CargoStore`, and an adapter for the
current active job/pallet state. Add stable IDs even though only ID zero exists.
Move reset/start-job construction into the runtime while `Game` still calls the
old-style methods.

The runtime must be able to initialize from the existing shift definition and
produce the same forklift spawn, pallet properties, support height, job state,
timer, collision count, and score inputs.

Acceptance: unit tests show that initialization and reset reproduce the
existing shift state; manual behavior is unchanged.

### Slice 2: Extract the active-shift step

Create `WarehouseRuntime.step(frame)` and move the current active-play
sequence into it in the exact existing order. `Game` becomes the shell that:

- reads platform input and maintains title/briefing/result/promotion flow;
- asks the runtime to step only while a shift is playing;
- handles campaign transitions and persistence;
- forwards presentation-relevant results such as sound requests.

Do not introduce reusable mechanics yet. The first implementation may be a
single standard-delivery system set whose purpose is parity. Keep audio at the
edge: simulation emits a semantic request such as `pallet_engaged` or
`fork_height_moved`; `Game` plays the effect.

Acceptance: all baseline manual cases match previous behavior, and host tests
cover the runtime’s vehicle/cargo/job transition sequence.

### Slice 3: Establish mechanics, phases, and commands

Split the parity step into named systems matching the fixed phase list:
input/control, vehicle/forks, collision, cargo carry/pickup/drop, objective,
and shift accounting. Add `EventBuffer` and `CommandBuffer` with capacities,
overflow behavior, and tests. Initially, only use them where they replace an
already-existing direct transition; do not invent events for everything.

Document each system’s read/write ownership in its declaration. In particular,
only the collision system may restore/reject forklift motion, only the cargo
interaction system changes carry state, and only the objective system marks a
job complete.

Acceptance: phase ordering is a testable runtime contract; an ordinary delivery
uses the same result whether invoked through the compatibility adapter or the
system list.

### Slice 4: Replace stage dispatch with descriptors

Replace repeated stage-specific query/draw branches with a registry of stage
descriptors. Each descriptor provides a runtime factory and the static-level
adapter. Existing warehouse modules remain declarative content modules.

Keep stage/shift IDs and save-format behavior stable. Unknown or invalid saved
IDs must retain the existing safe behavior. Do not make level content
runtime-loaded.

Acceptance: all current stages instantiate through the registry, starting,
restarting, continuing, and completing each campaign route still work.

### Slice 5: Add render-scene submission

Introduce `RenderScene` and move warehouse drawing, opaque-surface collection,
dynamic forklift/cargo composition, and HUD submission behind it. First render
the exact old scene through scene entries; then delete the old direct draw path.

Maintain the current culling and opaque-surface capacity protections. Make any
new scene capacity explicit and visible in debug builds rather than silently
drawing partial scenes.

Acceptance: current views preserve foreground/occlusion ordering at cardinal
and diagonal camera angles; host compositor tests remain green; web frame
baseline changes are reviewed rather than accepted blindly.

### Slice 6: Remove compatibility scaffolding

Once all production stages use the runtime and scene, remove duplicate
one-pallet state and old dispatcher entry points. Keep small adapters only
where they genuinely simplify static level authoring.

Acceptance: no active simulation state is duplicated between `Game` and
`World`; adding an empty new warehouse requires registering one descriptor,
not editing a family of stage switches.

## First mechanic: conveyors

### Player-facing rule

A conveyor belt moves a pallet along its configured direction while the pallet
is resting on the floor inside its belt region. The player must place a pallet
onto the belt to reach a delivery bay inaccessible by normal forklift travel.
The forklift and carried cargo are unaffected. The belt is always powered in
this first version.

The first warehouse should teach one thing: put the pallet on the belt, clear
the area, retrieve it at the far end, and deliver it. The destination must not
be placed so that the player can bypass the belt by driving around the
obstacle. Use simple graybox visuals first.

### Explicit scope

Implement:

- rectangular belt regions with a direction and speed;
- transport of a floor cargo item while it remains within a belt;
- solid collision response using existing cargo/obstacle geometry;
- a visible belt surface and direction/readability marks;
- an authored conveyor test warehouse and briefing;
- deterministic host tests and manual hardware validation.

Defer:

- belt-to-belt handoff rules;
- switches, reversing belts, power failures, damage, or sorting;
- conveyor motion for forklifts, robots, trains, or carried cargo;
- multiple live cargo items beyond what is needed to prove store iteration;
- animated art, sound, or darkness interactions.

### Data and system shape

Define a static `Conveyor` with a world rectangle, normalized direction, and
speed. Its simulation system runs in phase five, after forklift solid collision
and after carried cargo follows the forks. For each eligible floor cargo item
overlapping a belt:

1. calculate proposed displacement as direction times speed times `dt`;
2. enqueue or apply one cargo transport command;
3. test the proposed cargo footprint against the static solids;
4. move the cargo if valid, otherwise stop it at its present position for this
   first mechanic;
5. emit `cargo_transported` only when movement occurred.

The first implementation should use a clearly documented overlap choice. The
recommended rule is that the cargo center must be inside the belt region,
while final placement and collision continue to use the full oriented cargo
footprint. This is easy to teach and avoids unstable partial-contact behavior.

If the cargo leaves the belt, transport stops. If a belt would move it into a
wall, rack, or blocked destination, it stops rather than clipping, tunneling,
or being pushed sideways. Use substeps only if the selected belt speed can
cross a thin collider in one frame; otherwise choose a safe speed and assert
the constraint in tests.

The conveyor render contributor submits a ground/actor-adjacent semantic item;
it must not draw directly from simulation. Start with a rectangular outline,
repeated chevrons, and an optional alternating phase value. Its static shape
does not itself block movement. Surrounding walls create the route puzzle.

### Conveyor proof warehouse

Author one compact warehouse with:

- a cargo spawn on the accessible side;
- a belt crossing an impassable wall or rack boundary;
- a pickup/drop apron at both ends;
- a far-side retrieval apron and destination;
- enough turning room to make the lift gameplay legible;
- a briefing page explaining that only floor cargo moves on the belt.

The design must prove that cargo can be moved by a system other than fork
carry, then re-enter normal pickup, collision, objective, and rendering paths.
It should not require a new campaign rule; it is an ordinary ordered delivery
shift authored through the new descriptor.

### Conveyor tests and validation

Host tests must cover:

- cargo centered on a belt moves the expected distance for a fixed `dt`;
- carried cargo never moves from conveyor processing;
- cargo outside the belt does not move;
- cargo stops before an obstacle and never overlaps it;
- the result is deterministic for a fixed frame sequence;
- a transported, dropped, and re-picked pallet can complete a normal delivery
  objective;
- conveyor scene submission selects the expected pass and respects capacity.

Manual simulator and hardware checks must cover:

- a player can understand belt direction at native screen resolution;
- the pallet visibly moves without jitter or teleporting;
- the player cannot ride the belt accidentally;
- dropping at each belt end feels reliable;
- the camera and shelf occlusion do not hide the important interaction;
- restart restores cargo and conveyor visual phase predictably;
- the web build behaves identically for its fixed scripted input sequence.

Do not tune speed or add animation until the basic route can be completed on
hardware. If the belt is visually unclear, improve the graybox marks before
creating art.

## Subsequent mechanic order

After conveyors are stable, add one mechanic at a time and retain the same
small-playtest discipline:

1. pressure plates and gates — proves trigger occupancy, dynamic collision,
   and cargo as puzzle equipment;
2. objective edge indicator — consumes the generalized objective anchor and
   proves HUD submission;
3. portals — proves deferred relocation and contact conflict rules;
4. ice, fragile loads, and broken forklift — prove motion/load modifiers;
5. power and darkness — prove world overlay and powered-device state;
6. scan/recycling cargo — proves cargo metadata and non-delivery objective
   predicates;
7. robots, then trains — prove dynamic actor collections and their rendering;
8. battery routing and larger cargo inventories — raise cargo-store capacity;
9. final warehouse — combine only mechanics that have passed independently.

This order is intentional: it establishes state, triggers, HUD, relocation,
modifiers, and rendering before adding autonomous agents. Do not combine two
untested systems merely because the final warehouse will combine them.

## Verification and handoff checklist

Before declaring a slice complete, run the host unit tests, browser integration
check, and the relevant manual script in the current checkout. Build and run on
hardware for input, visual readability, performance, or crank-feel changes.
Record any intentional visual-baseline changes and the reason.

At the end of each slice, leave the next agent:

- the completed slice name and the next exact slice;
- commands run and their current results;
- whether native simulator, hardware, and web smoke tests were performed;
- capacities selected for cargo, actors, events, commands, and render entries;
- any invariant or ordering decision made while implementing;
- known deviations from parity, if any.

Stop and reassess the architecture only when repeated content demonstrates a
concrete limitation. Candidate evidence for component-store/ECS work is many
dynamic entity types sharing arbitrary combinations of behavior, repeated
cross-type queries, or an increasingly artificial `World` layout. Until then,
extend the bounded runtime through a focused store or mechanic, not a
framework rewrite.
