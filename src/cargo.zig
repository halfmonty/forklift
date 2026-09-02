const std = @import("std");
const math2 = @import("math2.zig");
const vehicle = @import("vehicle.zig");
const config = @import("config.zig");

pub const PalletState = enum {
    floor,
    carried,
};

pub const Footprint = struct {
    half_length: f32 = 14,
    half_width: f32 = 14,
};

pub const CargoDef = struct {
    carried_acceleration_multiplier: f32,
};

pub const standard_cargo = CargoDef{
    .carried_acceleration_multiplier = config.carried_acceleration_multiplier,
};

pub const heavy_cargo = CargoDef{
    .carried_acceleration_multiplier = 0.45,
};

pub const Pallet = struct {
    position: math2.Vec2,
    heading_rad: f32 = 0,
    state: PalletState = .floor,

    fork_lane_offset: f32 = 5,
    entry_back: f32 = -14,
    entry_front: f32 = 10,
    carry_offset: math2.Vec2 = .{ .x = 0, .y = 0 },
    footprint: Footprint = .{},
    z: f32 = 0,
    support_z: f32 = 0,
    carry_z: f32 = 12,
    cargo: CargoDef = standard_cargo,
};

pub const PickupTuning = struct {
    max_angle_error_rad: f32,
    tine_lateral_tolerance: f32,
    minimum_insertion: f32,
};

pub const PickupResult = struct {
    valid: bool,
    angle_error_rad: f32,
    insertion_depth: f32,
    entry_heading_rad: f32,
};

pub fn evaluateForkEntry(
    forklift: vehicle.Forklift,
    pallet: Pallet,
    tuning: PickupTuning,
) PickupResult {
    const forks = vehicle.forkGeometry(forklift);
    const entry_heading = nearestEntryHeading(
        forklift.heading_rad,
        pallet.heading_rad,
    );
    const left = worldToPalletLocal(
        forks.left_tip,
        pallet.position,
        entry_heading,
    );
    const right = worldToPalletLocal(
        forks.right_tip,
        pallet.position,
        entry_heading,
    );

    const angle_error = @abs(math2.shortestAngleDifference(
        forklift.heading_rad,
        entry_heading,
    ));
    const left_lane_error = @abs(left.lateral +
        pallet.fork_lane_offset);
    const right_lane_error = @abs(right.lateral -
        pallet.fork_lane_offset);
    const insertion_depth = @min(
        left.longitudinal - pallet.entry_back,
        right.longitudinal - pallet.entry_back,
    );

    const left_in_entry = left.longitudinal >=
        pallet.entry_back and
        left.longitudinal <= pallet.entry_front;
    const right_in_entry = right.longitudinal >=
        pallet.entry_back and
        right.longitudinal <= pallet.entry_front;

    return .{
        .valid = pallet.state == .floor and
            angle_error <= tuning.max_angle_error_rad and
            left_lane_error <=
                tuning.tine_lateral_tolerance and
            right_lane_error <=
                tuning.tine_lateral_tolerance and
            left_in_entry and
            right_in_entry and
            insertion_depth >= tuning.minimum_insertion,
        .angle_error_rad = angle_error,
        .insertion_depth = insertion_depth,
        .entry_heading_rad = entry_heading,
    };
}

const PalletLocal = struct {
    lateral: f32,
    longitudinal: f32,
};

fn worldToPalletLocal(
    point: math2.Vec2,
    pallet_position: math2.Vec2,
    entry_heading_rad: f32,
) PalletLocal {
    const delta = math2.sub(point, pallet_position);
    const forward =
        math2.forwardVector(entry_heading_rad);
    const right = math2.Vec2{
        .x = @cos(entry_heading_rad),
        .y = @sin(entry_heading_rad),
    };
    return .{
        .lateral = math2.dot(delta, right),
        .longitudinal = math2.dot(delta, forward),
    };
}
pub fn tryPickup(
    pallet: *Pallet,
    forklift: vehicle.Forklift,
    tuning: PickupTuning,
) bool {
    if (!evaluateForkEntry(forklift, pallet.*, tuning).valid) {
        return false;
    }

    const anchor = forkAnchor(forklift);
    const forward =
        math2.forwardVector(forklift.heading_rad);
    const right = math2.Vec2{
        .x = @cos(forklift.heading_rad),
        .y = @sin(forklift.heading_rad),
    };
    const delta = math2.sub(pallet.position, anchor);

    pallet.carry_offset = .{
        .x = math2.dot(delta, right),
        .y = math2.dot(delta, forward),
    };
    pallet.state = .carried;
    pallet.z = pallet.carry_z;
    pallet.support_z = 0;
    return true;
}

pub fn followForks(
    pallet: *Pallet,
    forklift: vehicle.Forklift,
) void {
    const forward =
        math2.forwardVector(forklift.heading_rad);
    const right = math2.Vec2{
        .x = @cos(forklift.heading_rad),
        .y = @sin(forklift.heading_rad),
    };

    pallet.position = math2.add(
        forkAnchor(forklift),
        math2.add(
            math2.scale(right, pallet.carry_offset.x),
            math2.scale(forward, pallet.carry_offset.y),
        ),
    );
    pallet.heading_rad = forklift.heading_rad;
}

pub fn drop(pallet: *Pallet) void {
    dropAt(pallet, 0);
}

pub fn dropAt(pallet: *Pallet, support_z: f32) void {
    pallet.state = .floor;
    pallet.support_z = support_z;
    pallet.z = support_z;
}

fn forkAnchor(forklift: vehicle.Forklift) math2.Vec2 {
    const forks = vehicle.forkGeometry(forklift);

    return math2.scale(
        math2.add(forks.left_tip, forks.right_tip),
        0.5,
    );
}

fn nearestEntryHeading(
    forklift_heading_rad: f32,
    pallet_heading_rad: f32,
) f32 {
    const turns = [_]f32{
        0,
        std.math.pi / 2.0,
        std.math.pi,
        3.0 * std.math.pi / 2.0,
    };

    var best_heading = pallet_heading_rad;
    var best_error = std.math.inf(f32);

    for (turns) |turn| {
        const candidate = math2.wrapAngle(pallet_heading_rad + turn);
        const err = @abs(math2.shortestAngleDifference(
            forklift_heading_rad,
            candidate,
        ));

        if (err < best_error) {
            best_heading = candidate;
            best_error = err;
        }
    }
    return best_heading;
}

test "aligned forks enter pallet" {
    const forklift = vehicle.Forklift{
        .position = .{ .x = 600, .y = 377 },
    };
    const pallet = Pallet{
        .position = .{ .x = 600, .y = 330 },
    };

    const result = evaluateForkEntry(forklift, pallet, .{
        .max_angle_error_rad = 0.4,
        .tine_lateral_tolerance = 3,
        .minimum_insertion = 18,
    });

    try std.testing.expect(result.valid);
}

test "forks enter pallet from its right side" {
    const forklift = vehicle.Forklift{
        .position = .{
            .x = 647.44,
            .y = 330,
        },
        .heading_rad = 3.0 * std.math.pi / 2.0,
    };
    const pallet = Pallet{
        .position = .{ .x = 600, .y = 330 },
    };

    try std.testing.expect(evaluateForkEntry(
        forklift,
        pallet,
        .{
            .max_angle_error_rad = 0.4,
            .tine_lateral_tolerance = 3,
            .minimum_insertion = 18,
        },
    ).valid);
}
