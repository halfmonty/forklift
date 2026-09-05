const std = @import("std");
const config = @import("../config.zig");
const math2 = @import("../sim/math2.zig");

pub const View = enum(u2) {
    north,
    east,
    south,
    west,
};

pub const Camera = struct {
    position: math2.Vec2 = .{ .x = 0, .y = 0 },
    view: View = .north,
};

pub const WorldBounds = struct {
    min: math2.Vec2,
    max: math2.Vec2,
};

pub fn visibleWorldBounds(camera: Camera) WorldBounds {
    const half = halfExtents(camera.view);

    return .{
        .min = camera.position,
        .max = .{
            .x = camera.position.x + half.x * 2,
            .y = camera.position.y + half.y * 2,
        },
    };
}

pub fn follow(
    camera: *Camera,
    target: math2.Vec2,
    world_size: math2.Vec2,
) void {
    const half = halfExtents(camera.view);

    camera.position = .{
        .x = clamp(
            target.x - half.x,
            0,
            world_size.x - half.x * 2,
        ),
        .y = clamp(
            target.y - half.y,
            0,
            world_size.y - half.y * 2,
        ),
    };
}

pub fn rotateClockwise(camera: *Camera) void {
    camera.view = switch (camera.view) {
        .north => .east,
        .east => .south,
        .south => .west,
        .west => .north,
    };
}

pub fn worldToScreen(
    world_position: math2.Vec2,
    camera: Camera,
) math2.Vec2 {
    const half = halfExtents(camera.view);
    const focus = math2.add(camera.position, half);
    const delta = math2.sub(world_position, focus);

    const rotated = switch (camera.view) {
        .north => delta,
        .east => math2.Vec2{ .x = -delta.y, .y = delta.x },
        .south => math2.Vec2{ .x = -delta.x, .y = -delta.y },
        .west => math2.Vec2{ .x = delta.y, .y = -delta.x },
    };

    return math2.add(
        rotated,
        .{
            .x = config.screen_width * 0.5,
            .y = config.screen_height * 0.5,
        },
    );
}

pub fn depth(
    world_position: math2.Vec2,
    camera: Camera,
) f32 {
    return worldToScreen(world_position, camera).y;
}

fn halfExtents(view: View) math2.Vec2 {
    return switch (view) {
        .north, .south => .{
            .x = config.screen_width * 0.5,
            .y = config.screen_height * 0.5,
        },
        .east, .west => .{
            .x = config.screen_height * 0.5,
            .y = config.screen_width * 0.5,
        },
    };
}

fn clamp(value: f32, minimum: f32, maximum: f32) f32 {
    return @max(minimum, @min(value, maximum));
}

test "north camera centers target" {
    var camera = Camera{};
    follow(&camera, .{ .x = 600, .y = 400 }, .{ .x = 1200, .y = 800 });

    const screen = worldToScreen(.{ .x = 600, .y = 400 }, camera);
    try std.testing.expectApproxEqAbs(@as(f32, 200), screen.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 120), screen.y, 0.001);
}

test "east camera rotates world clockwise" {
    var camera = Camera{};
    rotateClockwise(&camera);
    follow(&camera, .{ .x = 600, .y = 400 }, .{ .x = 1200, .y = 800 });

    const screen = worldToScreen(.{ .x = 700, .y = 400 }, camera);
    try std.testing.expectApproxEqAbs(@as(f32, 200), screen.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 220), screen.y, 0.001);
}

test "follow clamps to the selected world size" {
    var camera = Camera{};
    follow(&camera, .{ .x = 2400, .y = 1600 }, .{ .x = 2400, .y = 1600 });

    try std.testing.expectApproxEqAbs(@as(f32, 2000), camera.position.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1360), camera.position.y, 0.001);
}
