# Project Forklift — Implementation Guide & MVP Task List

> **Implementation target:** Panic Playdate, Zig, using DanB91's Zig-Playdate-Template  
> **Design target:** top-down forklift game with cumulative crank steering, rear-wheel maneuvering, pallet handling, and a height-aware 2.5D sprite renderer  
> **Development rule:** every major feature should reach the smallest useful, testable form before the next layer of complexity is added.

**Document status:** Working implementation roadmap  
**Version:** 0.3
**Priority:** prove fun and readability first; optimize and beautify only after the relevant mechanic passes its test gate.

---

# Current Project Status — 2026-09-05

## Reader and restart action

**Reader:** a developer starting a fresh session on the prototype.

**Action after reading:** hardware-validate M17a system-menu restart and the Low/Medium/High steering ratios, then implement M17b campaign flow before creating M18 content.

## Proven on hardware

- Persistent crank steering is controllable. Wheelbase `28` is hardware validated. M17a adds selectable `Low` (3:1), `Medium` (2:1), and `High` (1:1) crank-to-wheel ratios; hardware selection of the final default remains pending.
- Straight driving remains possible at crank orientations `0°` and `180°`.
- Forklift body collision uses an oriented rectangle and matches the rendered chassis more closely than the previous circle proxy.
- Four-sided pallets can be picked up from all sides. Valid pickup attaches without a visible jump; carrying and dropping preserve alignment and heading.
- Carried-pallet collision stops the pallet first, allows reverse recovery, and uses the pallet footprint rather than a circle.
- A basic job completes when a pallet is placed in the marked destination; its timer stops on completion.
- Discrete fork heights work: `floor = 0`, `carry = 12`, `rack_low = 30`. The mast is fixed and the carriage/forks move vertically.
- Floor and low-shelf pickup/drop rules work. Shelf drops require full pallet support. Pallet shadows project at their support height, preserving the 2.5D illusion.
- Geometry-based 2.5D forklift, pallet, shelf, rack, and tall-box rendering is readable. The selected parallax strength is `0.001`.
- Rack rendering now uses a filled upper surface plus a camera-facing wall. This produces convincing foreground occlusion in all four cardinal views.
- The four-view camera orbit passes on hardware. Hold B and press Right to rotate clockwise; four presses return to north. Camera rotation is render-only.
- Four fixed jobs run in sequence: standard floor, heavy floor, standard low-shelf to floor, and long floor cargo through a route choice. The long cargo preserves its relative carried orientation, including side pickup. Job transitions preserve forklift position, heading, fork height, steering state, and camera view; final delivery stops the timer.
- A compile-time static level owns static object collision and before/after-actor rendering. The renderer owns cardinal world-bounds culling; it remains separate from world-space physics.
- A representative dense 2.5D stress scene sustains the 50 Hz device cap in ReleaseFast. A spatial grid remains deferred until map scale makes linear collision queries expensive.
- Native Playdate-synth pallet engagement feedback passes hardware validation: exactly one clunk per successful pickup, silence for failed attempts, no stuck/repeating sound, and acceptable volume.
- The native four-track music loop maintains the device's 50 Hz cap and the same tempo on simulator and hardware during normal driving.
- Native pickup and fork-height effects mix with the four-track music loop at the 50 Hz cap. Successful pickups produce one effect, failed attempts are silent, and effect volume is acceptable.
- The fork-height effect's native one-shot pitch sweep passes hardware validation during music, does not alter pickup sound, and has no frame-rate impact.
- PDNA Toolkit song export was copied into the Zig project and runs on hardware at the 50 Hz cap with no frame-rate impact.

## Intentional changes from the original plan

- Production Blender/sprite art is deferred indefinitely. The game uses a geometry-first 2.5D visual style implemented by the renderer. Do not begin an art pipeline unless this decision changes explicitly.
- Pallets are deliberately four-sided to support positioning and cargo-rotation mechanics. Pickup lanes are available on every side.
- Fork-height control uses D-pad Right to raise and D-pad Left to lower. A performs pickup; B performs drop. This replaces the original M12 A/B lift-control suggestion.
- The camera supports four cardinal render-only views: north, east, south, and west. Hold B and press Right to rotate clockwise. World coordinates, forklift physics, collision, pickup, shelf support, and heading do not rotate.
- Arbitrary-angle camera rotation, camera smoothing, camera look-ahead, POV, and zoom are deferred. The four cardinal views solve rack accessibility without adding those systems.

## Desired future camera enhancement

The desired eventual camera is continuously rotatable rather than limited to four cardinal views. The likely control is a held camera-modifier button plus crank rotation; the specific modifier button is intentionally undecided so it does not conflict with established driving, pickup, drop, or fork-height controls.

This remains deferred. It requires arbitrary-angle world projection, general render ordering, and rack top/side-face selection that remain correct at every yaw angle. It must stay render-only: camera rotation must never rotate or alter world-space physics, collision, pickup rules, cargo support, or vehicle heading.

## Current implementation state

The game is currently a four-job warehouse prototype with standard, heavy, and long cargo. Its simulation and renderer are separated: vehicle, cargo, collision, jobs, static level, camera, height projection, and geometry rendering have distinct responsibilities.

The camera projects all rotating world geometry through its cardinal view transform. Ground rectangles use projected corners, and rack foreground occlusion compares screen-relative camera depth rather than raw world Y.

## Camera-orbit completion gate

**Status:** complete on hardware.

- Left alone lowers forks; Right alone raises forks.
- Hold B and press Right to rotate one step clockwise; four presses return to north.
- Movement, steering, collision, pickup, drop, shelf support, and job completion are identical in every view.
- A near-side forklift/pallet renders in front of the rack; a far-side forklift/pallet is occluded by the rack upper surface and foreground wall in every view.
- No rotation behavior modifies world-space state.

## Next implementation slice

Complete the M17a device gate, then implement M17b campaign flow:

1. Validate `Restart Job` from every current job, including while carrying.
2. Compare Low, Medium, and High steering ratios on the existing hardware course; choose the default from that test.
3. Add the title, briefing, shift-results, promotion, and final-completion states around the existing job loop.
4. Save only completed-shift campaign progression. M18 will then author training and warehouse content against this foundation.

Do not expand audio, add a custom pause screen, create a generic runtime level format, procedural generation, failure states, a spatial grid, or future game modes in this slice.

## Verification baseline

Run host tests for camera, 2.5D projection, vehicle, cargo, and collision, then build the game. Validate the orbit and job loop on physical hardware; simulator results do not substitute for crank/control feel.

---

# 1. Implementation Philosophy

The project should be built as a sequence of **small, playable experiments**, not as a collection of infrastructure that eventually becomes a game.

The highest-risk question is not whether a warehouse, cargo system, or 2.5D renderer can be implemented. It is:

> **Is a forklift with persistent crank-driven steering intrinsically fun and understandable on real Playdate hardware?**

Everything should be ordered around answering that question quickly.

The second major question is:

> **Can pickup, carrying, and placement remain readable and fluid entirely from the overhead view?**

The third is:

> **Can the 2.5D height-aware presentation add depth without making collision, navigation, or fork alignment harder to read?**

Only after those three questions are answered positively should production art, content volume, scoring depth, humorous cargo, advanced rack interactions, or optional camera systems receive substantial effort.

## 1.1 Core Development Rules

1. **One new risk at a time.** Do not simultaneously introduce new physics, new camera behavior, new art, and new collision logic.
2. **Debug art before final art.** Rectangles, lines, circles, and labels are preferred until the mechanic is validated.
3. **Simulation is independent of rendering.** The forklift must drive correctly even if every object is rendered as a rectangle.
4. **Collision is independent of artwork.** Never derive physical behavior from parallax-displaced sprite pixels.
5. **Keep Playdate integration thin.** Input, graphics, audio, and file APIs should sit around mostly pure Zig game logic.
6. **Test math on the host where possible.** Steering, transforms, overlap tests, projection, and job rules should be usable from Zig tests without Playdate.
7. **Test feel on hardware early.** Simulator correctness is useful; crank feel and frame pacing must ultimately be validated on the device.
8. **No POV dependency.** The first complete game loop must work entirely overhead.
9. **Do not pre-optimize math.** Start with readable `f32` simulation; profile before replacing trigonometry or introducing fixed-point math.
10. **Avoid unnecessary allocation during play.** Prefer fixed-capacity/static data for frequently used runtime collections.

---

# 2. Toolchain Baseline

The current Zig-Playdate-Template README specifies Zig 0.16.0 and Playdate SDK 3.0.0 or newer, and provides `zig build run` for building and launching the simulator. Zig is not an officially supported Playdate language; the template exposes the Playdate C API through Zig bindings. The template also warns that the Playdate has only about 10 KB of stack space, so large local arrays and stack-heavy `std` usage should be avoided in device code.

## 2.1 Initial Setup Tasks

- [ ] Create the repository from the Zig-Playdate-Template.
- [ ] Pin the exact Zig version used by the project in `README.md` or a tool-version file.
- [ ] Record the Playdate SDK version used for development.
- [ ] Confirm `PLAYDATE_SDK_PATH` is configured.
- [ ] Run the template unchanged with:

```sh
zig build run
```

- [ ] Confirm the example launches in the Playdate Simulator.
- [ ] Build a release configuration at least once:

```sh
zig build -Doptimize=ReleaseSafe
```

- [ ] Confirm a hardware build can be loaded onto a physical Playdate.
- [ ] Commit this untouched/near-untouched baseline before game code begins.

### Test Gate T0 — Toolchain

**Pass when:**

- Simulator build works from a clean checkout.
- Hardware build works.
- The project can be rebuilt without manual file copying.
- Another future checkout can determine which Zig/SDK versions are expected.

**Do not build yet:** game architecture, asset loaders, ECS, generic engine abstractions, level formats, or custom memory systems.

---

# 3. Recommended Project Structure

Start small. Create modules only as their responsibility becomes real.

```text
project/
├── assets/
│   ├── images/
│   └── sounds/
├── src/
│   ├── main.zig              # Playdate event entry point / update callback
│   ├── game.zig              # top-level game state + update/draw orchestration
│   ├── config.zig            # tuning constants
│   ├── input.zig             # Playdate input -> game input snapshot
│   ├── math2.zig             # Vec2, angle helpers, geometry helpers
│   ├── vehicle.zig           # forklift simulation
│   ├── camera.zig            # world camera
│   ├── collision.zig         # simple world collision
│   ├── cargo.zig             # pallet/load state and fork interaction
│   ├── world.zig             # test map / world entities
│   ├── render.zig            # overhead drawing
│   ├── render25d.zig         # z projection/layering once needed
│   ├── jobs.zig              # objectives/scoring once needed
│   ├── assets.zig            # image/sound ownership once real assets exist
│   └── debug.zig             # debug overlays/toggles
├── build.zig
└── pdxinfo
```

Do **not** create all these files on day one. A sensible progression is:

```text
main.zig
math2.zig
vehicle.zig
```

then add camera/collision/cargo/render modules as those features appear.

## 3.1 Architectural Boundary

Keep this dependency direction:

```text
Playdate API
    ↓
main / input / render / audio
    ↓
game orchestration
    ↓
pure-ish simulation modules
    ↓
math / geometry / data
```

Avoid this:

```text
vehicle.zig -> Playdate graphics
cargo.zig   -> Playdate buttons
world.zig   -> screen coordinates
```

That separation makes the difficult parts easier to test and keeps a future renderer change from affecting game rules.

---

# 4. Shared Types to Establish Early

Keep the initial data model intentionally small.

```zig
pub const Vec2 = struct {
    x: f32,
    y: f32,
};

pub const InputState = struct {
    crank_delta_deg: f32,
    forward: bool,
    reverse: bool,
    raise_pressed: bool,
    lower_pressed: bool,
};

pub const Forklift = struct {
    position: Vec2,
    heading_rad: f32,
    steer_angle_rad: f32,
    speed: f32,
};
```

Do not add cargo, fork height, health, scoring, sprite handles, sound handles, or camera data to `Forklift` until they are required.

## 4.1 Coordinate Convention

Choose and document one convention immediately. Suggested:

- world +X = right
- world +Y = down, matching screen coordinates
- heading `0` = facing up or right; choose one and never mix conventions
- positive heading rotation = clockwise if that makes Playdate crank reasoning easier
- angles stored internally in radians
- crank input arrives in degrees and is converted at the input/simulation boundary

Add tests for `forwardVector()` and angle wrapping immediately. Coordinate-sign bugs become extremely expensive once collision and sprite direction selection exist.

---

# 5. Milestone M0 — Empty Game Loop and Debug Harness

**Goal:** establish the smallest game loop that can display state and receive input.

## Tasks

- [ ] Replace the template example with a blank game update callback.
- [ ] Clear the screen every frame.
- [ ] Read D-pad button state.
- [ ] Read crank delta with the Playdate system crank-change API.
- [ ] Draw a crosshair or rectangle at screen center.
- [ ] Draw current FPS using the Playdate debug FPS helper in debug builds.
- [ ] Add a compile-time or runtime `debug_enabled` flag.
- [ ] Add a tiny fixed-size debug text buffer rather than allocating strings every frame.
- [ ] Add a reset action for prototypes, even if it is temporarily mapped to A+B or the system menu.

## Minimal Result

The screen shows a rectangle. Turning the crank changes a number or line. Up/down button state is visibly reflected.

### Test Gate M0

- [ ] Crank delta is positive in one direction and negative in the other.
- [ ] Crossing crank 0°/360° does not produce a giant discontinuity because the game uses **delta**, not absolute crank position.
- [ ] Input continues to behave after several full crank rotations.
- [ ] FPS display is stable.
- [ ] Runs on physical Playdate.

**Stop and fix any input problem here.** Persistent steering depends entirely on trustworthy crank delta.

---

# 6. Milestone M1 — Steering Laboratory

This is the first real game experiment and should be reached as quickly as possible.

**Goal:** drive a rectangle around an empty screen/world with the crank controlling persistent steering.

## 6.1 Steering State

Do not map the physical crank's absolute 0–360 position directly to steering. Accumulate crank delta:

```zig
forklift.steer_angle_rad = wrapAngle(
    forklift.steer_angle_rad +
    degreesToRadians(input.crank_delta_deg) * steering_gain
);
```

The resulting steering state remains where the player leaves it.

## 6.2 Continuous 360° Steering Curve

A conventional automobile bicycle model normally assumes a limited steering angle and uses something like `tan(steerAngle)`. That becomes unsuitable near ±90° and does not naturally represent the intended continuous steering loop.

For the **first playable prototype**, use a deliberately game-oriented periodic curvature mapping:

```text
curvature = max_curvature × sin(steer_angle)
angular_velocity = speed × curvature
```

This gives a clean continuous loop:

```text
steer angle   effect
0°            straight
90°           maximum turn A
180°          straight
270°          maximum turn B
360° / 0°     straight
```

That behavior matches the important design idea: continuing to crank in one direction cycles naturally through straight → right/left maximum → straight → opposite maximum → straight.

Treat this as the **baseline feel model**, not sacred physics. Later compare it against any more physically derived model only if the baseline feels wrong.

## 6.3 Movement MVP

- [ ] D-pad Up accelerates toward positive driving speed.
- [ ] D-pad Down accelerates toward reverse speed.
- [ ] Neither pressed causes coast/deceleration toward zero.
- [ ] Apply a top speed.
- [ ] Integrate heading from angular velocity.
- [ ] Integrate position along body forward vector.
- [ ] Draw the body as a rectangle/polygon.
- [ ] Draw a conspicuous rear steer-wheel line showing the **actual persistent steering angle**.
- [ ] Draw a heading line from the forklift body.
- [ ] Display steer angle, speed, and curvature in debug mode.

## 6.4 Initial Tuning Variables

Put these in `config.zig` from the start:

```zig
pub const steering_gain: f32 = 1.0;
pub const max_curvature: f32 = ...;
pub const acceleration: f32 = ...;
pub const braking: f32 = ...;
pub const coast_drag: f32 = ...;
pub const max_forward_speed: f32 = ...;
pub const max_reverse_speed: f32 = ...;
```

Do not scatter tuning numbers throughout update code.

## 6.5 Host Tests

- [ ] `wrapAngle` handles negative and multiple-turn inputs.
- [ ] steer angle returns to equivalent state after ±2π.
- [ ] curvature is approximately zero at 0°, 180°, and 360°.
- [ ] curvature reverses sign between 90° and 270°.
- [ ] zero speed produces zero heading change.
- [ ] reverse speed reverses turn response consistently.

### Test Gate M1 — Is Steering Fun?

Create a blank test field with a few primitive cones/markers and spend several minutes driving.

Pass when:

- [ ] Continuous crank rotation is immediately understandable after a short explanation.
- [ ] The player can intentionally drive straight after multiple crank revolutions.
- [ ] Tight turns feel controllable rather than random.
- [ ] Reverse steering is learnable.
- [ ] Rear swing is visible in the body's motion.
- [ ] The steering ratio does not require frantic cranking for ordinary maneuvering.
- [ ] The game is already mildly entertaining with no art, cargo, scoring, or warehouse.

### Required Experiment

Test at least three steering gains/ratios on hardware. Record the chosen baseline rather than relying on memory.

**Do not proceed to art if M1 is not fun.** This is the project's primary kill/tune gate.

---

# 7. Milestone M2 — Large World and Camera Follow

**Goal:** prove that driving remains readable when the forklift moves through a world much larger than 400×240.

## 7.1 World Coordinates

From this milestone onward, the forklift lives in world coordinates. Screen coordinates are purely a rendering concern.

```zig
screen_x = world_x - camera.x;
screen_y = world_y - camera.y;
```

The Playdate C graphics API also supports a global draw offset suitable for scrolling worlds. Either approach is valid. For the MVP, prefer whichever keeps debug geometry and later z/parallax projection easiest to reason about. If using global draw offset, keep HUD/debug overlays explicitly in screen coordinates.

## 7.2 Camera MVP

Start with the simplest possible camera:

- [ ] camera follows forklift position
- [ ] forklift remains near screen center
- [ ] camera clamps to test-world bounds

Only after that works:

- [ ] add smooth follow
- [ ] add modest velocity/heading look-ahead
- [ ] smooth the look-ahead reversal when changing direction

Suggested state:

```zig
pub const Camera = struct {
    position: Vec2,
    target: Vec2,
    look_ahead: Vec2,
};
```

## 7.3 Test Map

Build a primitive map around 1200×800 or larger containing only lines/filled rectangles:

- open driving yard
- narrow aisle
- 90° corner
- dead-end bay
- slalom markers
- loop around a large obstacle

### Test Gate M2 — Camera

- [ ] World can be several screens wide/tall.
- [ ] Camera never changes simulation coordinates.
- [ ] Steering remains easy to read while the camera scrolls.
- [ ] Reversing does not cause camera whiplash.
- [ ] No visible jitter occurs at low speed.
- [ ] The player can see enough space ahead to plan a turn.

**MVP before refinement:** if a rigid camera works, keep moving. Camera smoothing is polish until navigation proves it needs improvement.

---

# 8. Milestone M3 — Chassis Collision

**Goal:** make warehouse geometry matter without yet implementing pallets.

## 8.1 Collision MVP

Do not begin with the Playdate sprite collision system. The Zig template notes that some translated APIs, including sprite APIs, have historically had less testing than the core C surface. For this game, custom simple geometry is useful anyway because simulation collision should remain independent from layered/parallax art.

Start with:

- forklift body = circle or axis-aligned approximation if necessary
- racks/walls = axis-aligned rectangles
- collision response = reject movement or move back to last valid position

This is intentionally crude.

## 8.2 Second Collision Step

Once navigation proves useful:

- [ ] forklift body becomes an oriented rectangle (OBB)
- [ ] rear counterweight can use a second circle/rectangle if that improves rear-swing contacts
- [ ] obstacles remain rectangles where possible
- [ ] broad-phase checks only nearby obstacles

## 8.3 Collision Debug Drawing

Always support:

- [ ] body collision outline
- [ ] obstacle collision outlines
- [ ] contact point/normal if calculated
- [ ] current overlapping obstacle ID

### Test Gate M3 — Warehouse Maneuvering

Build two long shelf rows with a narrow turn between them.

Pass when:

- [ ] clipping the counterweight into a shelf is detected
- [ ] collisions are recoverable; the forklift does not become permanently stuck
- [ ] rear swing is now a meaningful gameplay concern
- [ ] tight maneuvering feels challenging for the right reason
- [ ] collision does not visibly disagree with placeholder body dimensions

**Do not implement fancy collision response.** A forklift is slow; reliable and predictable is more valuable than physically rich bouncing.

---

# 9. Milestone M4 — Visible Forks, No Cargo Yet

**Goal:** make the forks part of the actual simulated vehicle before implementing pickup rules.

## Tasks

- [ ] Define front axle/body reference point.
- [ ] Define fork base relative to body.
- [ ] Define two fork tine centerlines/rectangles.
- [ ] Transform fork geometry by vehicle heading each frame.
- [ ] Render forks clearly in overhead view.
- [ ] Add debug outlines for fork interaction geometry.
- [ ] Ensure forks rotate/move with vehicle without sprite art.
- [ ] Decide whether forks collide with walls in the first cargo prototype.

Suggested conceptual transform:

```text
local tine position
    ↓ rotate by forklift heading
world tine position
    ↓ camera projection
screen tine position
```

### Test Gate M4

- [ ] Fork tips remain visually stable relative to the truck.
- [ ] Fork placement is readable while turning.
- [ ] Player can intentionally point forks into a marked target rectangle from overhead.
- [ ] Fork geometry does not depend on final sprite dimensions.

---

# 10. Milestone M5 — One Pallet Pickup

This is the second major game-design gate.

**Goal:** pick up and place one pallet entirely from the overhead view, with no special camera and no polished art.

## 10.1 Pallet MVP Data

```zig
pub const Pallet = struct {
    position: Vec2,
    heading_rad: f32,
    state: enum { floor, carried },
};
```

Keep cargo separate for now. The pallet is just a rectangle with two visible fork-entry lanes.

## 10.2 Pickup Rules MVP

A pickup succeeds when all of these are true:

1. fork tines overlap their acceptable entry lanes
2. relative vehicle/pallet angle is within tolerance
3. insertion depth exceeds a threshold
4. A/raise is pressed

For this milestone, fork height can be binary:

```text
DOWN
UP/CARRY
```

No rack heights yet.

## 10.3 Implementation Tasks

- [ ] Draw pallet body rectangle.
- [ ] Draw two high-contrast fork-entry zones.
- [ ] Calculate pallet local-space position of each tine.
- [ ] Calculate relative heading error.
- [ ] Calculate insertion depth.
- [ ] Expose all pickup metrics in debug overlay.
- [ ] Press A to attach if valid.
- [ ] Attached pallet transform follows forklift/forks.
- [ ] Press B to detach and place on floor.
- [ ] Allow re-pickup after placement.
- [ ] Add a reset key/menu item for failed experiments.

## 10.4 Make Tolerances Data, Not Logic

```zig
pub const PickupTuning = struct {
    max_angle_error_rad: f32,
    tine_lateral_tolerance: f32,
    minimum_insertion: f32,
};
```

Start generous.

### Test Gate M5 — Pickup Readability

Perform at least 20 pickups in a row.

Pass when:

- [ ] alignment can be judged from overhead
- [ ] the player understands why a clearly bad pickup fails
- [ ] slightly imperfect pickups usually succeed
- [ ] experienced pickup becomes one fluid approach → insert → lift motion
- [ ] player does not wish for a mandatory POV camera
- [ ] placement is quick and does not feel like a separate minigame

If this gate fails, first adjust:

1. fork/pallet visual scale
2. high-contrast fork pockets
3. pickup tolerances
4. camera behavior at very low speed
5. optional top-down zoom

Only consider POV after those cheaper fixes fail.

---

# 11. Milestone M6 — Carrying Changes Driving

**Goal:** prove that cargo creates new maneuvering gameplay rather than merely serving as an objective token.

## MVP Load Effects

Implement exactly two effects first:

- [ ] pallet extends collision/clearance footprint in front of vehicle
- [ ] carried load reduces acceleration or maximum speed slightly

Then test.

Do not add stability, tipping, damage, weight classes, visibility, or sway until the basic loaded trip is fun.

## Tasks

- [ ] Add carried pallet to effective front footprint.
- [ ] Ensure collisions while loaded are clear and recoverable.
- [ ] Add one configurable handling multiplier.
- [ ] Add a narrow route that is easy empty but harder loaded.
- [ ] Add one loading bay requiring reverse maneuvering.

### Test Gate M6

- [ ] empty and loaded forklift noticeably require different driving decisions
- [ ] load is never visually detached from the forks
- [ ] carrying does not make controls sluggish or annoying
- [ ] route planning begins to matter

---

# 12. Milestone M7 — First Complete Job Loop

At this point the project should become a tiny actual game.

**Goal:** spawn one pallet at A, show destination B, deliver it, receive success feedback, and restart/repeat.

## Tasks

- [ ] Define one pickup entity ID.
- [ ] Define one destination rectangle.
- [ ] Highlight destination clearly.
- [ ] Detect valid placement inside destination.
- [ ] Display `JOB COMPLETE` or equivalent.
- [ ] Track elapsed job time.
- [ ] Allow immediate restart/new attempt.
- [ ] Add one simple impact count if collision events already exist.

## Minimal Job State

```zig
pub const JobState = enum {
    waiting_for_pickup,
    carrying,
    delivered,
};
```

Do not build a generic quest system yet.

### Test Gate M7 — First Vertical Micro-Slice

A new player should be able to:

1. start
2. understand the crank steering
3. navigate to a pallet
4. pick it up
5. carry it through a constrained route
6. place it in the destination
7. understand that the job is complete

All with placeholder graphics.

**This is the earliest meaningful external playtest build.**

---

# 13. Milestone M8 — Minimal Height-Aware 2.5D Renderer

Only begin this once the flat graybox game loop works.

**Goal:** demonstrate convincing height using the smallest renderer possible.

## 13.1 Add Z Without Changing XY Physics

Introduce `z` and `height` where needed:

```zig
pub const Transform25D = struct {
    position: Vec2,
    z: f32,
    height: f32,
};
```

World collision remains primarily XY.

## 13.2 Projection MVP

Start with the simplest height projection:

```text
screenX = worldX - cameraX + z * skewX
screenY = worldY - cameraY - z * skewY
```

This gives elevation but not camera-relative parallax.

Use it first for:

- fork raised vs lowered
- pallet on ground vs carried
- one tall test crate

### Test Gate M8A — Height Readability

- [ ] raised pallet visibly separates from floor
- [ ] fork height is understandable without a HUD
- [ ] collision still clearly belongs to the object's ground footprint

## 13.3 Add Ground Shadows

Before true parallax, add shadows:

- [ ] pallet shadow remains on floor
- [ ] carried pallet moves upward/offset while shadow stays grounded
- [ ] tall test object has a stable ground shadow

This may produce more useful depth than additional projection math.

### Test Gate M8B — Shadows

Ask a tester to identify whether a pallet is on the floor or lifted without explaining the indicator.

---

# 14. Milestone M9 — 2.5D Parallax Experiment

**Goal:** determine the minimum camera-relative offset that produces depth without making the world look unstable.

Do this with **one tall box and one rack**, not the entire warehouse.

## 14.1 Parallax Model

Conceptually, higher layers receive a tiny extra offset based on their position relative to camera/screen center.

Keep it parameterized:

```zig
pub const ProjectionTuning = struct {
    z_skew_x: f32,
    z_skew_y: f32,
    perspective_strength: f32,
};
```

## Tasks

- [ ] Draw object ground/base layer.
- [ ] Draw body layer at a mid-height.
- [ ] Draw top layer at full height.
- [ ] Shift layers subtly as the camera moves around them.
- [ ] Drive a loop around the object repeatedly.
- [ ] Test very low, medium, and intentionally excessive parallax strengths.
- [ ] Record the maximum acceptable value.

### Test Gate M9 — Stable Depth

Pass when:

- [ ] object clearly feels taller than a flat sprite
- [ ] top appears connected to base
- [ ] object does not look like separate layers sliding over each other
- [ ] player can still judge ground collision footprint
- [ ] parallax is still pleasant during rapid camera movement

If subtle parallax adds little, keep the system mostly as layered pre-rendered perspective + shadows. Do not preserve complexity merely because it was planned.

---

# 15. Milestone M10 — Draw Sorting and Occlusion

**Goal:** let the forklift convincingly pass in front of and behind tall warehouse structures.

## 15.1 Simplest Sort

Assign each renderable a ground sort anchor, usually its ground-footprint bottom Y.

- [ ] Collect visible render commands.
- [ ] Sort by ground anchor Y.
- [ ] Draw back-to-front.

For a small initial scene, a simple insertion sort or fixed-array sort is acceptable. Avoid designing a general render graph.

## 15.2 Split Rack Experiment

Use one rack with:

```text
rear/base layer
stored pallet layer
front-post layer
upper/top layer
```

The forklift should be able to pass behind the appropriate foreground parts while remaining spatially readable.

### Test Gate M10

- [ ] forklift passes in front of rack when physically in front
- [ ] forklift is occluded appropriately when behind
- [ ] foreground rack posts do not hide the entire vehicle unnecessarily
- [ ] fork/pallet interaction zones remain readable
- [ ] no sorting logic affects collision state

---

# 16. Milestone M11 — First Real Art Pipeline

> **Current decision:** superseded for this prototype. Geometry-based 2.5D rendering is the selected art direction. Keep the renderer geometry-first and do not start the Blender/sprite pipeline unless the project explicitly revisits this decision.

Original plan (superseded): Blender/pre-rendered production art would become a significant task here.

**Goal:** replace one graybox scene with representative final-style assets without changing simulation.

## 16.1 Blender Template

- [ ] Create one `.blend` file containing the canonical orthographic/high-angle camera.
- [ ] Lock camera angle and focal/orthographic settings.
- [ ] Lock simple lighting setup.
- [ ] Establish black/white material rules suitable for 1-bit conversion.
- [ ] Create a world-scale reference so forklift, pallets, racks, and cargo remain proportionally consistent.

## 16.2 Forklift Art MVP

Start with **16 directions**.

- [ ] Render 16 directional body frames.
- [ ] Convert to 1-bit.
- [ ] Clean only enough to test motion.
- [ ] Use nearest directional frame from heading.
- [ ] Keep steer wheel/tire as an independent visual if possible.

Test 16 directions on hardware before producing 32/64.

### Direction Test

- [ ] Is stepping visible during normal speed?
- [ ] Does it hurt steering readability?
- [ ] Does 32 materially improve the presentation?

Only go to 64 if 32 is visibly inadequate and memory/draw cost remains acceptable.

## 16.3 Representative Asset Set

Produce only:

- one forklift
- one pallet
- one rack family
- one wall/door element
- one ordinary cargo item
- one silly/tall cargo item

### Test Gate M11 — Art Direction

A screenshot/video from the representative scene should answer:

- [ ] does the game look intentionally 1-bit rather than like a degraded grayscale render?
- [ ] does scrolling avoid dither shimmer?
- [ ] are forks and steering still more readable than decorative detail?
- [ ] does the 2.5D effect survive real art?

---

# 17. Milestone M12 — Fork Height and Rack Shelf

> **Status:** complete. The implementation uses D-pad Right/Left for discrete raise/lower, A for pickup, and B for drop. The three validated heights are `floor = 0`, `carry = 12`, and `rack_low = 30`.

**Goal:** add vertical gameplay only after the renderer can communicate it.

Start with discrete useful heights:

```zig
pub const ForkHeight = enum {
    floor,
    carry,
    rack_low,
};
```

Internally this can map to numeric Z values.

## Tasks

- [x] D-pad Right raises toward the next useful state; D-pad Left lowers.
- [x] Add one rack shelf support Z.
- [x] Add one pallet on shelf.
- [x] Pickup validates vertical fork range.
- [x] Placement validates shelf support height.
- [x] Lifted pallet shadow/offset visibly matches its Z.

### Test Gate M12

- [x] player can identify correct fork height from overhead
- [x] shelf pickup works without a POV camera
- [x] vertical mistakes are understandable rather than mysterious
- [x] discrete heights feel sufficient for gameplay

If exact continuous fork height provides no extra fun, keep discrete states.

---

# 18. Milestone M13 — Cargo Data and First Variation

> **Status:** complete. Standard and heavy pallets have identical interaction rules; the heavy pallet uses carried acceleration multiplier `0.45`, validated on hardware.

**Goal:** prove that cargo type can change gameplay without adding bespoke logic everywhere.

## 18.1 Separate Pallet From Cargo

```zig
pub const CargoDef = struct {
    carried_acceleration_multiplier: f32,
};
```

The per-job pallet state owns a copied cargo definition. Keep the existing pallet footprint, height, pickup lanes, and renderer unchanged for this first variation.

## First Cargo Variation

1. **Standard pallet** — existing baseline multiplier.
2. **Heavy pallet** — reduced carried acceleration only.

Assign the heavy pallet to the second fixed job. Do not add braking changes, altered geometry, fragility, special pickup rules, or visual variants in this slice.

### Test Gate M13

- [x] player can feel which cargo is heavy without reading a number
- [x] standard and heavy cargo use identical pickup, collision, drop, shelf-support, and camera rules
- [x] adding the heavy cargo requires no vehicle steering-code changes

---

# 19. Milestone M14 — Small Job Set

> **Status:** complete. The four-job playtest passed; reverse placement is optional and does not block the milestone.

**Goal:** find out whether the game can support repeated play using combinations of existing systems.

Create up to 5 jobs:

1. floor pallet → open bay
2. floor pallet → tight bay
3. shelf pallet → staging area
4. long cargo → destination requiring route choice
5. optional: a fixed job added only to address a playtest finding

## Tasks

- [x] data-drive pallet spawn position and support height
- [x] data-drive cargo selection
- [ ] record completion time
- [ ] record impact count
- [ ] record placement quality only if it is easy to calculate/read
- [ ] next-job progression
- [ ] retry current job

### Test Gate M14 — Repetition

Have a tester play all available jobs and then repeat some. Four jobs are sufficient for this gate unless a specific playtest finding justifies a fifth.

Pass when:

- [x] driving remains the dominant fun activity
- [x] pickup is not described as repetitive ceremony
- [x] jobs feel meaningfully different despite sharing controls
- [x] at least one load creates a memorable maneuvering problem

---

# 20. Milestone M15 — Performance Baseline and Spatial Culling

> **Status:** complete for the current prototype. A ReleaseFast hardware stress scene with filled 2.5D racks runs at the 50 Hz cap (`20.4 ms`), and renderer-owned cardinal world-bounds culling is hardware-validated. Keep the linear collision pass; defer a spatial grid until future map scale justifies it.

Do this **before** building a large warehouse.

**Goal:** establish measured headroom with representative art and entities.

## Tasks

- [x] create a stress scene with more racks/pallets than a normal screen
- [x] show FPS/debug timing on hardware
- [x] count submitted renderables, render layers, and collision candidates
- [x] measure simulator and physical device separately
- [x] skip render work outside cardinal camera world bounds

## 20.1 Add a Uniform Spatial Grid Only When Needed

A simple grid is enough:

```text
world
┌────┬────┬────┬────┐
│    │    │    │    │
├────┼────┼────┼────┤
│    │ F  │    │    │
├────┼────┼────┼────┤
│    │    │    │    │
└────┴────┴────┴────┘
```

Use it to query nearby:

- collision obstacles
- pallets/cargo
- renderables

Prefer fixed-capacity cell lists or precomputed static world lists where practical.

### Test Gate M15

- [x] off-screen objects are not unnecessarily rendered
- [ ] collision cost scales with nearby objects, not entire map size when world scale justifies a grid
- [x] representative dense scene maintains target frame pacing on device in ReleaseFast
- [x] no per-frame heap churn is required for ordinary queries

---

# 21. Milestone M16 — Native-Synth Audio and Mechanical Feedback

> **Status:** The realtime ZzFX/ZzFXM experiment is removed. Six custom generator music voices reduced the game to roughly 1 FPS, and ZzFX effects reduced frame rate to roughly 20 FPS while native music played. Four native music tracks and two native effect voices pass hardware validation. PDNA Toolkit song export has also passed hardware playback at the 50 Hz cap. Next: plan and spike the bounded native-expression v2 contract before changing adapters or toolkit exports.

Add audio only after the loop works, but before broad content production because feedback can materially change feel.

## Native-Synth Effect Experiment

- [x] `audio.zig` owns a fixed pool of two to four pre-created native `PDSynth` voices
- [x] effects are static Zig presets for waveform, ADSR, pitch, velocity, duration, and volume
- [x] a preset is played through a reusable voice; ordinary play does not allocate
- [x] pallet engagement `clunk` fires only after a successful pickup

The temporary experiment uses Playdate-native waveforms and envelopes. The ZzFX-compatible path below deliberately uses a custom generator inside `PDSynth`; it must stay fixed-voice, allocation-free during playback, and narrowly scoped to ZzFX recipe rendering.

## Native Effect Presets

Effects use the same native waveform, ADSR, MIDI pitch, velocity, duration, and volume contract as music. A fixed pool of two PDSynth voices is reused; effect playback has no custom per-sample renderer or ordinary-play allocation.

- [x] two native effect voices are separate from the four native music voices
- [x] pallet engagement maps to a short native noise preset
- [x] fork-height movement maps to a short native triangle preset
- [x] native pickup and fork effects mix correctly with music on hardware
- [x] each reusable effect voice owns a preallocated native LFO for optional pitch sweep
- [x] fork-height pitch sweep passes hardware validation with music

## Later Mechanical Presets

- [ ] hydraulic raise/lower sound
- [ ] metal collision sound
- [ ] job completion sound
- [ ] motor/rolling loop or simple speed-dependent motor sound

Optional early test:

- [ ] subtle steering mechanical tick tied to crank delta

## Native Four-Track Music

Music uses the Playdate-native synth and sequencer rather than the custom ZzFX generator. Each track is monophonic; the initial four voices are square lead, square harmony/arpeggio, triangle bass, and noise percussion. Music notes are static Zig data. The SDK owns waveform generation, envelopes, and scheduled playback.

- [x] four monophonic native music voices are separate from two native effect voices
- [x] each native voice has an explicit waveform, ADSR, and volume
- [x] static Zig note data populates a four-track native `SoundSequence`
- [x] sequence playback loops without game-loop timing or custom per-sample rendering
- [ ] music plays on hardware without stealing, muting, or delaying simultaneous effects

Do not build a tracker, parser, converter, generic music format, custom generator, or generic mixer.

### Test Gate M16

- [x] pickup can be confirmed by sound without staring at HUD
- [x] repeated successful pickups do not fail, leak voices, or become irritating
- [x] ordinary effect playback performs no allocation and keeps voice ownership bounded
- [x] native pickup effects remain distinct and pleasant during music
- [x] native fork effects remain distinct and pleasant during music
- [ ] four-track native music tempo remains stable during normal driving and camera orbit
- [x] native music does not steal, mute, or delay simultaneous pallet/fork effects
- [ ] collision severity is understandable after the collision preset is added
- [ ] any music loop is tested separately on hardware after the effect gate passes

---

# 22. Milestone M17 — System Menu Restart and Steering Ratio

> **M17a scope:** use the Playdate system menu; do not build a redundant in-game pause state or pause overlay. The system menu already pauses the game and supports up to three project menu items.

Do not build progression persistence before there is progression worth saving.

## M17a — Native system-menu controls

1. Add a `Restart Job` item with `system.addMenuItem`.
2. Its callback sets a pending restart request only. The normal update path consumes that request and restores the current job's authored initial state: job index, pallet/load state, forklift position and heading, speed, steering state, fork height, camera view, timer, and destination state.
3. Add a `Steering Ratio` option item with `system.addOptionsMenuItem` and exactly three labels: `Low`, `Medium`, and `High`.
4. Map the selected setting only at crank-input-to-wheel-steering conversion:

   | Setting | Crank rotations : wheel rotations | Wheel-angle multiplier |
   | --- | --- | --- |
   | Low | 3:1 | `1.0 / 3.0` |
   | Medium | 2:1 | `1.0 / 2.0` |
   | High | 1:1 | `1.0` |

   The setting must not alter vehicle geometry, speed, collision, cargo, camera behavior, or world coordinates.
5. Default to `Medium` (2:1). Do not silently retune the selected baseline while adding menu plumbing; change the default only after the M17a hardware comparison.
6. Keep the selected ratio in session state only for M17a. Persistence is a later, separate decision.

### Hardware gate

- Opening the system menu pauses safely; no custom pause UI exists.
- `Restart Job` works from every fixed job and does not leave carrying, timer, audio, or camera state stale.
- Each steering option is selectable from the system menu and changes only steering responsiveness.
- Low, Medium, and High are each driven through the existing slalom, tight turn, and reverse-recovery course on hardware. Record the preferred default after that test.

## M17b — Campaign, Shift, and Progression Foundation

### Reader and action

**Reader:** an engineer preparing M18 stages, shifts, jobs, and tutorial content.

**Action after reading:** implement campaign flow around the existing delivery simulation so authored content can define a stage, its shifts, their jobs, boss briefings, scoring targets, and promotion outcome without changing core vehicle, cargo, collision, or renderer rules.

### Goal and player-facing loop

`Forklift Certified` is a forklift-operator campaign:

```text
Title → Continue Main Game → boss briefing → shift jobs → shift results
      → next shift | stage promotion → next stage → campaign complete
```

- A **job** is one existing pickup-and-delivery objective.
- A **shift** is an ordered, mandatory list of jobs in one warehouse stage. Completing a job starts only the next job in that shift.
- A **stage** is one warehouse, its fixed layout, theme, obstacle vocabulary, and ordered shifts.
- A **campaign** is the ordered list of stages.

The title screen initially has one selectable action: `Continue Main Game`. With no completed-shift save, it starts the first training shift. With a save, it starts the next unlocked, unfinished shift. Do not add a future-game-mode abstraction yet.

The first stage is the **Training Facility**. Its early shifts are tutorials: boss messages introduce movement, steering ratio, camera orbit, fork height, pickup, carrying, shelves, heavy cargo, long cargo, and route planning only when each concept first becomes relevant. Completing every Training Facility shift shows the promotion reward **Forklift Certified** and unlocks the first real warehouse stage. Each later stage must introduce a distinct warehouse theme and at least one obstacle or handling challenge not already taught. Completing the final stage shows a campaign-complete/win screen.

### Authored data boundary

Campaign flow is static authored data. It does not introduce runtime map loading or a generic level format. A stage selects one compile-time static warehouse level through its stage identity; stage metadata selects its shifts and presentation.

Each authored shift needs:

```zig
pub const ShiftDefinition = struct {
    id: ShiftId,
    stage_id: StageId,
    title: []const u8,
    jobs: []const JobDefinition,
    briefings: []const BossMessage,
    scoring: ShiftScoring,
};

pub const BossMessage = struct {
    trigger: BriefingTrigger,
    pages: []const []const u8,
};

pub const BriefingTrigger = union(enum) {
    shift_start,
    before_job: usize,
};

pub const ShiftScoring = struct {
    completion_points: u32,
    target_time_seconds: f32,
    time_bonus_per_second: u32,
    collision_penalty: u32,
};
```

`StageDefinition` contains a stable identity, display name, ordered shift identities, and `promotion_pages`. `CampaignDefinition` contains the ordered stage identities and `campaign_complete_pages`. Promotion and final pages use the same Boss text-box presentation after a stage or campaign completes. Keep IDs stable after release because saves use them; display text is not an identifier.

`JobDefinition` remains the atomic cargo/destination definition. M18 may add authored job labels or tutorial tags only when a briefing or results screen needs them. Do not add per-job scoring, branching jobs, random jobs, or job failure states in M17b.

### Boss briefings

Boss briefings are static pages in a simple text box, not a dialogue engine. The box identifies the speaker as `Boss`, wraps one page at a time, and advances with A. It appears at a shift start or immediately before its named job. While it is visible, no job simulation or job timer runs. It is used for instruction and new-mechanic introductions; stage promotion and final-win pages use the same presentation.

Do not add choices, portraits, localization infrastructure, runtime scripting, cutscenes, or arbitrary mid-frame message injection.

### Shift state and results

The top-level game-flow state is exactly:

```text
title | briefing | playing_shift | shift_results | promotion | campaign_complete
```

`playing_shift` owns the active job index, existing job state, pallet, forklift state, and elapsed shift time. Existing job completion advances the active job index. Completing the final job freezes shift simulation and opens `shift_results`.

Shift results show:

- shift name and completion status;
- completion time and time bonus;
- completed-job count;
- collision impact/damage count;
- points earned; and
- the next unlocked shift or promotion outcome.

Score is shift-scoped and deterministic:

```text
points = max(0,
    completion_points
    + max(0, target_time_seconds - elapsed_seconds) * time_bonus_per_second
    - collision_impacts * collision_penalty)
```

Use integer points and round the time bonus down to whole points. A collision impact is recorded once when a movement attempt first becomes blocked by collision; it is not recorded every frame while the forklift remains in contact. Each impact increments both `collision_impacts` and the displayed damage count. Damage has no physical health bar and cannot fail a job in this milestone.

### Progress save

Save only after the player confirms a completed shift result or promotion. Do not save mid-job.

The explicit, versioned save contains:

```text
save_version
next_unfinished_stage_id
next_unfinished_shift_id
campaign_complete
```

At shift completion, unlock and save the next shift. At the final shift of a stage, show its promotion, unlock and save the next stage's first shift, then continue. At the final campaign shift, save `campaign_complete = true` and show the win state. Restarting a job never changes saved progression.

Do not persist best time, high score, partial shift state, steering ratio, raw structs, or audio state in M17b. Best-score persistence and optional settings are M17c after scoring and settings values stabilize.

### Implementation order

1. Define stable campaign, stage, shift, boss-message, scoring, and progress-save data using the current four jobs as one provisional Training Facility shift.
2. Add the title screen and `Continue Main Game` entry path.
3. Add briefing and `playing_shift` state transitions around existing jobs; preserve current cargo, collision, renderer, and render-only camera invariants.
4. Add impact-onset accounting and shift results with the deterministic score formula.
5. Add completed-shift save/load, promotion, next-stage unlock, and final campaign-complete flow.
6. Replace the provisional Training Facility shift with authored multi-shift Training Facility content only during M18 content production.

### Hardware gate

- A fresh install starts Training Facility shift one from the title screen.
- The next job is unavailable until the current job is delivered.
- Boss pages block job input and timer until dismissed, then return to the intended job.
- Restarting an active job does not alter saved progression, active shift identity, or prior completed shifts.
- A sustained collision counts one impact, while separating and colliding again counts a second.
- Shift results report deterministic time, impact count, and points.
- Completing a shift survives reboot and `Continue Main Game` starts the next unfinished shift.
- A test-only short campaign proves stage promotion, the `Forklift Certified` reward, next-stage unlock, and final win flow.
- Gameplay stays at the established device frame-rate cap during normal driving and results/briefing transitions.

## Deferred M17c — Optional settings and best results

- [ ] optional steering-angle indicator checkmark item
- [ ] persist steering ratio after the preferred default is hardware selected
- [ ] save best score/time after the scoring formula is hardware tuned

Avoid serializing raw structs directly if layout/version changes could break saves. Use a small explicit save format/version.

---

# 23. Milestone M18 — Content Production

Only now scale up.

## Warehouse Content Tasks

- [ ] reusable rack modules
- [ ] corners/end caps
- [ ] loading dock pieces
- [ ] floor markings
- [ ] bollards/posts
- [ ] doors/clearance structures
- [ ] staging zones
- [ ] visual landmarks

## Cargo Content Tasks

- [ ] standard industrial loads
- [ ] appliances/machines
- [ ] pipes/lumber/oversized loads
- [ ] humorous cargo silhouettes
- [ ] one or two animated gag loads only after static variety works

## Level Design Tasks

- [ ] training yard
- [ ] certification pickup/drop
- [ ] narrow aisle warehouse
- [ ] loading dock
- [ ] shelf-height challenge
- [ ] oversized-load route puzzle
- [ ] multi-job shift

Every new level should answer:

> **What steering, route-planning, fork-height, or load-handling skill does this space exercise that an existing level does not?**

---

# 24. Deferred Feature Gate — Precision Zoom / POV

Do not implement this during the roadmap above unless playtesting produces a specific unresolved visibility problem.

Trigger consideration only if:

- players repeatedly fail pickups despite generous tolerances
- players cannot determine fork height despite strong shadows/z cues
- high-rack work is unreadable overhead
- a top-down precision zoom has been tested and is insufficient

Evaluation order:

1. improve fork/pallet silhouettes
2. improve shadows and z displacement
3. slow camera/look-ahead near pickup
4. add top-down zoom
5. only then prototype POV

POV remains a **separate optional feature**, never a requirement for basic cargo interaction.

---

# 25. Zig-Specific Implementation Guidance

## 25.1 Keep Large Runtime State Off the Stack

The Zig Playdate template warns about the Playdate's very small stack. Therefore:

- keep the main `Game` state static/global or heap-owned for the application's lifetime
- avoid large local arrays inside update/draw functions
- avoid recursive algorithms
- use fixed-capacity buffers stored in persistent game state
- be cautious with `std` functions that create large temporary stack values
- use the Playdate allocator/API or a deliberately simple allocator strategy only when dynamic allocation is genuinely needed

## 25.2 Prefer Fixed-Capacity Runtime Collections

For example:

```zig
const MaxVisible = 128;

pub const RenderQueue = struct {
    items: [MaxVisible]RenderCommand = undefined,
    len: usize = 0,
};
```

Do the same for nearby collision candidates if practical.

This makes frame behavior predictable and avoids allocator surprises.

## 25.3 Separate Device API Handles From Simulation Data

Good:

```text
ForkliftState
  position
  heading
  steering
  speed

ForkliftVisual
  image table handles
  frame selection
```

Avoid putting Playdate bitmap pointers into every simulation object unless that ownership relationship is genuinely useful.

## 25.4 Use Pure Functions for Geometry

Good candidates for host-side Zig tests:

```text
wrapAngle
shortestAngleDifference
rotateVector
worldToLocal
localToWorld
forwardVector
orientedRectCorners
obbVsAabb
forkEntryScore
projectZ
headingToSpriteIndex
```

The more of the game that can be tested with `zig test`, the less debugging must happen through device graphics.

## 25.5 Floating Point First

Start with `f32` for:

- world position
- heading
- steering angle
- speed
- projection

If profiling later identifies `sin`, `cos`, or general floating-point work as expensive, optimize the hotspot with:

1. cached heading sin/cos per frame
2. lookup tables
3. lower-frequency updates where visually acceptable
4. fixed-point only if measurements justify it

Do not make the initial implementation harder to reason about to solve an unmeasured problem.

## 25.6 Cache Reused Trigonometry

Even before aggressive optimization, calculate body heading sine/cosine once per simulation update and reuse them for:

- forward vector
- fork transforms
- collision corners
- carried-load transform
- wheel rendering

Likewise, calculate camera/project values once when possible.

## 25.7 Avoid General ECS Initially

The game has a modest set of entity types with very different behavior:

- forklift
- pallet/cargo
- rack/wall
- destination zone

Direct structs and arrays will be easier to understand and optimize. Introduce a more generic entity/component model only if content scale later demonstrates a real benefit.

---

# 26. Suggested Core Zig APIs

These are architectural targets, not exact required signatures.

## Input

```zig
pub fn read(pd: *PlaydateAPI) InputState;
```

## Vehicle

```zig
pub fn update(
    vehicle: *Forklift,
    input: InputState,
    tuning: VehicleTuning,
    dt: f32,
) void;
```

## Camera

```zig
pub fn update(
    camera: *Camera,
    target_pos: Vec2,
    target_velocity: Vec2,
    world_bounds: Rect,
    dt: f32,
) void;
```

## Collision

```zig
pub fn moveVehicle(
    vehicle: *Forklift,
    desired_position: Vec2,
    nearby: []const Obstacle,
) CollisionResult;
```

## Cargo Pickup

```zig
pub fn evaluateForkEntry(
    fork: ForkGeometry,
    pallet: Pallet,
    tuning: PickupTuning,
) PickupResult;
```

## Projection

```zig
pub fn project(
    world_xy: Vec2,
    z: f32,
    camera: Camera,
    tuning: ProjectionTuning,
) Vec2;
```

## Renderer

```zig
pub fn buildRenderQueue(
    game: *const Game,
    camera: Camera,
    queue: *RenderQueue,
) void;

pub fn draw(
    pd: *PlaydateAPI,
    queue: *const RenderQueue,
) void;
```

This pattern keeps `project()` and render sorting independently testable while Playdate bitmap calls stay at the edge.

---

# 27. Debug Tools Worth Building Early

A few debug tools will save much more time than they cost.

## Always Useful

- [ ] FPS
- [ ] forklift world position
- [ ] heading angle
- [ ] steering angle
- [ ] steering curvature
- [ ] speed
- [ ] camera position
- [ ] collision geometry toggle
- [ ] fork interaction geometry toggle
- [ ] pallet fork-entry zones toggle
- [ ] z/height labels
- [ ] render sort-anchor toggle
- [ ] visible/candidate object counts

## Prototype Reset Tools

- [ ] teleport forklift to test start
- [ ] reset steering to straight
- [ ] respawn pallet
- [ ] toggle carrying state for renderer testing
- [ ] cycle fork height
- [ ] cycle parallax strength presets

Debug controls do not need production UX. They need to make iteration fast.

---

# 28. Recommended Test Warehouse

Use one permanent development map for most of the project.

```text
┌────────────────────────────────────────────────────┐
│ OPEN YARD                SLALOM                    │
│                                                    │
│        o   o   o   o                               │
│                                                    │
├───────────────────────┐                            │
│ NARROW AISLE          │      LARGE LOOP            │
│ █████████████████     │                            │
│                 █     │                            │
│ █████████████   █     │                            │
│             █   █     │                            │
│             └───┘     │                            │
│                                                    │
│ FLOOR PALLET        RACK TEST       DESTINATION   │
│    [P]             [ shelf ]           [ X ]      │
│                                                    │
│ DEAD-END BAY       LONG-LOAD CORRIDOR              │
└────────────────────────────────────────────────────┘
```

It should contain:

- open steering area
- slalom
- narrow 90° aisle
- rear-swing hazard
- dead-end requiring reverse exit
- one floor pallet
- one destination
- one rack shelf
- one tall parallax test object
- one route around all sides of that object
- one corridor sized specifically for long cargo

Never throw this map away. It becomes the regression playground for handling changes.

---

# 29. Phase Gates Summary

| Gate | Smallest Testable Result | Main Question |
|---|---|---|
| T0 | Template builds on sim/device | Is toolchain stable? |
| M0 | Crank/button debug screen | Is input trustworthy? |
| M1 | Rectangle forklift drives | Is crank steering fun? |
| M2 | Scrolling graybox world | Is camera/navigation readable? |
| M3 | Rack collision | Does rear swing create useful challenge? |
| M4 | Visible simulated forks | Can player aim forks overhead? |
| M5 | One pallet pickup/drop | Is cargo interaction fluid without POV? |
| M6 | Loaded handling | Does cargo change driving decisions? |
| M7 | One complete delivery job | Is there already a game loop? |
| M8 | Z + shadows | Can height be communicated cheaply? |
| M9 | Subtle layer parallax | Does 2.5D add depth without sliding? |
| M10 | Occlusion/sorting | Can tall warehouse geometry remain readable? |
| M11 | Representative real art | Does final-style art preserve gameplay clarity? |
| M12 | Shelf pickup | Is vertical cargo play readable overhead? |
| M13 | 3 cargo types | Does cargo variety create gameplay variety? |
| M14 | 5 jobs | Does repetition stay fun? |
| M15 | Dense performance scene | Is there enough hardware headroom? |
| M16+ | Audio/save/content | Is the validated game ready to scale? |

---

# 30. Strict MVP Definition

The **first true MVP** should be much smaller than a demo release.

It is complete when all of these are true:

- [ ] game builds through the Zig Playdate template
- [ ] physical Playdate crank controls persistent steering by accumulated delta
- [ ] steering cycles continuously through a 360° periodic response
- [ ] forward and reverse driving work
- [ ] rear swing is meaningful
- [ ] large graybox world scrolls with camera follow
- [ ] racks/walls collide with forklift body
- [ ] forks are visible and simulated
- [ ] one pallet can be picked up from overhead
- [ ] one pallet can be carried and placed
- [ ] carrying changes either footprint or handling
- [ ] one destination creates a complete delivery job
- [ ] reset/retry exists
- [ ] debug visualization can explain steering, collision, and pickup failures
- [ ] this build has been tested on actual Playdate hardware

**Not required for this MVP:**

- final sprites
- Blender pipeline
- parallax
- rack height
- multiple cargo types
- sound
- scoring medals
- save data
- progression
- POV

The point of this MVP is to answer:

> **Would this still be worth making if it looked like rectangles forever?**

If yes, continue.

---

# 31. 2.5D MVP Definition

The **second MVP** validates presentation, not content.

It is complete when:

- [ ] world entities have ground anchors
- [ ] selected entities support `z` and `height`
- [ ] pallet can visibly leave ground plane
- [ ] ground shadow remains on floor
- [ ] one tall object is made from multiple visual layers
- [ ] height layers can receive subtle camera-relative parallax
- [ ] draw sorting works around one rack
- [ ] forklift can pass behind/in front of rack components convincingly
- [ ] collision remains based on ground/world geometry
- [ ] representative scene runs acceptably on hardware

Only after this passes should the art pipeline scale to many assets.

---

# 32. First Public/External Playtest Slice

Build this after the two MVPs above:

- one Training Facility stage with a small warehouse zone
- one forklift
- one floor pallet
- one shelf pallet
- one standard cargo
- one heavy cargo
- one awkward/silly cargo
- two or more short shifts with five or more total jobs
- shift timer/impact scoring and results
- basic sound
- representative 2.5D art
- title-screen Continue Main Game, boss briefings, and system-menu restart
- steering sensitivity option

Target session length: roughly 10–20 minutes.

The feedback questions should be specific:

1. Did crank steering make sense?
2. Did you ever lose track of which way the rear wheel was steering?
3. Which maneuver was most satisfying?
4. Was pickup satisfying, neutral, or annoying?
5. Could you tell when the pallet/forks were raised?
6. Did any 2.5D object look like it was sliding when the camera moved?
7. Did carrying different cargo actually change how you drove?
8. Did you want to keep playing after the five jobs?

Do not ask only "was it fun?" The implementation roadmap depends on diagnosing exactly where fun or friction comes from.

---

# 33. What Not to Build Early

Explicitly defer these until a preceding test demonstrates need:

- [ ] first-person fork camera
- [ ] runtime 3D renderer
- [ ] full ECS framework
- [ ] sophisticated rigid-body physics
- [ ] realistic tire friction model
- [ ] tipping simulation
- [ ] mast tilt
- [ ] worker AI
- [ ] procedural warehouse generation
- [ ] online leaderboard
- [ ] large narrative system
- [ ] dozens of cargo definitions
- [ ] 64-direction art before lower counts are tested
- [ ] complex save migration system
- [ ] custom editor before hand-authored data becomes painful
- [ ] micro-optimized fixed-point math before profiling

---

# 34. Immediate Next Tasks

If beginning implementation now, do these in this exact order:

## Session 1 — Toolchain + Input

- [ ] create/confirm Zig template project
- [ ] run simulator
- [ ] run hardware build
- [ ] replace sample with blank update loop
- [ ] read crank delta
- [ ] draw crank delta/steering line
- [ ] read Up/Down
- [ ] commit: `bootstrap Playdate Zig game loop`

## Session 2 — Steering Prototype

- [ ] add `Vec2` and angle helpers
- [ ] add `Forklift` state
- [ ] accumulate crank delta into persistent steer angle
- [ ] implement periodic `sin(steer_angle)` curvature
- [ ] implement acceleration/reverse/coast
- [ ] draw rectangle body + visible steering line
- [ ] add steering/speed debug values
- [ ] test on hardware
- [ ] commit: `prototype continuous crank steering`

## Session 3 — Steering Test Course

- [ ] add primitive cones
- [ ] add slalom
- [ ] add 90° corner
- [ ] add dead-end reverse bay
- [ ] test 3 steering ratios/gains
- [ ] record preferred tuning
- [ ] commit: `add forklift steering test course`

## Session 4 — World + Camera

- [ ] move to world coordinates
- [ ] add camera
- [ ] make map > screen
- [ ] follow forklift
- [ ] add look-ahead only if rigid follow is already good
- [ ] commit: `add scrolling warehouse camera`

## Session 5 — Collision

- [ ] add rectangle obstacles
- [ ] add simple forklift collision
- [ ] add collision debug outlines
- [ ] create narrow shelf aisle
- [ ] commit: `add graybox warehouse collision`

## Session 6 — Forks

- [ ] add fork geometry
- [ ] transform forks from vehicle-local to world coordinates
- [ ] render fork tines
- [ ] add target-alignment debug box
- [ ] commit: `add simulated forklift forks`

## Session 7 — Pallet

- [ ] add one pallet
- [ ] add fork-entry zones
- [ ] calculate alignment/insertion
- [ ] A attaches, B detaches
- [ ] carry pallet with vehicle
- [ ] perform 20-pickup repetition test
- [ ] commit: `add overhead pallet pickup and placement`

## Session 8 — First Job

- [ ] add destination zone
- [ ] validate drop
- [ ] job complete message
- [ ] timer/retry
- [ ] hardware playtest full loop
- [ ] tag repository: `mvp-flat-graybox`

Only then begin the 2.5D renderer milestones.

---

# 35. Reference Notes

Current toolchain/reference sources checked while preparing this guide:

- DanB91, **Zig-Playdate-Template**: https://github.com/DanB91/Zig-Playdate-Template
- Panic, **Useful Links for Playdate Development**: https://help.play.date/developer/dev-links/
- Panic, **Inside Playdate / SDK documentation**: https://sdk.play.date/

Relevant Playdate C API concepts for this plan include:

- `playdate->system->getCrankChange()` for per-update crank delta
- `playdate->system->getButtonState()` for buttons
- `playdate->system->setUpdateCallback()` for the game loop
- `playdate->system->drawFPS()` for quick profiling feedback
- `playdate->graphics->setDrawOffset()` as an available scrolling-world mechanism

The project should use the exact function/field spellings exposed by the version of `src/playdate_api_definitions.zig` pinned in the chosen Zig template commit; do not assume Lua API names are identical to the C/Zig bindings.

---

# 36. Definition of Success for the Implementation Strategy

This roadmap is working correctly if the project repeatedly produces **small builds that answer one question**:

```text
Does crank input work?
        ↓
Is steering fun?
        ↓
Is navigating a large warehouse fun?
        ↓
Does rear swing matter?
        ↓
Can forks be aimed overhead?
        ↓
Is pickup fluid?
        ↓
Does carrying change driving?
        ↓
Is there a complete job loop?
        ↓
Does height read clearly?
        ↓
Does 2.5D improve the game?
        ↓
Can real art preserve clarity?
        ↓
Can a handful of jobs stay fun?
        ↓
Scale content
```

At no point should months of implementation be required before the next major design assumption can be tested.

> **Primary implementation rule:** build the smallest version that lets you play the new feature, test it on hardware, keep it only if it improves the game, and then move to the next risk.
