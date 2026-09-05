const std = @import("std");

pub const Vec2 = struct {
    x: f32,
    y: f32,
};

pub const tau: f32 = 2.0 * std.math.pi;

pub fn add(a: Vec2, b: Vec2) Vec2 {
    return .{ .x = a.x + b.x, .y = a.y + b.y };
}

pub fn sub(a: Vec2, b: Vec2) Vec2 {
    return .{ .x = a.x - b.x, .y = a.y - b.y };
}

pub fn scale(v: Vec2, amount: f32) Vec2 {
    return .{ .x = v.x * amount, .y = v.y * amount };
}

pub fn forwardVector(heading_rad: f32) Vec2 {
    return .{
        .x = @sin(heading_rad),
        .y = -@cos(heading_rad),
    };
}

pub fn wrapAngle(angle_rad: f32) f32 {
    var result = angle_rad;
    while (result < 0) result += tau;
    while (result >= tau) result -= tau;
    return result;
}

pub fn degreesToRadians(degrees: f32) f32 {
    return degrees * std.math.pi / 180.0;
}

pub fn dot(a: Vec2, b: Vec2) f32 {
    return a.x * b.x + a.y * b.y;
}

pub fn shortestAngleDifference(from: f32, to: f32) f32 {
    var difference = wrapAngle(to - from);
    if (difference > std.math.pi) difference -= tau;
    return difference;
}

test "forward vector convention" {
    const forward = forwardVector(0);
    try std.testing.expectApproxEqAbs(@as(f32, 0), forward.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, -1), forward.y, 0.0001);
}

test "wrap angle handles negative and multiple turns" {
    try std.testing.expectApproxEqAbs(
        @as(f32, std.math.pi),
        wrapAngle(-std.math.pi),
        0.0001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        wrapAngle(2.0 * tau),
        0.0001,
    );
}
