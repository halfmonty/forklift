const std = @import("std");
const math2 = @import("math2.zig");
const config = @import("../config.zig");

pub const body_front_extent: f32 = 20;
pub const body_rear_extent: f32 = 14;
pub const body_half_width: f32 = 11;
pub const body_half_length: f32 = (body_front_extent + body_rear_extent) * 0.5;

pub fn bodyCenter(forklift: Forklift) math2.Vec2 {
    return math2.add(
        forklift.position,
        math2.scale(
            math2.forwardVector(forklift.heading_rad),
            config.wheelbase * 0.48,
        ),
    );
}

pub fn bodyCollisionCenter(forklift: Forklift) math2.Vec2 {
    return math2.add(
        bodyCenter(forklift),
        math2.scale(
            math2.forwardVector(forklift.heading_rad),
            (body_front_extent - body_rear_extent) * 0.5,
        ),
    );
}

pub const InputState = struct {
    crank_delta_deg: f32,
    steering_ratio: SteeringRatio,
    forward: bool,
    reverse: bool,
};

pub const SteeringRatio = enum {
    low,
    medium,
    high,

    pub fn wheelAngleMultiplier(self: SteeringRatio) f32 {
        return switch (self) {
            .low => 1.0 / 8.0,
            .medium => 1.0 / 4.0,
            .high => 1.0,
        };
    }

    pub fn fromMenuValue(value: c_int) SteeringRatio {
        return switch (value) {
            0 => .low,
            1 => .medium,
            2 => .high,
            else => .low,
        };
    }
};

pub const ForkHeight = enum(c_int) {
    floor = 0,
    carry = 12,
    rack_low = 30,
};

pub fn forkZ(height: ForkHeight) f32 {
    return @floatFromInt(@intFromEnum(height));
}

pub fn raiseForks(forklift: *Forklift) void {
    forklift.fork_height = switch (forklift.fork_height) {
        .floor => .carry,
        .carry => .rack_low,
        .rack_low => .rack_low,
    };
}

pub fn lowerForks(forklift: *Forklift) void {
    forklift.fork_height = switch (forklift.fork_height) {
        .floor => .floor,
        .carry => .floor,
        .rack_low => .carry,
    };
}

pub const Forklift = struct {
    position: math2.Vec2,
    heading_rad: f32 = 0,
    steer_angle_rad: f32 = 0,
    speed: f32 = 0,
    fork_height: ForkHeight = .floor,

    pub fn reset(self: *Forklift, position: math2.Vec2) void {
        self.* = .{ .position = position };
    }
};

pub const ForkGeometry = struct {
    left_base: math2.Vec2,
    left_tip: math2.Vec2,
    right_base: math2.Vec2,
    right_tip: math2.Vec2,
};

pub fn forkGeometry(forklift: Forklift) ForkGeometry {
    const forward = math2.forwardVector(forklift.heading_rad);
    const right = math2.Vec2{
        .x = @cos(forklift.heading_rad),
        .y = @sin(forklift.heading_rad),
    };

    const body_center = math2.add(
        forklift.position,
        math2.scale(forward, config.wheelbase * 0.48),
    );
    const fork_base_center = math2.add(
        body_center,
        math2.scale(forward, 20),
    );
    const fork_spacing = math2.scale(right, 5);
    const fork_length = math2.scale(forward, 22);

    const left_base = math2.sub(fork_base_center, fork_spacing);
    const right_base = math2.add(fork_base_center, fork_spacing);

    return .{
        .left_base = left_base,
        .left_tip = math2.add(left_base, fork_length),
        .right_base = right_base,
        .right_tip = math2.add(right_base, fork_length),
    };
}

pub fn curvature(steer_angle_rad: f32) f32 {
    return @sin(steer_angle_rad) / config.wheelbase;
}

pub fn update(
    forklift: *Forklift,
    input: InputState,
    acceleration_multiplier: f32,
    dt: f32,
) void {
    forklift.steer_angle_rad = math2.wrapAngle(
        forklift.steer_angle_rad +
            math2.degreesToRadians(input.crank_delta_deg) *
                input.steering_ratio.wheelAngleMultiplier(),
    );

    const desired_speed: f32 = if (input.forward and !input.reverse)
        config.max_forward_speed
    else if (input.reverse and !input.forward)
        -config.max_reverse_speed
    else
        0;

    const rate: f32 = if (desired_speed == 0)
        config.coast_drag
    else if (forklift.speed * desired_speed < 0)
        config.braking
    else
        config.acceleration * acceleration_multiplier;

    forklift.speed = approach(forklift.speed, desired_speed, rate * dt);

    const rear_wheel_direction = rearWheelDirection(
        forklift.heading_rad,
        forklift.steer_angle_rad,
    );

    forklift.position = math2.add(
        forklift.position,
        math2.scale(rear_wheel_direction, forklift.speed *
            dt),
    );
    forklift.heading_rad = math2.wrapAngle(
        forklift.heading_rad +
            forklift.speed *
                curvature(forklift.steer_angle_rad) * dt,
    );
}

fn approach(value: f32, target: f32, max_delta: f32) f32 {
    if (value < target) return @min(value + max_delta, target);
    return @max(value - max_delta, target);
}

pub fn rearWheelDirection(
    heading_rad: f32,
    steer_angle_rad: f32,
) math2.Vec2 {
    const forward = math2.forwardVector(heading_rad);
    const right = math2.Vec2{
        .x = @cos(heading_rad),
        .y = @sin(heading_rad),
    };

    return math2.sub(
        math2.scale(forward, @cos(steer_angle_rad)),
        math2.scale(right, @sin(steer_angle_rad)),
    );
}

test "curvature is periodic and reverses direction" {
    try @import("std").testing.expectApproxEqAbs(
        @as(f32, 0),
        curvature(0),
        0.0001,
    );
    try @import("std").testing.expect(curvature(std.math.pi /
        2.0) > 0);
    try @import("std").testing.expect(curvature(3.0 *
        std.math.pi / 2.0) < 0);
}

test "fork geometry faces body heading" {
    const forklift = Forklift{
        .position = .{ .x = 100, .y = 100 },
    };
    const forks = forkGeometry(forklift);

    try @import("std").testing.expect(forks.left_tip.y <
        forks.left_base.y);
    try @import("std").testing.expect(forks.right_tip.y <
        forks.right_base.y);
    try @import("std").testing.expect(forks.left_base.x <
        forks.right_base.x);
}

test "steering ratios match their crank-to-wheel rotation ratios" {
    try @import("std").testing.expectApproxEqAbs(@as(f32, 1.0 / 3.0), SteeringRatio.low.wheelAngleMultiplier(), 0.0001);
    try @import("std").testing.expectApproxEqAbs(@as(f32, 1.0 / 2.0), SteeringRatio.medium.wheelAngleMultiplier(), 0.0001);
    try @import("std").testing.expectApproxEqAbs(@as(f32, 1.0), SteeringRatio.high.wheelAngleMultiplier(), 0.0001);
}
