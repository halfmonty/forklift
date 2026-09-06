const static_level = @import("static_level.zig");
const math2 = @import("../sim/math2.zig");
const collision = @import("../sim/collision.zig");
const cargo = @import("../sim/cargo.zig");
const jobs = @import("../sim/jobs.zig");
const campaign = @import("../game/campaign.zig");
const vehicle = @import("../sim/vehicle.zig");

pub const forklift_spawn = math2.Vec2{ .x = 1200, .y = 800 };
pub const world_size = math2.Vec2{ .x = 2400, .y = 1600 };

// const low_rack = static_level.StorageRack{
//     .bounds = .{ .x = 1572, .y = 844, .width = 56, .height = 140 },
//     .level = .low,
// };

const stacked_rack = static_level.StorageRack{
    .bounds = .{ .x = 1300, .y = 704, .width = 56, .height = 140 },
    .level = .high,
};

pub const Warehouse = static_level.StaticLevel(.{
    static_level.FloorExpansionJoints{
        .world_size = world_size,
        .cell_size = .{ .x = 400, .y = 240 },
    },
    stacked_rack,
    // low_rack,
});
pub const warehouse = Warehouse{};

const jobs_data = [_]jobs.JobDefinition{
    .{
        .pallet_spawn = .{
            .position = .{ .x = 1316, .y = 718 },
            .support_z = vehicle.forkZ(.rack_high),
        },
        .destination = collision.Rect{
            .x = 1040,
            .y = 600,
            .width = 120,
            .height = 100,
        },
        .cargo = cargo.standard_cargo,
    },
};

pub const shift = campaign.ShiftDefinition{
    .id = .feature_test,
    .stage_id = .feature_test,
    .title = "Feature Test",
    .jobs = &jobs_data,
    .briefings = &[_]campaign.BossMessage{},
    .scoring = .{
        .completion_points = 0,
        .target_time_seconds = 0,
        .time_bonus_per_second = 0,
        .collision_penalty = 0,
    },
};

const shifts = [_]campaign.ShiftDefinition{shift};
const promotion_pages = [_][]const u8{};

pub const stage = campaign.StageDefinition{
    .id = .feature_test,
    .title = "Feature Test",
    .shifts = &shifts,
    .promotion_pages = &promotion_pages,
};

pub const decorative_pallets = [_]cargo.Pallet{};

pub fn palletDropSupport(
    fork_height: vehicle.ForkHeight,
    pallet: cargo.Pallet,
) ?f32 {
    // if (low_rack.dropSupport(fork_height, pallet)) |support_z| {
    //     return support_z;
    // }
    return stacked_rack.dropSupport(fork_height, pallet);
}
