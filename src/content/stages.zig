const static_level = @import("static_level.zig");
const training_facility = @import("training_facility.zig");
const first_warehouse = @import("first_warehouse.zig");
const conveyor_warehouse = @import("conveyor_warehouse.zig");
const feature_test = @import("feature_test.zig");
const stress_test = @import("stress_test.zig");
const campaign = @import("../game/campaign.zig");
const cargo = @import("../sim/cargo.zig");
const conveyor = @import("../sim/conveyor.zig");
const math2 = @import("../sim/math2.zig");
const vehicle = @import("../sim/vehicle.zig");
const render = @import("../render/renderer.zig");
const compositor = @import("../render/compositor.zig");
const config = @import("../config.zig");

const production_stages = [_]campaign.StageDefinition{
    conveyor_warehouse.stage,
    training_facility.stage,
    first_warehouse.stage,
};
const stress_stages = [_]campaign.StageDefinition{stress_test.stage};
const feature_test_stages = [_]campaign.StageDefinition{feature_test.stage};

const campaign_complete_pages = [_][]const u8{
    "All shifts complete.",
    "Excellent work, operator.",
};

pub const active_campaign = campaign.CampaignDefinition{
    .stages = if (config.use_feature_test_stage)
        &feature_test_stages
    else if (config.use_stress_stage)
        &stress_stages
    else
        &production_stages,
    .campaign_complete_pages = &campaign_complete_pages,
};

pub const skip_title_screen = config.use_feature_test_stage;

pub const initial_stage_id = active_campaign.stages[0].id;
pub const initial_shift = active_campaign.stages[0].shifts[0];

pub const Conveyor = conveyor.Conveyor;

pub const WarehouseDescriptor = struct {
    stage: *const campaign.StageDefinition,
    forklift_spawn: math2.Vec2,
    world_size: math2.Vec2,
    collides: *const fn (vehicle.Forklift, ?cargo.Pallet) bool,
    cargo_collides: *const fn (cargo.Pallet) bool,
    blocks_fork_lowering: *const fn (vehicle.Forklift, ?cargo.Pallet, vehicle.ForkHeight, vehicle.ForkHeight) bool,
    blocks_fork_raising: *const fn (vehicle.Forklift, ?cargo.Pallet, vehicle.ForkHeight, vehicle.ForkHeight) bool,
    draw: *const fn (*render.Renderer, static_level.DrawPhase, f32) void,
    collect_opaque_surfaces: *const fn (*compositor.OpaqueSurfaceCollector) void,
    draw_decorative_pallets: *const fn (*render.Renderer) void,
    pallet_drop_support: *const fn (vehicle.ForkHeight, cargo.Pallet) ?f32,
};

fn descriptorFor(comptime content: anytype) WarehouseDescriptor {
    return .{
        .stage = &content.stage,
        .forklift_spawn = content.forklift_spawn,
        .world_size = content.world_size,
        .collides = struct {
            fn call(f: vehicle.Forklift, p: ?cargo.Pallet) bool {
                return content.warehouse.collides(f, p);
            }
        }.call,
        .cargo_collides = struct {
            fn call(p: cargo.Pallet) bool {
                return content.warehouse.collidesCargo(p);
            }
        }.call,
        .blocks_fork_lowering = struct {
            fn call(f: vehicle.Forklift, p: ?cargo.Pallet, from: vehicle.ForkHeight, to: vehicle.ForkHeight) bool {
                return content.warehouse.blocksForkLowering(f, p, from, to);
            }
        }.call,
        .blocks_fork_raising = struct {
            fn call(f: vehicle.Forklift, p: ?cargo.Pallet, from: vehicle.ForkHeight, to: vehicle.ForkHeight) bool {
                return content.warehouse.blocksForkRaising(f, p, from, to);
            }
        }.call,
        .draw = struct {
            fn call(r: *render.Renderer, p: static_level.DrawPhase, d: f32) void {
                content.warehouse.draw(r, p, d);
            }
        }.call,
        .collect_opaque_surfaces = struct {
            fn call(c: *compositor.OpaqueSurfaceCollector) void {
                content.warehouse.collectOpaqueSurfaces(c);
            }
        }.call,
        .draw_decorative_pallets = struct {
            fn call(r: *render.Renderer) void {
                for (content.decorative_pallets) |pallet| {
                    r.palletShadow(pallet);
                    r.pallet(pallet);
                }
            }
        }.call,
        .pallet_drop_support = struct {
            fn call(h: vehicle.ForkHeight, p: cargo.Pallet) ?f32 {
                return if (@hasDecl(content, "palletDropSupport")) content.palletDropSupport(h, p) else null;
            }
        }.call,
    };
}

const descriptors = [_]WarehouseDescriptor{
    descriptorFor(training_facility), descriptorFor(stress_test), descriptorFor(first_warehouse), descriptorFor(feature_test), descriptorFor(conveyor_warehouse),
};

pub fn descriptor(stage_id: campaign.StageId) *const WarehouseDescriptor {
    for (&descriptors) |*entry| if (entry.stage.id == stage_id) return entry;
    unreachable;
}

pub fn forkliftSpawn(stage_id: campaign.StageId) math2.Vec2 {
    return descriptor(stage_id).forklift_spawn;
}

pub fn worldSize(stage_id: campaign.StageId) math2.Vec2 {
    return descriptor(stage_id).world_size;
}

pub fn collides(
    stage_id: campaign.StageId,
    forklift: vehicle.Forklift,
    carried: ?cargo.Pallet,
) bool {
    return descriptor(stage_id).collides(forklift, carried);
}

pub fn cargoCollides(stage_id: campaign.StageId, pallet: cargo.Pallet) bool {
    return descriptor(stage_id).cargo_collides(pallet);
}
pub fn conveyors(stage_id: campaign.StageId) []const Conveyor {
    if (stage_id == .conveyor_warehouse) return &conveyor_warehouse.conveyors;
    return &[_]Conveyor{};
}

pub fn blocksForkLowering(
    stage_id: campaign.StageId,
    forklift: vehicle.Forklift,
    carried: ?cargo.Pallet,
    from_height: vehicle.ForkHeight,
    to_height: vehicle.ForkHeight,
) bool {
    return descriptor(stage_id).blocks_fork_lowering(forklift, carried, from_height, to_height);
}

pub fn blocksForkRaising(
    stage_id: campaign.StageId,
    forklift: vehicle.Forklift,
    carried: ?cargo.Pallet,
    from_height: vehicle.ForkHeight,
    to_height: vehicle.ForkHeight,
) bool {
    return descriptor(stage_id).blocks_fork_raising(forklift, carried, from_height, to_height);
}

pub fn drawWarehouse(
    stage_id: campaign.StageId,
    renderer: *render.Renderer,
    phase: static_level.DrawPhase,
    actor_depth: f32,
) void {
    descriptor(stage_id).draw(renderer, phase, actor_depth);
}

pub fn collectOpaqueSurfaces(
    stage_id: campaign.StageId,
    collector: *compositor.OpaqueSurfaceCollector,
) void {
    descriptor(stage_id).collect_opaque_surfaces(collector);
}

pub fn drawDecorativePallets(
    stage_id: campaign.StageId,
    renderer: *render.Renderer,
) void {
    descriptor(stage_id).draw_decorative_pallets(renderer);
}

pub fn palletDropSupport(
    stage_id: campaign.StageId,
    fork_height: vehicle.ForkHeight,
    pallet: cargo.Pallet,
) ?f32 {
    return descriptor(stage_id).pallet_drop_support(fork_height, pallet);
}
