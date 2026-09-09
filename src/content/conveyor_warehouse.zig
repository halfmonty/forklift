const static_level = @import("static_level.zig");
const conveyor = @import("../sim/conveyor.zig");
const math2 = @import("../sim/math2.zig");
const collision = @import("../sim/collision.zig");
const cargo = @import("../sim/cargo.zig");
const jobs = @import("../sim/jobs.zig");
const campaign = @import("../game/campaign.zig");

pub const forklift_spawn = math2.Vec2{ .x = 280, .y = 430 };
pub const world_size = math2.Vec2{ .x = 1200, .y = 800 };
pub const Warehouse = static_level.StaticLevel(.{
    static_level.Obstacle{ .bounds = .{ .x = 520, .y = 180, .width = 40, .height = 140 } },
    static_level.Obstacle{ .bounds = .{ .x = 520, .y = 460, .width = 40, .height = 160 } },
});
pub const warehouse = Warehouse{};
pub const conveyors = [_]conveyor.Conveyor{.{ .bounds = .{ .x = 460, .y = 320, .width = 220, .height = 140 }, .direction = .{ .x = 1, .y = 0 }, .speed = 40 }};
const jobs_data = [_]jobs.JobDefinition{.{ .pallet_spawn = .{ .position = .{ .x = 410, .y = 390 } }, .destination = .{ .x = 760, .y = 350, .width = 120, .height = 100 }, .cargo = cargo.standard_cargo }};
const pages = [_][]const u8{ "Place floor cargo on the conveyor.", "The forklift and carried cargo do not move with it." };
const briefings = [_]campaign.BossMessage{.{ .trigger = .shift_start, .pages = &pages }};
pub const shift = campaign.ShiftDefinition{ .id = .conveyor_delivery, .stage_id = .conveyor_warehouse, .title = "Conveyor Crossing", .jobs = &jobs_data, .briefings = &briefings, .scoring = .{ .completion_points = 750, .target_time_seconds = 90, .time_bonus_per_second = 5, .collision_penalty = 100 } };
const shifts = [_]campaign.ShiftDefinition{shift};
const promotion_pages = [_][]const u8{"Conveyor training complete."};
pub const stage = campaign.StageDefinition{ .id = .conveyor_warehouse, .title = "Conveyor Warehouse", .shifts = &shifts, .promotion_pages = &promotion_pages };
pub const decorative_pallets = [_]cargo.Pallet{};
