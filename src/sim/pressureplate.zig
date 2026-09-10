const collision = @import("collision.zig");
const math2 = @import("math2.zig");

pub const PressurePlate = struct {
    bounds: collision.Rect,
    gate_index: usize,
};

pub const Gate = struct {
    bounds: collision.Rect,
};
