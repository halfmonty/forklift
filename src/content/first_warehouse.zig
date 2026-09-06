const static_level = @import("static_level.zig");
const math2 = @import("../sim/math2.zig");
const collision = @import("../sim/collision.zig");
const cargo = @import("../sim/cargo.zig");
const jobs = @import("../sim/jobs.zig");
const campaign = @import("../game/campaign.zig");

pub const forklift_spawn = math2.Vec2{ .x = 300, .y = 400 };
pub const world_size = math2.Vec2{ .x = 1200, .y = 800 };

pub const Warehouse = static_level.StaticLevel(.{});
pub const warehouse = Warehouse{};

const jobs_data = [_]jobs.JobDefinition{
    .{
        .pallet_spawn = .{ .position = .{ .x = 400, .y = 400 } },
        .destination = collision.Rect{
            .x = 800,
            .y = 350,
            .width = 120,
            .height = 100,
        },
        .cargo = cargo.standard_cargo,
    },
};

const briefing_pages = [_][]const u8{
    "Welcome to your first warehouse shift.",
    "Move the pallet to the marked delivery zone.",
};

const promotion_pages = [_][]const u8{
    "Shift complete.",
    "Good work, operator.",
};

const briefings = [_]campaign.BossMessage{
    .{ .trigger = .shift_start, .pages = &briefing_pages },
};

pub const shift = campaign.ShiftDefinition{
    .id = .first_delivery,
    .stage_id = .first_warehouse,
    .title = "First Warehouse Shift",
    .jobs = &jobs_data,
    .briefings = &briefings,
    .scoring = .{
        .completion_points = 500,
        .target_time_seconds = 60,
        .time_bonus_per_second = 5,
        .collision_penalty = 100,
    },
};

const shifts = [_]campaign.ShiftDefinition{shift};

pub const stage = campaign.StageDefinition{
    .id = .first_warehouse,
    .title = "First Warehouse",
    .shifts = &shifts,
    .promotion_pages = &promotion_pages,
};

pub const decorative_pallets = [_]cargo.Pallet{};
