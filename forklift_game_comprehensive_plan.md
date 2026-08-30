# Project Forklift

*Comprehensive Game Design & Implementation Plan*

> **CORE CONCEPT**
> A Playdate-native top-down forklift game built around continuous 360-degree crank steering, rear-wheel maneuvering, precision cargo handling, and a height-aware 2.5D sprite renderer. The game should make the crank feel like a physical steering mechanism rather than an alternate analog stick.

**Document status:** Working design plan - intended to guide prototyping, implementation, art production, and scope decisions.

**Primary platform:** Panic Playdate (400 x 240, 1-bit display, crank input)

**Rendering direction:** Top-down 2.5D, height-aware layered sprites with subtle parallax and shadows

**Deferred feature:** First-person fork POV / precision camera unless playtesting proves it necessary

**Version:** 0.1 - concept consolidation

# 1. Executive Summary

Project Forklift is a compact precision-driving and spatial-puzzle game for Playdate. Its defining interaction is a cumulative crank-controlled steering mechanism inspired by real lift trucks whose steer wheel can rotate continuously through 360 degrees. The crank turns the steering system itself; it does not merely represent a centered left/right steering input.

The main game takes place entirely in a scrolling top-down warehouse or industrial environment larger than the Playdate display. The presentation uses a height-aware 2.5D sprite renderer: gameplay and collision remain primarily 2D, while objects carry height metadata, layered art, shadows, occlusion rules, and subtle camera-relative parallax to create a convincing sense of volume.

The development strategy is deliberately proof-first. The project should establish the steering feel, rear-wheel swing, camera, collision, and readable pallet pickup before investing in polished content. The initial game must be fully playable without a first-person view. A zoom or POV system remains a possible later enhancement rather than a foundational dependency.

## 1.1 Product Pillars

Crank-native control: the crank behaves like a real physical steering wheel with persistent rotational state.

Skill through maneuvering: tight navigation, rear swing, reversing, load handling, and route planning are the primary sources of mastery.

Readable 2.5D: strong dimensional presentation without the complexity or performance cost of a full real-time 3D game.

Fast cargo interaction: routine pickups should become fluid actions, not repetitive minigames or mode changes.

Expressive cargo: ordinary logistics can escalate into humorous and mechanically distinctive loads without requiring a bespoke engine per item.

Small-system depth: the game should derive variety from combinations of steering, space, load properties, warehouse layout, and job constraints rather than feature bloat.

## 1.2 Non-Goals for the First Playable

Full forklift simulator realism.

Mandatory first-person fork alignment.

General-purpose 3D engine or polygonal warehouse rendering.

Complex hydraulic simulation, continuous mast tilt, or realistic OSHA procedure modeling.

Large narrative campaign before the core driving loop is proven.

Dozens of forklift classes before one vehicle feels excellent.

## 1.3 Core Design Rule

> **DESIGN RULE**
> The crank turns the wheel. It does not tell the forklift which way to turn.

# 2. Document Map

| **Section** | **Purpose**                             |
|-------------|-----------------------------------------|
| 3           | Core Gameplay Loop and Controls         |
| 4           | Forklift Steering and Vehicle Model     |
| 5           | Camera and World Navigation             |
| 6           | 2.5D Height-Aware Rendering System      |
| 7           | Art and Asset Production Pipeline       |
| 8           | Cargo, Pallets, and Fork Handling       |
| 9           | Warehouse World and Level Structure     |
| 10          | Jobs, Progression, Scoring, and Variety |
| 11          | UX, Feedback, Audio, and Accessibility  |
| 12          | Technical Architecture                  |
| 13          | Performance and Memory Strategy         |
| 14          | Development Roadmap                     |
| 15          | Testing and Tuning Plan                 |
| 16          | Risks and Mitigations                   |
| 17          | Deferred / Optional Features            |
| 18          | Open Questions and Decision Log         |
| Appendix A  | Suggested Data Model                    |
| Appendix B  | MVP Acceptance Checklist                |

# 3. Core Gameplay Loop and Controls

## 3.1 Core Loop

Receive or select a job.

Identify pickup and destination.

Plan or discover a viable route through the warehouse.

Drive and maneuver into pickup position.

Insert forks and lift the load without a separate minigame.

Navigate while the vehicle footprint and handling are changed by the load.

Position and place the cargo at the destination.

Receive score/feedback and continue to the next job.

The pickup itself should remain a relatively small part of the loop. The richest play is expected to come from maneuvering into position and then navigating with a load that changes what routes and steering choices are safe.

## 3.2 Proposed Initial Controls

| **Input**        | **Initial Action**              | **Design Notes**                                                                 |
|------------------|---------------------------------|----------------------------------------------------------------------------------|
| Crank            | Rotate steer wheel cumulatively | Persistent state; no automatic centering.                                        |
| D-pad Up         | Drive forward                   | Analog-like speed can be simulated with acceleration/ramp despite digital input. |
| D-pad Down       | Reverse                         | Reverse should be a normal, frequently used maneuver.                            |
| A                | Raise forks / lift              | Context may determine whether cargo becomes attached.                            |
| B                | Lower forks / drop              | Must not require a camera or mode switch.                                        |
| D-pad Left/Right | Reserved initially              | Possible horn, job UI, mast action, or camera function later.                    |
| Menu             | Pause / job / settings          | Keep non-driving UI off the core controls.                                       |

## 3.3 Input Philosophy

Driving should remain possible with left thumb on D-pad and right hand on crank.

Fork actions should be infrequent enough that temporarily leaving the crank is acceptable.

Avoid chords or frequent button combinations in the MVP.

Do not automatically straighten steering when the player stops cranking.

Provide immediate visual feedback for steering angle so players never have to infer persistent wheel state from crank position.

# 4. Forklift Steering and Vehicle Model

## 4.1 Steering State

The forklift maintains an independent steer-wheel angle. Each frame, crank delta changes that angle by a configurable gear ratio. The angle wraps continuously rather than clamping to a left/right steering range.

> **CONCEPTUAL UPDATE**
> steerAngle = wrap(steerAngle + crankDelta x steeringRatio)

The steering ratio should be a tuning parameter. Prototype at least 1.0, 1.5, and 2.0 crank revolutions per steer-wheel revolution. A ratio above 1:1 may create the satisfying physical sensation of spinning a steering wheel while preserving fine control.

## 4.2 Rear-Wheel Kinematics

The vehicle should pivot according to a rear-steer bicycle model or a simplified equivalent. The exact tire simulation is less important than producing believable rear swing and predictable maneuvering. The front of the forklift carries the forks and load; the rear steer axle causes the counterweight to swing outward during turns.

Use a configurable wheelbase between front axle and rear steer axle.

Calculate angular velocity from current linear velocity and rear steer angle.

Reverse naturally inverts the apparent response, creating useful forklift-specific maneuvering skill.

Clamp acceleration, braking, and top speed independently for forward and reverse if needed.

Test at low speed first; warehouse gameplay should reward precision more than speed.

## 4.3 Vehicle State

| **Property**           | **Purpose**                                               |
|------------------------|-----------------------------------------------------------|
| position (x, y)        | World-space location of vehicle reference point.          |
| heading                | Body orientation in world space.                          |
| steerAngle             | Persistent steer-wheel orientation driven by crank delta. |
| velocity               | Signed forward/reverse speed.                             |
| acceleration / braking | Tuning controls for responsiveness.                       |
| wheelbase              | Determines turning geometry.                              |
| body footprint         | Collision shape for chassis/counterweight.                |
| fork footprint         | Separate forward collision/interaction geometry.          |
| forkHeight             | Height-aware interaction/render state.                    |
| carriedLoad            | Optional reference to currently supported pallet/cargo.   |
| load modifiers         | Mass, size, stability, visibility, and handling effects.  |

## 4.4 Handling with Cargo

Heavy loads can reduce acceleration and braking responsiveness.

Long loads increase effective front footprint and route-planning difficulty.

Tall loads can affect visibility cues and clearance constraints.

Fragile or unstable loads can punish abrupt turns or impacts without requiring full rigid-body simulation.

Handling changes should be readable and consistent rather than numerically realistic.

# 5. Camera and World Navigation

## 5.1 World vs. Screen Coordinates

The warehouse exists in world coordinates and may be many times larger than the 400 x 240 display. Rendering converts world positions into screen positions relative to a camera. Only visible or near-visible objects need to be submitted for drawing.

> **BASIC TRANSFORM**
> screenX = worldX - cameraX; screenY = worldY - cameraY

## 5.2 Camera Follow

Do not rigidly pin the forklift to exact screen center.

Use a smoothly damped target position to avoid jitter and abrupt camera corrections.

Bias the camera modestly in the current direction of travel so the player sees more of the route ahead.

Transition look-ahead gradually when switching from forward to reverse.

Clamp the camera to map bounds or intentionally expose off-map margins only where visually acceptable.

## 5.3 Precision Camera Option

The MVP should not depend on POV. If top-down fork alignment proves difficult, the first enhancement to test should be a top-down precision zoom or reduced look-ahead at very low speed. This reuses the same renderer and art pipeline and is much cheaper than building a second camera paradigm.

# 6. 2.5D Height-Aware Rendering System

## 6.1 Rendering Goal

The renderer should make the warehouse feel volumetric while keeping simulation and most collision logic in 2D. Each relevant object has a ground position/footprint plus a height or layer structure. The renderer uses those values to produce visual extrusion, parallax, shadows, occlusion, and elevation cues.

## 6.2 Object Representation

| **Field**       | **Meaning**                                                   |
|-----------------|---------------------------------------------------------------|
| x, y            | Ground anchor in world space.                                 |
| footprint       | 2D collision/placement shape at ground level.                 |
| z               | Elevation above floor, usually 0 except lifted/stored cargo.  |
| height          | Visual/clearance height.                                      |
| render layers   | Optional base/body/top/front/overlay components.              |
| shadow profile  | Ground shadow sprite or shape.                                |
| sort anchor     | Ground-space Y point used for normal draw ordering.           |
| occlusion class | Rules for objects that need split-front/split-back rendering. |

## 6.3 Three Combined Depth Effects

Pre-rendered perspective: sprites show top and side faces from a fixed high-angle view.

Height displacement/parallax: higher visual components shift subtly relative to the ground anchor as the camera moves.

Ground shadows: shadows remain attached to the floor plane, visually separating elevated parts from their footprints.

The effect should be subtle. The world must feel stable; tall objects should not appear to slide dramatically as the camera pans.

## 6.4 Projection Strategy

Use a lightweight projection function rather than a general 3D transform. The exact formula can evolve, but the API should conceptually accept x, y, and z so later systems can raise pallets, place cargo on racks, and support clearance rules without rewriting the renderer.

> **RENDERER API TARGET**
> project(worldX, worldY, worldZ, camera) -> screenX, screenY

## 6.5 Layered Sprites and Sprite Stacking

Objects may be drawn as a few coarse layers rather than dozens of one-pixel slices. A typical rack can use base, body, top, and foreground-post layers. A forklift can use shadow/wheels, body, mast/forks, and overhead-guard layers. This produces depth while keeping draw calls predictable.

| **Object**      | **Suggested Layers**                                                        |
|-----------------|-----------------------------------------------------------------------------|
| Forklift        | shadow/wheels; chassis/body; mast/forks; guard/upper details; carried cargo |
| Rack            | rear/base; stored pallets; body; front posts; top cap                       |
| Pallet          | shadow; pallet base; cargo body; cargo top/overlay                          |
| Crate / machine | shadow; base/body; top highlight or cap                                     |
| Tall wall       | floor contact; wall face; top edge; foreground cap if needed                |

## 6.6 Draw Ordering and Occlusion

Base draw order should derive from each object's ground/sort anchor, usually bottom Y in screen/world projection.

Tall structures may be split into back and front components so the forklift can visually pass behind foreground posts while remaining in front of the structure base.

Carried cargo should sort as part of the forklift assembly while still maintaining its own z/height cues.

Avoid relying on one giant flattened warehouse bitmap; use spatial chunks and independently sortable objects.

## 6.7 Height Cues for Forks and Cargo

Raised forks move in projected z and separate from their ground shadow.

A lifted pallet follows fork z and gains a visible gap/shadow separation.

Rack shelves use known z levels so visual placement and gameplay placement agree.

Discrete height states are acceptable for MVP even if internal representation remains numeric.

# 7. Art and Asset Production Pipeline

## 7.1 Recommended Source Pipeline

Use Blender as an asset-authoring and consistency tool even though the runtime is 2D. Models can be rendered from a fixed orthographic/high-angle camera, converted to 1-bit, and manually cleaned where necessary. The goal is not photorealism; it is consistent perspective, proportions, and efficient production of many directional frames.

> **PIPELINE**
> Blender source -> fixed camera render -> 1-bit conversion -> pixel cleanup -> sprite tables / layered assets -> Playdate runtime

## 7.2 Forklift Directional Art

Prototype with 16 or 32 body directions; move to 64 only if rotation stepping is visually distracting.

Render the steer wheel/tire separately from the body so its orientation is always readable and does not multiply the body-frame count.

Keep mast/forks separable if fork elevation or load interaction requires visible changes.

Prioritize silhouette and steering readability over small mechanical detail.

## 7.3 1-Bit Art Rules

Use bold silhouettes and controlled interior texture.

Avoid dense photographic dithering that shimmers during scrolling.

Use a limited set of intentional dither patterns for material/shadow differences.

Preserve strong contrast around fork pockets, rack edges, and collision-critical shapes.

Let decorative detail live on surfaces that do not compete with gameplay readability.

## 7.4 Cargo Art Strategy

Cargo can be visually extravagant without being structurally complex. Each item should have a simple gameplay footprint, height, weight, and optional special rules; the visual representation may be pre-rendered, hand-drawn, layered, or animated independently.

| **Cargo Class**                   | **Visual Complexity**                   | **Gameplay Proxy**                    |
|-----------------------------------|-----------------------------------------|---------------------------------------|
| Boxes / drums / appliances        | Simple 2.5D sprite layers               | Box footprint + height + mass         |
| Long pipe / lumber / steel        | Long directional sprite                 | Oriented long rectangle + stability   |
| Giant rubber duck / cake / oddity | Distinct silhouette, optional animation | Simple footprint + height + mass      |
| Animals / animated gag loads      | Few-frame animation                     | Proxy shape + movement/stability flag |
| Fragile machinery / aquarium      | Detailed visual, strong shadow          | Proxy + fragile/jolt thresholds       |

# 8. Cargo, Pallets, and Fork Handling

## 8.1 Pickup Philosophy

Routine pickup must be fast enough that skilled players can approach, insert, lift, and leave in one continuous sequence. Do not require entering a dedicated alignment mode. The forklift forks should be actual interaction geometry visible in the normal view.

## 8.2 Pickup Conditions

A pallet can become supported when the fork geometry overlaps its fork-entry region sufficiently, the relative heading is within an allowed tolerance, the forks are at an acceptable height, and penetration is deep enough. Tolerances should be forgiving at first and can tighten for special jobs.

| **Check**          | **Purpose**                                    |
|--------------------|------------------------------------------------|
| Horizontal overlap | Both fork tines occupy acceptable entry lanes. |
| Relative angle     | Prevents obviously sideways pickup.            |
| Fork height        | Matches floor/rack opening height.             |
| Insertion depth    | Prevents lifting by touching only pallet edge. |
| Load clearance     | Optional for rack/overhead constraints.        |
| Stability / center | Optional for special heavy or awkward cargo.   |

## 8.3 Fork Height

Start with discrete or semi-discrete useful states rather than simulation-grade hydraulics. Example: Ground, Carry, Rack Low, Rack High. Internally the value may be numeric so future interpolation and visuals remain possible.

## 8.4 Placement

Dropping onto floor should be forgiving and fast.

Placing into marked bays can score based on position and heading precision.

Rack placement checks support surface height and overlap rather than requiring exact physics.

Cargo should visibly detach from forks and settle to its target z/height state.

# 9. Warehouse World and Level Structure

## 9.1 Spatial Design Goals

Create spaces where rear swing matters.

Use aisle width, dead ends, rack ends, posts, and staging areas to create maneuvering puzzles.

Provide multiple routes when loads differ in size/height.

Let the same geometry feel different when driving empty versus loaded.

Keep visual landmarks strong so a scrolling world remains navigable on a small display.

## 9.2 World Composition

| **System**       | **Recommendation**                                                     |
|------------------|------------------------------------------------------------------------|
| Floor            | Chunked tile/bitmap regions with markings, stains, arrows, and zones.  |
| Racks            | Independent 2.5D objects with collision footprints and shelf z-levels. |
| Walls            | Chunked or segmented layered sprites; top caps may occlude vehicle.    |
| Posts / bollards | Small high-contrast collision obstacles.                               |
| Pallets / cargo  | Dynamic entities; sortable and potentially movable.                    |
| Doors / trailers | Special destination spaces and clearance constraints.                  |
| Decor            | Non-colliding signs, lights, floor marks, debris, workers, etc.        |

## 9.3 Spatial Partitioning

Divide large maps into chunks or a lightweight spatial index so rendering and collision checks only consider nearby objects. A uniform grid is likely sufficient and easy to debug. Keep map data independent of the sprite artwork so level editing does not require re-authoring a giant image.

## 9.4 Level Progression Example

| **Stage**            | **Primary Lesson / Twist**                                                       |
|----------------------|----------------------------------------------------------------------------------|
| Training Yard        | Crank steering, forward/reverse, cones, rear swing.                              |
| Certification        | First pallet pickup and marked drop zone.                                        |
| Warehouse A          | Tight aisles and rack ends.                                                      |
| Loading Dock         | Trailer entry, long reverse lines, dock obstacles.                               |
| High Storage         | Multiple rack heights and clearance awareness.                                   |
| Fragile Shift        | Cargo damage constraints; smooth driving matters.                                |
| Oversize             | Long/wide cargo changes route choice.                                            |
| Rush Shift           | Several jobs, route optimization, score pressure.                                |
| Night / Power Issue  | Visual theme variation and selective visibility challenge, if readable in 1-bit. |
| Master Certification | Compact gymkhana combining steering precision, pickup, and placement.            |

# 10. Jobs, Progression, Scoring, and Variety

## 10.1 Job Types

Move one pallet from A to B.

Load a sequence of pallets into a trailer.

Unload and stage incoming cargo.

Reorganize blocked stock to reach a target load.

Deliver multiple loads in an efficient order.

Handle fragile cargo under impact/jolt limits.

Move oversized cargo through a restricted route.

Recover misplaced pallets under a time or damage target.

Certification / cone course with no cargo.

## 10.2 Puzzle Layer

Some jobs should function like light Sokoban problems without becoming grid-based. A pallet may block a necessary aisle, a temporary staging area may be needed, or the order of moves may matter. The player solves the spatial problem while physically executing each maneuver.

## 10.3 Scoring

| **Metric**                   | **Why It Matters**                               |
|------------------------------|--------------------------------------------------|
| Completion time              | Rewards efficient routing and confident driving. |
| Cargo damage                 | Rewards smooth, accurate handling.               |
| Rack / obstacle impacts      | Makes rear swing and spatial awareness matter.   |
| Placement precision          | Adds mastery without requiring pickup minigames. |
| Unnecessary moves / distance | Optional puzzle-efficiency metric.               |
| Safety / clean shift bonus   | Rewards zero-collision runs.                     |
| Difficulty modifier          | Supports special cargo/job constraints.          |

## 10.4 Progression Philosophy

Prefer player skill progression over numerical upgrade trees. Unlock new warehouses, cargo classes, job types, or forklift variants only when they introduce meaningful handling differences. Avoid upgrades that erase the steering challenge.

# 11. UX, Feedback, Audio, and Accessibility

## 11.1 Critical Visual Feedback

Clearly visible rear steer-wheel orientation.

Readable fork tips and pallet entry regions.

Ground shadows that show whether forks/cargo are elevated.

Strong collision silhouettes on racks and posts.

Subtle impact flash/shake without obscuring control.

Job destination zones recognizable at a glance.

Optional minimal steering indicator if the physical tire sprite is insufficient.

## 11.2 Audio

Motor/drive hum that changes with speed and load.

Mechanical steering/chain/tire ticks tied subtly to crank movement.

Hydraulic lift/lower sound.

Distinct pallet engagement "clunk".

Rack/metal impacts versus soft cargo impacts.

Reverse warning beep as an optional authenticity/comedy element.

Short completion stingers rather than constant music if ambience suits the game better.

## 11.3 Accessibility and Comfort

Crank sensitivity / steering ratio presets.

Optional steering-angle HUD.

Camera smoothing strength or reduced camera motion.

High-contrast interaction markings.

Generous pickup tolerances in easier modes.

Optional reduced penalties for collision/damage.

# 12. Technical Architecture

## 12.1 Separation of Concerns

| **Module / Layer**      | **Responsibility**                                                  |
|-------------------------|---------------------------------------------------------------------|
| Game State              | Entities, jobs, scores, progression, simulation state.              |
| Input                   | Crank delta, buttons, action mapping, sensitivity.                  |
| Vehicle Simulation      | Steering, motion, chassis/fork transforms, load modifiers.          |
| Collision / Interaction | World footprints, fork overlap, pallet support, placement.          |
| Camera                  | Follow target, look-ahead, bounds, optional precision zoom.         |
| 2.5D Renderer           | Projection, sorting, layer composition, shadows, parallax, culling. |
| World / Level           | Map chunks, racks, obstacles, zones, spawn points.                  |
| Asset System            | Directional sprite tables, layered sprites, metadata.               |
| Job System              | Objectives, rules, timers, scoring.                                 |
| UI / Audio              | HUD, menus, feedback, sound events.                                 |

## 12.2 Fixed-Step Simulation

Prefer a deterministic or semi-fixed simulation step for vehicle motion and collision so handling does not change with rendering load. Rendering can interpolate if necessary, but the MVP may simply update and draw at the same cadence if performance is stable.

## 12.3 Collision Strategy

Use simple oriented rectangles/circles/polygons rather than pixel-perfect collision.

Maintain separate chassis, rear/counterweight, fork, and cargo interaction regions where useful.

Use broad-phase spatial grid lookup before narrow-phase checks.

Do not derive collision from parallax-displaced artwork; collision stays on the ground/world model.

## 12.4 Data-Driven Content

Warehouses, cargo, job definitions, rack shelf heights, and tuning values should be declarative where practical. This makes iteration faster and allows art and design content to grow without editing core simulation code.

# 13. Performance and Memory Strategy

## 13.1 Performance Priorities

Keep the normal driving renderer entirely sprite-based.

Cull off-screen objects before sorting/drawing.

Use coarse spatial chunks for collision and rendering queries.

Limit layer counts for large repeated structures.

Prefer pre-generated directional frames to expensive arbitrary runtime rotation when appearance matters.

Avoid excessive full-screen dither animation that can shimmer and increase draw cost.

Profile on hardware early; simulator smoothness is not sufficient evidence.

## 13.2 Asset Budget Approach

Do not decide 16/32/64 directional frames globally. Measure memory and visual quality per asset class. The forklift deserves more directional fidelity than small symmetric props. Repeated warehouse assets should reuse sprite data aggressively.

## 13.3 Optimization Order

Correctness and steering feel.

Visibility culling and spatial partitioning.

Reduce unnecessary draw layers.

Reduce directional frame counts where visually acceptable.

Chunk/static-cache floor and non-interactive scenery.

Micro-optimize math or move hotspots to lower-level code only after profiling.

# 14. Development Roadmap

## Phase 0 - Paper / Math Prototype

Define vehicle reference points and wheelbase.

Implement cumulative crank-to-steer-angle logic.

Verify rear-steer equations with simple debug drawing.

Choose initial steering ratio and speed envelope.

Exit criterion: a rectangle with a visible steer wheel can be driven naturally with the crank and exhibits convincing rear swing.

## Phase 1 - Graybox Driving

Large scrolling world larger than the screen.

Camera follow and look-ahead.

Walls/racks as rectangles.

Chassis collision and reset behavior.

Basic timer / debug metrics.

Exit criterion: driving through a simple warehouse is fun for several minutes even with placeholder art.

## Phase 2 - Forks and Pallet Handling

Visible forks and interaction geometry.

Pallet entry zones.

Raise/lower states.

Attach, carry, place, detach.

Basic carried-load handling modifiers.

Exit criterion: routine pallet pickup is readable and fluid from overhead without a POV system.

## Phase 3 - 2.5D Renderer Prototype

Introduce z/height metadata.

Ground shadows.

Layered rack/forklift objects.

Camera-relative height displacement/parallax.

Y-sort and split foreground/background occlusion.

Test lifted pallet visuals.

Exit criterion: the warehouse feels dimensional while collision remains understandable and the renderer stays comfortably within frame budget on hardware.

## Phase 4 - Art Pipeline

Create fixed Blender camera/lighting template.

Automate directional renders.

Establish 1-bit conversion and cleanup rules.

Produce forklift, pallet, one rack set, one wall set, and 3-5 cargo types.

Validate directional frame counts and memory use.

Exit criterion: a representative warehouse scene matches the intended final visual style.

## Phase 5 - Vertical Slice

One polished warehouse zone.

5-8 jobs.

Basic scoring.

Cargo variety including at least one awkward/novel load.

Sound and HUD.

Restart/pause/save basics.

Exit criterion: a small audience can play a coherent 15-30 minute slice and identify the crank steering as the game's defining appeal.

## Phase 6 - Content and Progression

Expand job templates and map layouts.

Add rack heights / clearance where useful.

Add cargo modifiers and humorous loads.

Add score targets / medals / leaderboards if desired.

Introduce additional forklift only if it changes play materially.

## Phase 7 - Polish and Release

Hardware performance pass.

Input/sensitivity presets.

Tutorial and onboarding.

Content pacing.

Audio polish.

Save-data robustness.

Edge-case collision and soft-lock audit.

Store assets / screenshots / trailer.

# 15. Testing and Tuning Plan

## 15.1 Steering Tests

| **Test**         | **Question**                                                                        |
|------------------|-------------------------------------------------------------------------------------|
| Straight aisle   | Can the player hold a line without constant correction?                             |
| 90-degree corner | Does rear swing feel intuitive and teachable?                                       |
| Reverse into bay | Does steering remain predictable while reversing?                                   |
| Cone slalom      | Is crank gearing fast enough without becoming twitchy?                              |
| Full steer loop  | Does continuous 360-degree behavior remain understandable after multiple rotations? |
| Stop/restart     | Does persistent steer state feel intentional rather than broken?                    |

## 15.2 Camera / 2.5D Tests

Drive along and around tall racks: does parallax add depth without apparent sliding?

Pass behind foreground posts: is occlusion correct and readable?

Lift and lower a pallet: can players tell when it is off the ground?

Reverse quickly: does look-ahead transition avoid camera whiplash?

Dense scene: does 1-bit dithering remain stable while scrolling?

Small cargo/fork alignment: are interaction-critical edges obvious on real hardware?

## 15.3 Pickup Repetition Test

Because pickup repetition is a known design risk, explicitly test sessions containing 20-30 pallet interactions. If players describe pickup as ceremony, friction, or waiting, simplify tolerances and interaction steps before adding a new camera. Add zoom/POV only if the problem is fundamentally visual rather than procedural.

# 16. Risks and Mitigations

| **Risk**                                     | **Mitigation**                                                                                                         |
|----------------------------------------------|------------------------------------------------------------------------------------------------------------------------|
| Steering is novel but confusing              | Strong steer-wheel visualization, short tutorial, sensitivity presets, early playtesting.                              |
| Steering is realistic but not fun            | Tune wheelbase, ratio, speed, and rear swing for playability rather than simulation fidelity.                          |
| Pickup becomes repetitive                    | Keep routine pickup continuous; vary approach, route, cargo handling, and placement rather than adding minigame steps. |
| 2.5D parallax makes world unstable           | Use very small offsets; anchor shadows/footprints firmly; test on moving camera early.                                 |
| Occlusion hides important information        | Split tall assets, use selective outlines, reduce top-face size where necessary.                                       |
| Pre-rendered sprites consume too much memory | Use fewer directions on small props; separate reusable components; measure before committing to 64 frames.             |
| 1-bit dithering flickers while scrolling     | Use restrained patterns, larger clean regions, and hand-tuned sprite cleanup.                                          |
| Large warehouse becomes expensive            | Chunk maps, cull aggressively, reuse static art, broad-phase spatial grid.                                             |
| Fork height is unreadable overhead           | Improve shadows/z displacement first; then test top-down precision zoom before considering POV.                        |
| Scope grows into simulator                   | Protect core pillars and phase gates; every new system must improve steering/navigation/cargo variety directly.        |

# 17. Deferred / Optional Features

These ideas remain compatible with the architecture but should not be treated as MVP requirements.

First-person fork POV / "aim down forks" camera.

Automatic or manual top-down precision zoom.

Mast tilt and more detailed hydraulic controls.

Multiple forklift classes: reach truck, order picker, telehandler, pallet jack.

Dynamic workers / pedestrians.

Co-op or asynchronous score challenges.

Procedural job generation or endless shift mode.

Weather/outdoor yard areas.

Advanced load stability / tipping.

Narrative characters, supervisor radio, workplace comedy.

Daily challenge / global leaderboard systems.

# 18. Open Questions and Decision Log

## 18.1 Decisions Already Made

| **Topic**         | **Decision**                                                                                            |
|-------------------|---------------------------------------------------------------------------------------------------------|
| View              | Primary gameplay is overhead/top-down.                                                                  |
| World size        | Scrollable environment larger than 400 x 240 with camera follow.                                        |
| Signature control | Cumulative continuous crank steering representing physical steer-wheel rotation.                        |
| Rendering         | 2.5D height-aware sprite renderer, not full runtime 3D.                                                 |
| Art direction     | Likely Blender-authored/pre-rendered directional sprites plus hand-cleaned 1-bit assets.                |
| POV               | Not required; deferred unless overhead play proves insufficient.                                        |
| Pickup            | Must be playable directly in the main view and should not become a repetitive minigame.                 |
| Cargo             | Can include silly/unusual items and should use simple gameplay proxies separate from visual complexity. |

## 18.2 Questions for Prototype Testing

What crank-to-steer ratio feels best on actual hardware?

Should steer wheel make one 360-degree turn or use a gearing abstraction relative to the visible rear tire?

What top speed preserves tension without making precision annoying?

How much rear swing should be exaggerated for gameplay readability?

How many forklift body directions are visually sufficient: 16, 32, or 64?

How strong can 2.5D parallax be before it looks like sliding?

How many render layers per rack/forklift are affordable and useful?

Can fork height be communicated entirely with shadows/layering?

What pickup tolerance feels skilled but not fussy?

Does a discrete fork-height system feel sufficient?

Are jobs more compelling as authored levels, freeform shifts, or a mixture?

How much scoring pressure fits the intended relaxed/arcade tone?

Should the first release emphasize realistic warehouse work, absurd cargo comedy, or a balanced progression from one into the other?

# Appendix A - Suggested Data Model

## A.1 Forklift

| **Field**       | **Example Meaning**                        |
|-----------------|--------------------------------------------|
| position        | (x, y) world coordinate                    |
| heading         | body angle                                 |
| steerAngle      | persistent crank-driven steering state     |
| velocity        | signed forward/reverse speed               |
| wheelbase       | turning geometry                           |
| bodyShape       | collision proxy                            |
| forkShape       | interaction geometry                       |
| forkHeight      | z/elevation                                |
| carriedLoadId   | optional pallet/cargo                      |
| handlingProfile | accel, brake, max speed, steering response |

## A.2 Pallet / Cargo

| **Field**          | **Example Meaning**                  |
|--------------------|--------------------------------------|
| position / heading | world transform                      |
| z / supportHeight  | floor, fork, or rack shelf elevation |
| footprint          | 2D physical proxy                    |
| height             | visual and clearance height          |
| forkEntryZones     | accepted tine regions                |
| massClass          | handling modifier                    |
| fragility          | impact/jolt tolerance                |
| stability          | turn/brake sensitivity               |
| visualAsset        | sprite/layer set                     |
| specialFlags       | oversize, animated, live cargo, etc. |

## A.3 Renderable Object

| **Field**      | **Example Meaning**                          |
|----------------|----------------------------------------------|
| groundAnchor   | x/y attachment to world plane                |
| z              | elevation                                    |
| height         | visual extrusion / parallax amount           |
| layers         | ordered sprite components                    |
| shadow         | ground-plane cue                             |
| sortAnchor     | normal ordering key                          |
| occlusionMode  | simple, split-front/back, overhead-cap, etc. |
| directionIndex | selected sprite frame from heading           |

## A.4 Job

| **Field**              | **Example Meaning**              |
|------------------------|----------------------------------|
| pickupIds / sourceZone | cargo to acquire                 |
| destinationZone        | required delivery region         |
| constraints            | time, damage, route, cargo order |
| scoreWeights           | time, impacts, precision, safety |
| completionRules        | conditions for success           |
| failureRules           | optional hard failure conditions |

# Appendix B - MVP Acceptance Checklist

- [ ] Crank rotation continuously changes a persistent steering state.

- [ ] Visible steering wheel/tire orientation always matches simulation.

- [ ] Forklift forward/reverse and rear swing feel predictable on hardware.

- [ ] Camera scrolls a map substantially larger than the screen without distracting jitter.

- [ ] Player can navigate tight aisles using only the overhead view.

- [ ] Player can pick up and place a pallet without entering another mode.

- [ ] Carried pallet changes visual state and at least one handling property.

- [ ] Collision with racks/posts is clear and recoverable.

- [ ] Height-aware renderer supports floor, elevated forks, lifted cargo, and at least one rack shelf level.

- [ ] Shadows/parallax make tall objects feel dimensional without causing visible sliding.

- [ ] Forklift correctly sorts in front of and behind layered warehouse structures.

- [ ] Representative scene maintains acceptable frame rate on physical Playdate hardware.

- [ ] At least one short job sequence is fun with placeholder or near-final art.

- [ ] After 20+ repeated pickups, pickup interaction is not the dominant source of friction.

- [ ] No POV feature is required to understand or complete the core loop.

# Appendix C - Recommended First Prototype Map

Build one compact test environment before creating a production warehouse. It should include:

A large open area for steering feel.

A cone slalom.

A 90-degree narrow aisle turn with rear-swing risk.

A dead-end bay requiring reverse exit.

One floor pallet and one destination zone.

One rack with foreground posts for occlusion testing.

One shelf-height pallet for z/height testing.

One long-load corridor to test changed footprint.

A loop route that lets the camera cross the same objects from multiple directions.

> **PROTOTYPE SUCCESS QUESTION**
> Is it intrinsically enjoyable to drive the forklift around this graybox for five minutes before adding progression, comedy, or polished art? If not, tune steering and camera before building more systems.

**End of plan** - This document should be updated as prototype tests resolve the open questions. Preserve the design pillars, but treat numeric values, control mappings, art frame counts, and job structures as tunable until validated on hardware.
