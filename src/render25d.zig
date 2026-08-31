const std = @import("std");
const camera = @import("camera.zig");
const math2 = @import("math2.zig");
const config = @import("config.zig");

pub const ProjectionTuning = struct {
    z_skew_x: f32,
    z_skew_y: f32,
    perspective_strength: f32,
};

pub fn project(
    world_position: math2.Vec2,
    z: f32,
    camera_state: camera.Camera,
    tuning: ProjectionTuning,
) math2.Vec2 {
    const ground = math2.Vec2{
        .x = world_position.x - camera_state.position.x,
        .y = world_position.y - camera_state.position.y,
    };
    const perspective_scale = z * tuning.perspective_strength;
    return .{
        .x = ground.x +
            z * tuning.z_skew_x +
            (ground.x - config.screen_width * 0.5) *
                perspective_scale,
        .y = ground.y -
            z * tuning.z_skew_y +
            (ground.y - config.screen_height * 0.5) *
                perspective_scale,
    };
}

test "z projects upward" {
    const result = project(
        .{ .x = 100, .y = 100 },
        12,
        .{},
        .{ .z_skew_x = 0, .z_skew_y = 0.75, .perspective_strength = 0 },
    );

    try std.testing.expectApproxEqAbs(@as(f32, 100), result.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 91), result.y, 0.001);
}
