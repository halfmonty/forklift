const static_level = @import("static_level.zig");
const training_facility = @import("training_facility.zig");
const stress_test = @import("stress_test.zig");
const campaign = @import("../game/campaign.zig");
const cargo = @import("../sim/cargo.zig");
const math2 = @import("../sim/math2.zig");
const vehicle = @import("../sim/vehicle.zig");
const render = @import("../render/renderer.zig");

// Development-only selection. Production stages belong in production_stages.
pub const use_stress_stage = false;

const production_stages = [_]campaign.StageDefinition{training_facility.stage};
const stress_stages = [_]campaign.StageDefinition{stress_test.stage};

pub const active_campaign = campaign.CampaignDefinition{
    .stages = if (use_stress_stage) &stress_stages else &production_stages,
};

pub const initial_stage_id = active_campaign.stages[0].id;
pub const initial_shift = active_campaign.stages[0].shifts[0];

pub fn forkliftSpawn(stage_id: campaign.StageId) math2.Vec2 {
    return switch (stage_id) {
        .training_facility => training_facility.forklift_spawn,
        .stress_test => stress_test.forklift_spawn,
    };
}

pub fn worldSize(stage_id: campaign.StageId) math2.Vec2 {
    return switch (stage_id) {
        .training_facility => training_facility.world_size,
        .stress_test => stress_test.world_size,
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
    }
}

pub fn rackLowDropSupport(
    stage_id: campaign.StageId,
    pallet: cargo.Pallet,
) ?f32 {
    return switch (stage_id) {
        .training_facility => if (training_facility.palletFitsRackLowShelf(pallet))
            training_facility.rack_low_support_z
        else
            null,
        .stress_test => if (stress_test.palletFitsRackLowShelf(pallet))
            stress_test.rack_low_support_z
        else
            null,
    };
}
