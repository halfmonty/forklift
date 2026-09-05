const level = @import("../level.zig");
const math2 = @import("../math2.zig");
const collision = @import("../collision.zig");
const vehicle = @import("../vehicle.zig");
const jobs = @import("../jobs.zig");
const cargo = @import("../cargo.zig");
const campaign = @import("../campaign.zig");
const scoring = @import("../scoring.zig");

pub const forklift_spawn = math2.Vec2{ .x = 600, .y = 400 };

const Shelf = struct {
    zone: collision.Rect,
    support_z: f32,
};

const rack_low_shelf = Shelf{
    .zone = .{
        .x = 960,
        .y = 380,
        .width = 100,
        .height = 100,
    },
    .support_z = vehicle.forkZ(.rack_low),
};

const normal_obstacles = [_]collision.Rect{
    occlusion_rack,
    .{ .x = 220, .y = 500, .width = 520, .height = 36 },
    .{ .x = 820, .y = 280, .width = 36, .height = 256 },
};

const tall_box_position = math2.Vec2{
    .x = 1000,
    .y = 150,
};

const occlusion_rack = collision.Rect{
    .x = 220,
    .y = 200,
    .width = 520,
    .height = 36,
};

const destination = collision.Rect{
    .x = 950,
    .y = 600,
    .width = 100,
    .height = 100,
};

pub const Warehouse = level.StaticLevel(.{
    level.TallBox{ .position = tall_box_position },
    level.Rack{ .bounds = occlusion_rack },
    level.Obstacle{ .bounds = normal_obstacles[1] },
    level.Obstacle{ .bounds = normal_obstacles[2] },
    level.Shelf{
        .zone = rack_low_shelf.zone,
        .support_z = rack_low_shelf.support_z,
    },
    level.Cone{ .position = .{ .x = 100, .y = 100 } },
    level.Cone{ .position = .{ .x = 1100, .y = 100 } },
    level.Cone{ .position = .{ .x = 100, .y = 700 } },
    level.Cone{ .position = .{ .x = 1100, .y = 700 } },
    level.Cone{ .position = .{ .x = 500, .y = 300 } },
    level.Cone{ .position = .{ .x = 600, .y = 260 } },
    level.Cone{ .position = .{ .x = 700, .y = 300 } },
    level.Cone{ .position = .{ .x = 700, .y = 500 } },
});

pub const warehouse = Warehouse{};

const jobs_data = [_]jobs.JobDefinition{
    .{
        .pallet_spawn = .{
            .position = .{ .x = 600, .y = 300 },
        },
        .destination = destination,
        .cargo = cargo.standard_cargo,
    },
    .{
        .pallet_spawn = .{
            .position = .{ .x = 300, .y = 600 },
        },
        .destination = .{
            .x = 900,
            .y = 550,
            .width = 75,
            .height = 75,
        },
        .cargo = cargo.heavy_cargo,
    },
    .{
        .pallet_spawn = .{
            .position = .{ .x = 1010, .y = 430 },
            .support_z = vehicle.forkZ(.rack_low),
        },
        .destination = .{
            .x = 500,
            .y = 600,
            .width = 100,
            .height = 100,
        },
        .cargo = cargo.standard_cargo,
    },
    .{
        .pallet_spawn = .{
            .position = .{ .x = 600, .y = 650 },
        },
        .destination = .{
            .x = 880,
            .y = 100,
            .width = 120,
            .height = 120,
        },
        .cargo = cargo.long_cargo,
    },
};

const orientation_pages = [_][]const u8{
    "Welcome to the Training Facility.",
    "Complete each delivery job to finish your shift.",
};

pub const shift = campaign.ShiftDefinition{
    .id = .training_orientation,
    .title = "Training Orientation",
    .jobs = &jobs_data,
    .opening_briefing = .{ .pages = &orientation_pages },
    .scoring = .{
        .completion_points = 1_000,
        .target_time_seconds = 180,
        .time_bonus_per_second = 5,
        .collision_penalty = 100,
    },
};

const shifts = [_]campaign.ShiftDefinition{shift};

pub const stage = campaign.StageDefinition{
    .id = .training_facility,
    .title = "Training Facility",
    .shifts = &shifts,
};

pub const decorative_pallets = [_]cargo.Pallet{};
pub const rack_low_support_z = rack_low_shelf.support_z;

pub fn palletFitsRackLowShelf(pallet: cargo.Pallet) bool {
    return collision.obbContainedInRect(
        pallet.position,
        pallet.footprint.half_length,
        pallet.footprint.half_width,
        pallet.heading_rad,
        rack_low_shelf.zone,
    );
}
