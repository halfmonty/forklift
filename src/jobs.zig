const std = @import("std");
const cargo = @import("cargo.zig");
const collision = @import("collision.zig");
const math2 = @import("math2.zig");

pub const JobDefinition = struct {
    pallet_spawn: math2.Vec2,
    destination: collision.Rect,
    cargo: cargo.CargoDef,
};

pub const JobState = enum {
    waiting_for_pickup,
    carrying,
    delivered,
};

pub fn update(
    current: JobState,
    pallet: cargo.Pallet,
    destination: collision.Rect,
) JobState {
    if (current == .delivered) return .delivered;
    if (pallet.state == .carried) return .carrying;

    if (current == .carrying and
        collision.obbContainedInRect(
            pallet.position,
            pallet.footprint.half_length,
            pallet.footprint.half_width,
            pallet.heading_rad,
            destination,
        ))
    {
        return .delivered;
    }

    return .waiting_for_pickup;
}

test "dropped pallet inside destination delivers job" {
    const pallet = cargo.Pallet{
        .position = .{ .x = 50, .y = 50 },
    };
    const destination = collision.Rect{
        .x = 30,
        .y = 30,
        .width = 40,
        .height = 40,
    };

    try std.testing.expectEqual(
        JobState.delivered,
        update(.carrying, pallet, destination),
    );
}
