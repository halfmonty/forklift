const level = @import("../level.zig");
const math2 = @import("../math2.zig");
const collision = @import("../collision.zig");
const vehicle = @import("../vehicle.zig");
const jobs = @import("../jobs.zig");
const cargo = @import("../cargo.zig");
const campaign = @import("../campaign.zig");
const scoring = @import("../scoring.zig");

pub const forklift_spawn = math2.Vec2{ .x = 600, .y = 400 };

const rack_low_shelf = level.Shelf{
    .zone = .{ .x = 960, .y = 380, .width = 100, .height = 100 },
    .support_z = vehicle.forkZ(.rack_low),
};

const destination = collision.Rect{
    .x = 950,
    .y = 600,
    .width = 100,
    .height = 100,
};

pub const Warehouse = level.StaticLevel(.{
    level.TallBox{ .position = .{ .x = 1000, .y = 150 } },
    level.Rack{ .bounds = .{ .x = 220, .y = 200, .width = 520, .height = 36 } },
    level.Obstacle{ .bounds = .{ .x = 220, .y = 500, .width = 520, .height = 36 } },
    level.Obstacle{ .bounds = .{ .x = 820, .y = 280, .width = 36, .height = 256 } },
    rack_low_shelf,
    level.Cone{ .position = .{ .x = 100, .y = 100 } },
    level.Cone{ .position = .{ .x = 1100, .y = 100 } },
    level.Cone{ .position = .{ .x = 100, .y = 700 } },
    level.Cone{ .position = .{ .x = 1100, .y = 700 } },
    level.Cone{ .position = .{ .x = 500, .y = 300 } },
    level.Cone{ .position = .{ .x = 600, .y = 260 } },
    level.Cone{ .position = .{ .x = 700, .y = 300 } },
    level.Cone{ .position = .{ .x = 700, .y = 500 } },
    level.Obstacle{ .bounds = .{ .x = 40, .y = 40, .width = 160, .height = 28 } },
    level.Obstacle{ .bounds = .{ .x = 260, .y = 40, .width = 160, .height = 28 } },
    level.Obstacle{ .bounds = .{ .x = 480, .y = 40, .width = 160, .height = 28 } },
    level.Obstacle{ .bounds = .{ .x = 700, .y = 40, .width = 160, .height = 28 } },
    level.Obstacle{ .bounds = .{ .x = 920, .y = 40, .width = 160, .height = 28 } },
    level.Obstacle{ .bounds = .{ .x = 40, .y = 732, .width = 160, .height = 28 } },
    level.Obstacle{ .bounds = .{ .x = 260, .y = 732, .width = 160, .height = 28 } },
    level.Obstacle{ .bounds = .{ .x = 480, .y = 732, .width = 160, .height = 28 } },
    level.Obstacle{ .bounds = .{ .x = 700, .y = 732, .width = 160, .height = 28 } },
    level.Obstacle{ .bounds = .{ .x = 920, .y = 732, .width = 160, .height = 28 } },
    level.Rack{ .bounds = .{ .x = 280, .y = 180, .width = 160, .height = 36 } },
    level.Rack{ .bounds = .{ .x = 520, .y = 180, .width = 160, .height = 36 } },
    level.Rack{ .bounds = .{ .x = 760, .y = 180, .width = 160, .height = 36 } },
    level.Rack{ .bounds = .{ .x = 280, .y = 300, .width = 160, .height = 36 } },
    level.Rack{ .bounds = .{ .x = 520, .y = 300, .width = 160, .height = 36 } },
    level.Rack{ .bounds = .{ .x = 760, .y = 300, .width = 160, .height = 36 } },
    level.Rack{ .bounds = .{ .x = 280, .y = 540, .width = 160, .height = 36 } },
    level.Rack{ .bounds = .{ .x = 640, .y = 540, .width = 160, .height = 36 } },
});

pub const warehouse = Warehouse{};

const jobs_data = [_]jobs.JobDefinition{
    .{ .pallet_spawn = .{ .position = .{ .x = 600, .y = 300 } }, .destination = destination, .cargo = cargo.standard_cargo },
    .{ .pallet_spawn = .{ .position = .{ .x = 300, .y = 600 } }, .destination = .{ .x = 900, .y = 550, .width = 75, .height = 75 }, .cargo = cargo.heavy_cargo },
    .{ .pallet_spawn = .{ .position = .{ .x = 1010, .y = 430 }, .support_z = vehicle.forkZ(.rack_low) }, .destination = .{ .x = 500, .y = 600, .width = 100, .height = 100 }, .cargo = cargo.standard_cargo },
    .{ .pallet_spawn = .{ .position = .{ .x = 600, .y = 650 } }, .destination = .{ .x = 880, .y = 100, .width = 120, .height = 120 }, .cargo = cargo.long_cargo },
};

const briefing_pages = [_][]const u8{
    "Stress-test warehouse.",
    "Drive through the dense scene and monitor frame time.",
};

pub const shift = campaign.ShiftDefinition{
    .id = .stress_test,
    .title = "Render Stress Test",
    .jobs = &jobs_data,
    .opening_briefing = .{ .pages = &briefing_pages },
    .scoring = .{
        .completion_points = 1_000,
        .target_time_seconds = 180,
        .time_bonus_per_second = 5,
        .collision_penalty = 100,
    },
};

const shifts = [_]campaign.ShiftDefinition{shift};

pub const stage = campaign.StageDefinition{
    .id = .stress_test,
    .title = "Render Stress Test",
    .shifts = &shifts,
};

pub const decorative_pallets = [_]cargo.Pallet{
    .{ .position = .{ .x = 440, .y = 330 } },
    .{ .position = .{ .x = 500, .y = 330 } },
    .{ .position = .{ .x = 560, .y = 330 } },
    .{ .position = .{ .x = 620, .y = 330 } },
    .{ .position = .{ .x = 680, .y = 330 } },
    .{ .position = .{ .x = 440, .y = 410 } },
    .{ .position = .{ .x = 500, .y = 410 } },
    .{ .position = .{ .x = 560, .y = 410 } },
    .{ .position = .{ .x = 620, .y = 410 } },
    .{ .position = .{ .x = 680, .y = 410 } },
    .{ .position = .{ .x = 740, .y = 330 }, .cargo = cargo.long_cargo, .footprint = cargo.long_cargo.footprint },
    .{ .position = .{ .x = 740, .y = 440 }, .cargo = cargo.heavy_cargo, .footprint = cargo.heavy_cargo.footprint },
};

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
