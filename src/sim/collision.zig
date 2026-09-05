const std = @import("std");
const math2 = @import("math2.zig");

pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub fn circleOverlapsRect(
    center: math2.Vec2,
    radius: f32,
    rect: Rect,
) bool {
    const closest_x = clamp(center.x, rect.x, rect.x + rect.width);
    const closest_y = clamp(center.y, rect.y, rect.y + rect.height);
    const dx = center.x - closest_x;
    const dy = center.y - closest_y;

    return dx * dx + dy * dy <= radius * radius;
}

fn clamp(value: f32, minimum: f32, maximum: f32) f32 {
    return @max(minimum, @min(value, maximum));
}

pub fn obbOverlapsRect(
    center: math2.Vec2,
    half_length: f32,
    half_width: f32,
    heading_rad: f32,
    rect: Rect,
) bool {
    const forward = math2.forwardVector(heading_rad);
    const right = math2.Vec2{
        .x = @cos(heading_rad),
        .y = @sin(heading_rad),
    };
    const rect_center = math2.Vec2{
        .x = rect.x + rect.width * 0.5,
        .y = rect.y + rect.height * 0.5,
    };
    const delta = math2.sub(rect_center, center);

    const axes = [_]math2.Vec2{ .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 1 }, forward, right };

    for (axes) |axis| {
        const pallet_radius =
            half_length * @abs(math2.dot(forward, axis)) +
            half_width * @abs(math2.dot(right, axis));
        const rect_radius =
            rect.width * 0.5 * @abs(axis.x) +
            rect.height * 0.5 * @abs(axis.y);
        const center_distance = @abs(math2.dot(delta, axis));

        if (center_distance > pallet_radius + rect_radius) {
            return false;
        }
    }
    return true;
}

pub fn obbContainedInRect(
    center: math2.Vec2,
    half_length: f32,
    half_width: f32,
    heading_rad: f32,
    rect: Rect,
) bool {
    const forward = math2.forwardVector(heading_rad);
    const right = math2.Vec2{
        .x = @cos(heading_rad),
        .y = @sin(heading_rad),
    };

    const front = math2.scale(forward, half_length);
    const side = math2.scale(right, half_width);
    const corners = [_]math2.Vec2{
        math2.sub(math2.add(center, front), side),
        math2.add(math2.add(center, front), side),
        math2.sub(math2.sub(center, front), side),
        math2.add(math2.sub(center, front), side),
    };

    for (corners) |corner| {
        if (corner.x < rect.x or
            corner.x > rect.x + rect.width or
            corner.y < rect.y or
            corner.y > rect.y + rect.height)
        {
            return false;
        }
    }

    return true;
}

test "circle overlaps rectangle" {
    const rect = Rect{ .x = 10, .y = 10, .width = 20, .height = 20 };

    try std.testing.expect(circleOverlapsRect(
        .{ .x = 8, .y = 20 },
        3,
        rect,
    ));
    try std.testing.expect(!circleOverlapsRect(
        .{ .x = 5, .y = 20 },
        3,
        rect,
    ));
}

test "oriented pallet contacts rack face without circle gap" {
    const rack = Rect{
        .x = 20,
        .y = 0,
        .width = 10,
        .height = 10,
    };

    try std.testing.expect(!obbOverlapsRect(
        .{ .x = 5, .y = 5 },
        14,
        14,
        std.math.pi / 2.0,
        rack,
    ));
    try std.testing.expect(obbOverlapsRect(
        .{ .x = 6, .y = 5 },
        14,
        14,
        std.math.pi / 2.0,
        rack,
    ));
}
