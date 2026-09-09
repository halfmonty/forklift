const std = @import("std");
const campaign = @import("../game/campaign.zig");
const cargo = @import("../sim/cargo.zig");
const jobs = @import("../sim/jobs.zig");
const math2 = @import("../sim/math2.zig");
const scoring = @import("../game/scoring.zig");
const stages = @import("../content/stages.zig");
const vehicle = @import("../sim/vehicle.zig");
const world_module = @import("world.zig");

const impact_rearm_distance: f32 = 12;

pub const Phase = enum {
    frame_intent,
    modifiers,
    vehicle_forks,
    collision,
    carry_transport,
    interactions,
    objectives,
    scene_submission,
};

pub const phase_order = [_]Phase{
    .frame_intent,
    .modifiers,
    .vehicle_forks,
    .collision,
    .carry_transport,
    .interactions,
    .objectives,
    .scene_submission,
};

pub const Event = union(enum) {
    pallet_engaged: void,
    fork_height_moved: void,
    cargo_dropped: world_module.CargoId,
    cargo_transported: world_module.CargoId,
    collision_impact: void,
    objective_completed: void,
};

pub const Command = union(enum) {
    begin_next_job: usize,
};

pub const EventBuffer = FixedBuffer(Event, 16);
pub const CommandBuffer = FixedBuffer(Command, 16);

pub fn FixedBuffer(comptime T: type, comptime capacity: usize) type {
    return struct {
        items: [capacity]T = undefined,
        len: usize = 0,

        pub const Error = error{CapacityExceeded};

        pub fn clear(self: *@This()) void {
            self.len = 0;
        }

        pub fn append(self: *@This(), item: T) Error!void {
            if (self.len == self.items.len) return error.CapacityExceeded;
            self.items[self.len] = item;
            self.len += 1;
        }

        pub fn slice(self: *const @This()) []const T {
            return self.items[0..self.len];
        }
    };
}

pub const Frame = struct {
    dt: f32,
    crank_delta_deg: f32 = 0,
    steering_ratio: vehicle.SteeringRatio = .medium,
    forward: bool = false,
    reverse: bool = false,
    camera_mode: bool = false,
    raise_pressed: bool = false,
    lower_pressed: bool = false,
    action_pressed: bool = false,
};

pub const SoundRequests = struct {
    pallet_engaged: bool = false,
    fork_height_moved: bool = false,
};

pub const StepTransition = enum {
    none,
    next_job,
    shift_completed,
};

pub const StepResult = struct {
    sounds: SoundRequests = .{},
    transition: StepTransition = .none,
    next_job_index: ?usize = null,
    phases: [phase_order.len]Phase = phase_order,
};

pub const WarehouseRuntime = struct {
    world: world_module.World,
    stage_id: campaign.StageId,
    shift: *const campaign.ShiftDefinition,
    events: EventBuffer = .{},
    commands: CommandBuffer = .{},

    pub fn init(
        stage_id: campaign.StageId,
        shift: *const campaign.ShiftDefinition,
    ) WarehouseRuntime {
        return .{
            .world = world_module.World.init(
                shift,
                stages.forkliftSpawn(stage_id),
            ),
            .stage_id = stage_id,
            .shift = shift,
        };
    }

    pub fn beginShift(
        self: *WarehouseRuntime,
        stage_id: campaign.StageId,
        shift: *const campaign.ShiftDefinition,
    ) void {
        self.stage_id = stage_id;
        self.shift = shift;
        self.world.beginShift(shift, stages.forkliftSpawn(stage_id));
    }

    pub fn startJob(self: *WarehouseRuntime, job_index: usize) void {
        self.world.startJob(self.shift, job_index);
    }

    pub fn resetCurrentJob(self: *WarehouseRuntime) void {
        self.world.resetCurrentJob(
            self.shift,
            stages.forkliftSpawn(self.stage_id),
        );
    }

    pub fn step(self: *WarehouseRuntime, frame: Frame) StepResult {
        var result = StepResult{};
        self.events.clear();
        self.commands.clear();
        const pallet = self.world.primaryCargo();
        const previous_position = self.world.forklift.position;
        const previous_heading = self.world.forklift.heading_rad;
        const previous_pallet = pallet.*;

        vehicle.update(&self.world.forklift, .{
            .crank_delta_deg = if (frame.camera_mode) 0 else frame.crank_delta_deg,
            .steering_ratio = frame.steering_ratio,
            .forward = !frame.camera_mode and frame.forward,
            .reverse = !frame.camera_mode and frame.reverse,
        }, if (pallet.state == .carried)
            pallet.cargo.carried_acceleration_multiplier
        else
            1.0, frame.dt);

        const previous_fork_height = self.world.forklift.fork_height;
        if (!frame.camera_mode and frame.raise_pressed) {
            var raised = self.world.forklift;
            vehicle.raiseForks(&raised);
            const carried = if (pallet.state == .carried) pallet.* else null;
            if (!stages.blocksForkRaising(
                self.stage_id,
                self.world.forklift,
                carried,
                self.world.forklift.fork_height,
                raised.fork_height,
            )) self.world.forklift.fork_height = raised.fork_height;
        } else if (!frame.camera_mode and frame.lower_pressed) {
            var lowered = self.world.forklift;
            vehicle.lowerForks(&lowered);
            const carried = if (pallet.state == .carried) pallet.* else null;
            if (!stages.blocksForkLowering(
                self.stage_id,
                self.world.forklift,
                carried,
                self.world.forklift.fork_height,
                lowered.fork_height,
            )) self.world.forklift.fork_height = lowered.fork_height;
        }
        result.sounds.fork_height_moved = self.world.forklift.fork_height != previous_fork_height;
        if (result.sounds.fork_height_moved) self.events.append(.fork_height_moved) catch unreachable;

        if (pallet.state == .carried) cargo.followForks(pallet, self.world.forklift);
        if (self.world.impact_origin) |origin| {
            const displacement = math2.sub(self.world.forklift.position, origin);
            if (math2.dot(displacement, displacement) >= impact_rearm_distance * impact_rearm_distance) {
                self.world.impact_origin = null;
            }
        }
        if (forkliftCollides(self.stage_id, self.world.forklift, pallet.*)) {
            if (self.world.impact_origin == null) {
                self.world.collision_impacts += 1;
                self.world.impact_origin = previous_position;
                self.events.append(.collision_impact) catch unreachable;
            }
            restoreAfterCollision(
                &self.world.forklift,
                pallet,
                previous_position,
                previous_heading,
                previous_pallet,
            );
        }

        if (pallet.state == .floor) {
            for (stages.conveyors(self.stage_id)) |conveyor| {
                if (!pointInsideRect(pallet.position, conveyor.bounds)) continue;
                var proposed = pallet.*;
                proposed.position = math2.add(proposed.position, math2.scale(conveyor.direction, conveyor.speed * frame.dt));
                if (!stages.cargoCollides(self.stage_id, proposed)) {
                    pallet.position = proposed.position;
                    self.events.append(.{ .cargo_transported = .primary }) catch unreachable;
                }
                break;
            }
        }

        if (frame.action_pressed) {
            if (pallet.state == .carried) {
                if (self.world.forklift.fork_height == .floor) {
                    cargo.drop(pallet);
                    self.events.append(.{ .cargo_dropped = .primary }) catch unreachable;
                } else if (stages.palletDropSupport(
                    self.stage_id,
                    self.world.forklift.fork_height,
                    pallet.*,
                )) |support_z| {
                    cargo.dropAt(pallet, support_z);
                    self.events.append(.{ .cargo_dropped = .primary }) catch unreachable;
                }
            } else if (@abs(vehicle.forkZ(self.world.forklift.fork_height) - pallet.support_z) < 0.1 and
                cargo.tryPickup(pallet, self.world.forklift, pickup_tuning))
            {
                result.sounds.pallet_engaged = true;
                self.events.append(.pallet_engaged) catch unreachable;
                if (self.world.forklift.fork_height == .floor) self.world.forklift.fork_height = .carry;
            }
        }
        if (pallet.state == .carried) {
            cargo.followForks(pallet, self.world.forklift);
            pallet.z = vehicle.forkZ(self.world.forklift.fork_height);
        }

        if (self.world.objective.job_state != .delivered) {
            self.world.shift_elapsed_seconds += frame.dt;
            self.world.objective.job_state = jobs.update(
                self.world.objective.job_state,
                pallet.*,
                self.world.objective.destination,
            );
            if (self.world.objective.job_state == .delivered) {
                self.events.append(.objective_completed) catch unreachable;
                if (self.world.objective.job_index + 1 < self.shift.jobs.len) {
                    result.transition = .next_job;
                    result.next_job_index = self.world.objective.job_index + 1;
                    self.commands.append(.{ .begin_next_job = result.next_job_index.? }) catch unreachable;
                } else {
                    self.world.shift_result = scoring.calculate(
                        self.shift.scoring,
                        self.world.shift_elapsed_seconds,
                        self.shift.jobs.len,
                        self.world.collision_impacts,
                    );
                    result.transition = .shift_completed;
                }
            }
        }
        return result;
    }
};

const pickup_tuning = cargo.PickupTuning{
    .max_angle_error_rad = 0.4,
    .tine_lateral_tolerance = 3,
    .minimum_insertion = 18,
};

fn forkliftCollides(
    stage_id: campaign.StageId,
    forklift: vehicle.Forklift,
    pallet: cargo.Pallet,
) bool {
    return stages.collides(
        stage_id,
        forklift,
        if (pallet.state == .carried) pallet else null,
    );
}

fn restoreAfterCollision(
    forklift: *vehicle.Forklift,
    pallet: *cargo.Pallet,
    previous_position: math2.Vec2,
    previous_heading: f32,
    previous_pallet: cargo.Pallet,
) void {
    forklift.position = previous_position;
    forklift.heading_rad = previous_heading;
    forklift.speed = 0;
    pallet.* = previous_pallet;
}

fn pointInsideRect(point: math2.Vec2, rect: @import("../sim/collision.zig").Rect) bool {
    return point.x >= rect.x and point.x <= rect.x + rect.width and point.y >= rect.y and point.y <= rect.y + rect.height;
}

test "collision rollback restores vehicle and cargo snapshot" {
    const previous_position = math2.Vec2{ .x = 120, .y = 240 };
    const previous_pallet = cargo.Pallet{ .position = .{ .x = 160, .y = 260 }, .state = .carried };
    var forklift = vehicle.Forklift{ .position = .{ .x = 180, .y = 300 }, .heading_rad = 1.4, .speed = 45 };
    var pallet = cargo.Pallet{ .position = .{ .x = 220, .y = 320 }, .state = .carried };
    restoreAfterCollision(&forklift, &pallet, previous_position, 0.75, previous_pallet);
    try std.testing.expectEqual(previous_position, forklift.position);
    try std.testing.expectEqual(@as(f32, 0.75), forklift.heading_rad);
    try std.testing.expectEqual(@as(f32, 0), forklift.speed);
    try std.testing.expectEqual(previous_pallet, pallet);
}

test "runtime step completes a delivered final job" {
    const shift_jobs = [_]jobs.JobDefinition{.{
        .pallet_spawn = .{ .position = .{ .x = 10, .y = 10 } },
        .destination = .{ .x = 100, .y = 100, .width = 80, .height = 80 },
        .cargo = cargo.standard_cargo,
    }};
    const shift = campaign.ShiftDefinition{
        .id = .training_orientation,
        .stage_id = .training_facility,
        .title = "Test shift",
        .jobs = &shift_jobs,
        .briefings = &[_]campaign.BossMessage{},
        .scoring = .{
            .completion_points = 100,
            .target_time_seconds = 60,
            .time_bonus_per_second = 1,
            .collision_penalty = 10,
        },
    };
    var runtime = WarehouseRuntime.init(.training_facility, &shift);
    runtime.world.primaryCargo().* = .{
        .position = .{ .x = 140, .y = 140 },
        .state = .floor,
    };
    runtime.world.objective.job_state = .carrying;

    const result = runtime.step(.{ .dt = 0.25 });

    try std.testing.expectEqual(StepTransition.shift_completed, result.transition);
    try std.testing.expectEqual(jobs.JobState.delivered, runtime.world.objective.job_state);
    try std.testing.expect(runtime.world.shift_result != null);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.25),
        runtime.world.shift_elapsed_seconds,
        0.0001,
    );
}

test "runtime step picks up cargo and emits a semantic engagement request" {
    const shift_jobs = [_]jobs.JobDefinition{.{
        .pallet_spawn = .{ .position = .{ .x = 600, .y = 330 } },
        .destination = .{ .x = 900, .y = 600, .width = 80, .height = 80 },
        .cargo = cargo.standard_cargo,
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
    var runtime = WarehouseRuntime.init(.training_facility, &shift);
    runtime.world.forklift.position = .{ .x = 600, .y = 377 };

    const result = runtime.step(.{ .dt = 0, .action_pressed = true });

    try std.testing.expect(result.sounds.pallet_engaged);
    try std.testing.expect(!result.sounds.fork_height_moved);
    try std.testing.expectEqual(cargo.PalletState.carried, runtime.world.primaryCargo().state);
    try std.testing.expectEqual(vehicle.ForkHeight.carry, runtime.world.forklift.fork_height);
    try std.testing.expectEqual(jobs.JobState.carrying, runtime.world.objective.job_state);
}

test "runtime phase order and bounded buffers are explicit contracts" {
    try std.testing.expectEqualSlices(Phase, &[_]Phase{
        .frame_intent,
        .modifiers,
        .vehicle_forks,
        .collision,
        .carry_transport,
        .interactions,
        .objectives,
        .scene_submission,
    }, &phase_order);

    var events = EventBuffer{};
    for (0..16) |_| try events.append(.pallet_engaged);
    try std.testing.expectError(error.CapacityExceeded, events.append(.pallet_engaged));

    var commands = CommandBuffer{};
    try commands.append(.{ .begin_next_job = 1 });
    try std.testing.expectEqual(@as(usize, 1), commands.slice().len);
}
