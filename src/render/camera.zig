const std = @import("std");
const config = @import("../config.zig");
const math2 = @import("../sim/math2.zig");

pub const CardinalView = enum(u2) {
    north,
    east,
    south,
    west,
};

pub const Camera = struct {
    focus: math2.Vec2 = .{ .x = 0, .y = 0 },
    yaw_rad: f32 = 0,
};

pub const WorldBounds = struct {
    min: math2.Vec2,
    max: math2.Vec2,
};

pub fn visibleWorldBounds(camera: Camera) WorldBounds {
    const offsets = visibleWorldOffsets(camera.yaw_rad);

    return .{
        .min = math2.add(camera.focus, offsets.min),
        .max = math2.add(camera.focus, offsets.max),
    };
}

pub fn follow(
    camera: *Camera,
    target: math2.Vec2,
    world_size: math2.Vec2,
) void {
    const offsets = visibleWorldOffsets(camera.yaw_rad);

    camera.focus = .{
        .x = clampOrCenter(
            target.x,
            -offsets.min.x,
            world_size.x - offsets.max.x,
        ),
        .y = clampOrCenter(
            target.y,
            -offsets.min.y,
            world_size.y - offsets.max.y,
        ),
    };
}

pub fn worldToScreen(
    world_position: math2.Vec2,
    camera: Camera,
) math2.Vec2 {
    const delta = math2.sub(world_position, camera.focus);
    const cosine = @cos(camera.yaw_rad);
    const sine = @sin(camera.yaw_rad);

    return .{
        .x = config.screen_width * 0.5 +
            cosine * delta.x - sine * delta.y,
        .y = config.screen_height * 0.5 +
            sine * delta.x + cosine * delta.y,
    };
}

pub fn snapTo(
    camera: *Camera,
    view: CardinalView,
) void {
    camera.yaw_rad = switch (view) {
        .north => 0,
        .east => std.math.pi / 2.0,
        .south => std.math.pi,
        .west => 3.0 * std.math.pi / 2.0,
    };
}

pub fn rotateBy(
    camera: *Camera,
    delta_rad: f32,
) void {
    camera.yaw_rad = math2.wrapAngle(camera.yaw_rad + delta_rad);
}

pub fn depth(
    world_position: math2.Vec2,
    camera: Camera,
) f32 {
    return worldToScreen(world_position, camera).y;
}

fn visibleWorldOffsets(yaw_rad: f32) WorldBounds {
    const half_screen = math2.Vec2{
        .x = config.screen_width * 0.5,
        .y = config.screen_height * 0.5,
    };

    const screen_corners = [_]math2.Vec2{
        .{ .x = -half_screen.x, .y = -half_screen.y },
        .{ .x = half_screen.x, .y = -half_screen.y },
        .{ .x = half_screen.x, .y = half_screen.y },
        .{ .x = -half_screen.x, .y = half_screen.y },
    };

    var minimum = screenOffsetToWorld(screen_corners[0], yaw_rad);
    var maximum = minimum;

    for (screen_corners[1..]) |corner| {
        const world_offset = screenOffsetToWorld(corner, yaw_rad);
        minimum.x = @min(minimum.x, world_offset.x);
        minimum.y = @min(minimum.y, world_offset.y);
        maximum.x = @max(maximum.x, world_offset.x);
        maximum.y = @max(maximum.y, world_offset.y);
    }

    return .{
        .min = minimum,
        .max = maximum,
    };
}

fn screenOffsetToWorld(
    screen_offset: math2.Vec2,
    yaw_rad: f32,
) math2.Vec2 {
    const cosine = @cos(yaw_rad);
    const sine = @sin(yaw_rad);

    return .{
        .x = cosine * screen_offset.x + sine * screen_offset.y,
        .y = -sine * screen_offset.x + cosine * screen_offset.y,
    };
}

fn clampOrCenter(
    value: f32,
    minimum: f32,
    maximum: f32,
) f32 {
    if (minimum > maximum) return (minimum + maximum) * 0.5;
    return clamp(value, minimum, maximum);
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
    snapTo(&camera, .east);
    follow(&camera, .{ .x = 600, .y = 400 }, .{ .x = 1200, .y = 800 });

    const screen = worldToScreen(.{ .x = 700, .y = 400 }, camera);
    try std.testing.expectApproxEqAbs(@as(f32, 200), screen.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 220), screen.y, 0.001);
}

test "follow clamps to the selected world size" {
    var camera = Camera{};
    follow(&camera, .{ .x = 2400, .y = 1600 }, .{ .x = 2400, .y = 1600 });

    try std.testing.expectApproxEqAbs(@as(f32, 2200), camera.focus.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1480), camera.focus.y, 0.001);
}

test "arbitrary yaw rotates around camera focus" {
    const camera = Camera{
        .focus = .{ .x = 600, .y = 400 },
        .yaw_rad = std.math.pi / 4.0,
    };
    const screen = worldToScreen(.{ .x = 700, .y = 400 }, camera);
    const offset: f32 = 100.0 / @sqrt(@as(f32, 2));

    try std.testing.expectApproxEqAbs(@as(f32, 200) + offset, screen.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 120) + offset, screen.y, 0.001);
}

test "visible bounds contain every inverse-projected screen corner" {
    const camera = Camera{
        .focus = .{ .x = 600, .y = 400 },
        .yaw_rad = std.math.pi / 4.0,
    };
    const bounds = visibleWorldBounds(camera);
    const half_screen = math2.Vec2{
        .x = config.screen_width * 0.5,
        .y = config.screen_height * 0.5,
    };
    const screen_corners = [_]math2.Vec2{
        .{ .x = -half_screen.x, .y = -half_screen.y },
        .{ .x = half_screen.x, .y = -half_screen.y },
        .{ .x = half_screen.x, .y = half_screen.y },
        .{ .x = -half_screen.x, .y = half_screen.y },
    };

    for (screen_corners) |corner| {
        const world_corner = math2.add(
            camera.focus,
            screenOffsetToWorld(corner, camera.yaw_rad),
        );
        try std.testing.expect(world_corner.x >= bounds.min.x - 0.001);
        try std.testing.expect(world_corner.x <= bounds.max.x + 0.001);
        try std.testing.expect(world_corner.y >= bounds.min.y - 0.001);
        try std.testing.expect(world_corner.y <= bounds.max.y + 0.001);
    }
}

test "rotateBy wraps continuous yaw" {
    var camera = Camera{};
    rotateBy(&camera, 2.0 * std.math.pi + std.math.pi / 4.0);

    try std.testing.expectApproxEqAbs(
        std.math.pi / 4.0,
        camera.yaw_rad,
        0.001,
    );
}
