const std = @import("std");
const config = @import("config.zig");
const math2 = @import("math2.zig");

pub const Camera = struct {
    position: math2.Vec2 = .{ .x = 0, .y = 0 },
};

pub fn follow(camera: *Camera, target: math2.Vec2) void {
    camera.position = .{
        .x = clamp(
            target.x - config.screen_width / 2.0,
            0,
            config.world_width - config.screen_width,
        ),
        .y = clamp(
            target.y - config.screen_height / 2.0,
            0,
            config.world_height - config.screen_height,
        ),
    };
}

pub fn worldToScreen(
    world_position: math2.Vec2,
    camera: Camera,
) math2.Vec2 {
    return math2.sub(world_position, camera.position);
}

fn clamp(value: f32, minimum: f32, maximum: f32) f32 {
    return @max(minimum, @min(value, maximum));
}

test "camera centers and clamps target" {
    var camera = Camera{};

    follow(&camera, .{ .x = 600, .y = 400 });
    try std.testing.expectApproxEqAbs(@as(f32, 400), camera.position.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 280), camera.position.y, 0.001);

    follow(&camera, .{ .x = 0, .y = 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 0), camera.position.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), camera.position.y, 0.001);
}
