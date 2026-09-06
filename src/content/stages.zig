const static_level = @import("static_level.zig");
const training_facility = @import("training_facility.zig");
const first_warehouse = @import("first_warehouse.zig");
const feature_test = @import("feature_test.zig");
const stress_test = @import("stress_test.zig");
const campaign = @import("../game/campaign.zig");
const cargo = @import("../sim/cargo.zig");
const math2 = @import("../sim/math2.zig");
const vehicle = @import("../sim/vehicle.zig");
const render = @import("../render/renderer.zig");
const compositor = @import("../render/compositor.zig");
const config = @import("../config.zig");

const production_stages = [_]campaign.StageDefinition{
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

pub fn forkliftSpawn(stage_id: campaign.StageId) math2.Vec2 {
    return switch (stage_id) {
        .training_facility => training_facility.forklift_spawn,
        .stress_test => stress_test.forklift_spawn,
        .first_warehouse => first_warehouse.forklift_spawn,
        .feature_test => feature_test.forklift_spawn,
    };
}

pub fn worldSize(stage_id: campaign.StageId) math2.Vec2 {
    return switch (stage_id) {
        .training_facility => training_facility.world_size,
        .stress_test => stress_test.world_size,
        .first_warehouse => first_warehouse.world_size,
        .feature_test => feature_test.world_size,
    };
}

pub fn collides(
    stage_id: campaign.StageId,
    forklift: vehicle.Forklift,
    carried: ?cargo.Pallet,
) bool {
    return switch (stage_id) {
        .training_facility => training_facility.warehouse.collides(forklift, carried),
        .stress_test => stress_test.warehouse.collides(forklift, carried),
        .first_warehouse => first_warehouse.warehouse.collides(forklift, carried),
        .feature_test => feature_test.warehouse.collides(forklift, carried),
    };
}

pub fn blocksForkLowering(
    stage_id: campaign.StageId,
    forklift: vehicle.Forklift,
    carried: ?cargo.Pallet,
    from_height: vehicle.ForkHeight,
    to_height: vehicle.ForkHeight,
) bool {
    return switch (stage_id) {
        .training_facility => training_facility.warehouse.blocksForkLowering(
            forklift,
            carried,
            from_height,
            to_height,
        ),
        .stress_test => stress_test.warehouse.blocksForkLowering(
            forklift,
            carried,
            from_height,
            to_height,
        ),
        .first_warehouse => first_warehouse.warehouse.blocksForkLowering(
            forklift,
            carried,
            from_height,
            to_height,
        ),
        .feature_test => feature_test.warehouse.blocksForkLowering(
            forklift,
            carried,
            from_height,
            to_height,
        ),
    };
}

pub fn blocksForkRaising(
    stage_id: campaign.StageId,
    forklift: vehicle.Forklift,
    carried: ?cargo.Pallet,
    from_height: vehicle.ForkHeight,
    to_height: vehicle.ForkHeight,
) bool {
    return switch (stage_id) {
        .training_facility => training_facility.warehouse.blocksForkRaising(
            forklift,
            carried,
            from_height,
            to_height,
        ),
        .stress_test => stress_test.warehouse.blocksForkRaising(
            forklift,
            carried,
            from_height,
            to_height,
        ),
        .first_warehouse => first_warehouse.warehouse.blocksForkRaising(
            forklift,
            carried,
            from_height,
            to_height,
        ),
        .feature_test => feature_test.warehouse.blocksForkRaising(
            forklift,
            carried,
            from_height,
            to_height,
        ),
    };
}

pub fn drawWarehouse(
    stage_id: campaign.StageId,
    renderer: *render.Renderer,
    phase: static_level.DrawPhase,
    actor_depth: f32,
) void {
    switch (stage_id) {
        .training_facility => training_facility.warehouse.draw(renderer, phase, actor_depth),
        .stress_test => stress_test.warehouse.draw(renderer, phase, actor_depth),
        .first_warehouse => first_warehouse.warehouse.draw(renderer, phase, actor_depth),
        .feature_test => feature_test.warehouse.draw(renderer, phase, actor_depth),
    }
}

pub fn collectOpaqueSurfaces(
    stage_id: campaign.StageId,
    collector: *compositor.OpaqueSurfaceCollector,
) void {
    switch (stage_id) {
        .training_facility => training_facility.warehouse.collectOpaqueSurfaces(collector),
        .stress_test => stress_test.warehouse.collectOpaqueSurfaces(collector),
        .first_warehouse => first_warehouse.warehouse.collectOpaqueSurfaces(collector),
        .feature_test => feature_test.warehouse.collectOpaqueSurfaces(collector),
    }
}

pub fn drawDecorativePallets(
    stage_id: campaign.StageId,
    renderer: *render.Renderer,
) void {
    switch (stage_id) {
        .training_facility => for (training_facility.decorative_pallets) |pallet| {
            renderer.palletShadow(pallet);
            renderer.pallet(pallet);
        },
        .stress_test => for (stress_test.decorative_pallets) |pallet| {
            renderer.palletShadow(pallet);
            renderer.pallet(pallet);
        },
        .first_warehouse => for (first_warehouse.decorative_pallets) |pallet| {
            renderer.palletShadow(pallet);
            renderer.pallet(pallet);
        },
        .feature_test => for (feature_test.decorative_pallets) |pallet| {
            renderer.palletShadow(pallet);
            renderer.pallet(pallet);
        },
    }
}

pub fn palletDropSupport(
    stage_id: campaign.StageId,
    fork_height: vehicle.ForkHeight,
    pallet: cargo.Pallet,
) ?f32 {
    return switch (stage_id) {
        .training_facility => training_facility.palletDropSupport(fork_height, pallet),
        .stress_test => stress_test.palletDropSupport(fork_height, pallet),
        .first_warehouse => null,
        .feature_test => feature_test.palletDropSupport(fork_height, pallet),
    };
}
