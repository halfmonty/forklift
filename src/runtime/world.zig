const std = @import("std");
const campaign = @import("../game/campaign.zig");
const cargo = @import("../sim/cargo.zig");
const collision = @import("../sim/collision.zig");
const jobs = @import("../sim/jobs.zig");
const math2 = @import("../sim/math2.zig");
const scoring = @import("../game/scoring.zig");
const vehicle = @import("../sim/vehicle.zig");

pub const CargoId = enum(u8) {
    primary = 0,
};

pub const CargoStore = struct {
    items: [1]?cargo.Pallet = .{null},

    pub const Error = error{CapacityExceeded};

    pub fn clear(self: *CargoStore) void {
        self.items = .{null};
    }

    pub fn spawn(
        self: *CargoStore,
        id: CargoId,
        pallet: cargo.Pallet,
    ) Error!void {
        const index: usize = @intFromEnum(id);
        if (self.items[index] != null) return error.CapacityExceeded;
        self.items[index] = pallet;
    }

    pub fn get(self: *CargoStore, id: CargoId) ?*cargo.Pallet {
        const index: usize = @intFromEnum(id);
        if (self.items[index] == null) return null;
        return &self.items[index].?;
    }
};

pub const ObjectiveRuntime = struct {
    job_index: usize = 0,
    job_state: jobs.JobState = .waiting_for_pickup,
    destination: collision.Rect,
};

pub const DynamicActorStore = struct {};
pub const TransientState = struct {};

pub const World = struct {
    forklift: vehicle.Forklift,
    cargo: CargoStore = .{},
    gates: GateStore = .{},
    pressure_plates: PressurePlateStore = .{},
    objective: ObjectiveRuntime,
    shift_elapsed_seconds: f32 = 0,
    collision_impacts: u32 = 0,
    impact_origin: ?math2.Vec2 = null,
    shift_result: ?scoring.ShiftResult = null,
    dynamic_actors: DynamicActorStore = .{},
    transient: TransientState = .{},

    pub fn init(
        shift: *const campaign.ShiftDefinition,
        forklift_spawn: math2.Vec2,
    ) World {
        std.debug.assert(shift.jobs.len > 0);
        var world = World{
            .forklift = .{ .position = forklift_spawn },
            .objective = .{
                .destination = shift.jobs[0].destination,
            },
        };
        world.startJob(shift, 0);
        return world;
    }

    pub fn beginShift(
        self: *World,
        shift: *const campaign.ShiftDefinition,
        forklift_spawn: math2.Vec2,
    ) void {
        self.shift_elapsed_seconds = 0;
        self.collision_impacts = 0;
        self.impact_origin = null;
        self.shift_result = null;
        self.objective.job_index = 0;
        self.resetCurrentJob(shift, forklift_spawn);
    }

    pub fn startJob(
        self: *World,
        shift: *const campaign.ShiftDefinition,
        job_index: usize,
    ) void {
        std.debug.assert(job_index < shift.jobs.len);
        const job = shift.jobs[job_index];
        self.objective = .{
            .job_index = job_index,
            .job_state = .waiting_for_pickup,
            .destination = job.destination,
        };
        self.gates.clear();
        self.pressure_plates.clear();
        self.cargo.clear();
        self.cargo.spawn(.primary, palletForJob(job)) catch unreachable;
    }

    pub fn resetCurrentJob(
        self: *World,
        shift: *const campaign.ShiftDefinition,
        forklift_spawn: math2.Vec2,
    ) void {
        self.forklift.reset(forklift_spawn);
        self.startJob(shift, self.objective.job_index);
    }

    pub fn primaryCargo(self: *World) *cargo.Pallet {
        return self.cargo.get(.primary) orelse unreachable;
    }
};

pub fn palletForJob(job: jobs.JobDefinition) cargo.Pallet {
    return .{
        .position = job.pallet_spawn.position,
        .z = job.pallet_spawn.support_z,
        .support_z = job.pallet_spawn.support_z,
        .cargo = job.cargo,
        .footprint = job.cargo.footprint,
    };
}

pub const max_gates = 8;

pub const GateStore = struct {
    open: [max_gates]bool = [_]bool{false} ** max_gates,

    pub fn clear(self: *GateStore) void {
        self.open = [_]bool{false} ** max_gates;
    }

    pub fn isOpen(self: *const GateStore, gate_index: usize) bool {
        std.debug.assert(gate_index < self.open.len);
        return self.open[gate_index];
    }

    pub fn setOpen(
        self: *GateStore,
        gate_index: usize,
        value: bool,
    ) bool {
        std.debug.assert(gate_index < self.open.len);

        const changed = self.open[gate_index] != value;
        self.open[gate_index] = value;
        return changed;
    }
};

pub const max_pressure_plates = 8;

pub const PressurePlateStore = struct {
    active: [max_pressure_plates]bool = [_]bool{false} ** max_pressure_plates,

    pub fn clear(self: *PressurePlateStore) void {
        self.active = [_]bool{false} ** max_pressure_plates;
    }

    pub fn isActive(
        self: *const PressurePlateStore,
        plate_index: usize,
    ) bool {
        std.debug.assert(plate_index < self.active.len);
        return self.active[plate_index];
    }

    pub fn setActive(
        self: *PressurePlateStore,
        plate_index: usize,
        value: bool,
    ) bool {
        std.debug.assert(plate_index < self.active.len);

        const changed = self.active[plate_index] != value;
        self.active[plate_index] = value;
        return changed;
    }
};

test "world initialization creates the first job at its authored state" {
    const shift_jobs = [_]jobs.JobDefinition{.{
        .pallet_spawn = .{
            .position = .{ .x = 300, .y = 420 },
            .support_z = vehicle.forkZ(.rack_low),
        },
        .destination = .{ .x = 600, .y = 200, .width = 80, .height = 90 },
        .cargo = cargo.heavy_cargo,
    }};
    const shift = campaign.ShiftDefinition{
        .id = .training_orientation,
        .stage_id = .training_facility,
        .title = "Test shift",
        .jobs = &shift_jobs,
        .briefings = &[_]campaign.BossMessage{},
        .scoring = .{
            .completion_points = 0,
            .target_time_seconds = 0,
            .time_bonus_per_second = 0,
            .collision_penalty = 0,
        },
    };

    var world = World.init(&shift, .{ .x = 120, .y = 240 });
    const pallet = world.primaryCargo().*;

    try std.testing.expectEqual(
        (math2.Vec2{ .x = 120, .y = 240 }),
        world.forklift.position,
    );
    try std.testing.expectEqual(@as(usize, 0), world.objective.job_index);
    try std.testing.expectEqual(jobs.JobState.waiting_for_pickup, world.objective.job_state);
    try std.testing.expectEqual(shift_jobs[0].pallet_spawn.position, pallet.position);
    try std.testing.expectEqual(shift_jobs[0].pallet_spawn.support_z, pallet.support_z);
    try std.testing.expectEqual(shift_jobs[0].cargo, pallet.cargo);
    try std.testing.expectEqual(@as(f32, 0), world.shift_elapsed_seconds);
    try std.testing.expectEqual(@as(u32, 0), world.collision_impacts);
}

test "cargo store rejects a second primary cargo item" {
    var store = CargoStore{};
    const first = cargo.Pallet{ .position = .{ .x = 10, .y = 20 } };

    try store.spawn(.primary, first);
    try std.testing.expectError(
        error.CapacityExceeded,
        store.spawn(.primary, .{ .position = .{ .x = 30, .y = 40 } }),
    );
    try std.testing.expectEqual(first, store.get(.primary).?.*);
}

test "world reset restores the active job while preserving shift accounting" {
    const shift_jobs = [_]jobs.JobDefinition{
        .{
            .pallet_spawn = .{ .position = .{ .x = 100, .y = 200 } },
            .destination = .{ .x = 300, .y = 400, .width = 50, .height = 60 },
            .cargo = cargo.standard_cargo,
        },
        .{
            .pallet_spawn = .{
                .position = .{ .x = 500, .y = 600 },
                .support_z = vehicle.forkZ(.rack_low),
            },
            .destination = .{ .x = 700, .y = 800, .width = 70, .height = 80 },
            .cargo = cargo.heavy_cargo,
        },
    };
    const shift = campaign.ShiftDefinition{
        .id = .training_orientation,
        .stage_id = .training_facility,
        .title = "Test shift",
        .jobs = &shift_jobs,
        .briefings = &[_]campaign.BossMessage{},
        .scoring = .{
            .completion_points = 0,
            .target_time_seconds = 0,
            .time_bonus_per_second = 0,
            .collision_penalty = 0,
        },
    };
    const spawn = math2.Vec2{ .x = 30, .y = 40 };
    var world = World.init(&shift, spawn);
    world.startJob(&shift, 1);
    world.forklift = .{
        .position = .{ .x = 1, .y = 2 },
        .heading_rad = 1.5,
        .speed = 80,
        .fork_height = .rack_high,
    };
    world.primaryCargo().* = .{
        .position = .{ .x = 3, .y = 4 },
        .state = .carried,
    };
    world.objective.job_state = .carrying;
    world.shift_elapsed_seconds = 37;
    world.collision_impacts = 2;
    world.impact_origin = .{ .x = 5, .y = 6 };

    world.resetCurrentJob(&shift, spawn);

    try std.testing.expectEqual(spawn, world.forklift.position);
    try std.testing.expectEqual(@as(f32, 0), world.forklift.heading_rad);
    try std.testing.expectEqual(@as(f32, 0), world.forklift.speed);
    try std.testing.expectEqual(vehicle.ForkHeight.floor, world.forklift.fork_height);
    try std.testing.expectEqual(@as(usize, 1), world.objective.job_index);
    try std.testing.expectEqual(jobs.JobState.waiting_for_pickup, world.objective.job_state);
    try std.testing.expectEqual(shift_jobs[1].destination, world.objective.destination);
    try std.testing.expectEqual(palletForJob(shift_jobs[1]), world.primaryCargo().*);
    try std.testing.expectEqual(@as(f32, 37), world.shift_elapsed_seconds);
    try std.testing.expectEqual(@as(u32, 2), world.collision_impacts);
    try std.testing.expectEqual((math2.Vec2{ .x = 5, .y = 6 }), world.impact_origin.?);
}

test "gate store resets every gate closed" {
    var gates = GateStore{};
    try std.testing.expect(gates.setOpen(2, true));
    try std.testing.expect(gates.isOpen(2));

    gates.clear();

    try std.testing.expect(!gates.isOpen(2));
}
