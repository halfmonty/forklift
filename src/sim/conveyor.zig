const collision = @import("collision.zig");
const math2 = @import("math2.zig");
pub const Conveyor = struct {
    bounds: collision.Rect,
    direction: math2.Vec2,
    speed: f32,
};
