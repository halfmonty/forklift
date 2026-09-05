const cargo = @import("cargo.zig");
const collision = @import("collision.zig");
const math2 = @import("math2.zig");
const render = @import("render.zig");
const vehicle = @import("vehicle.zig");

pub const DrawPhase = enum {
    before_actors,
    after_actors,
};

pub const Rack = struct {
    bounds: collision.Rect,

    pub fn collisionRect(self: Rack) ?collision.Rect {
        return self.bounds;
    }

    pub fn draw(
        self: Rack,
        renderer: *render.Renderer,
        phase: DrawPhase,
        actor_depth: f32,
    ) void {
        switch (phase) {
            .before_actors => {
                renderer.rackBack(self.bounds);
                if (actor_depth >= renderer.rackFrontDepth(self.bounds)) {
                    renderer.rackFront(self.bounds);
                }
            },
            .after_actors => {
                if (actor_depth < renderer.rackFrontDepth(self.bounds)) {
                    renderer.rackFront(self.bounds);
                }
            },
        }
    }
};

pub const Obstacle = struct {
    bounds: collision.Rect,

    pub fn collisionRect(self: Obstacle) ?collision.Rect {
        return self.bounds;
    }

    pub fn draw(
        self: Obstacle,
        renderer: *render.Renderer,
        phase: DrawPhase,
        actor_depth: f32,
    ) void {
        _ = actor_depth;
        if (phase == .before_actors) {
            renderer.obstacle(self.bounds);
        }
    }
};

pub const Shelf = struct {
    zone: collision.Rect,
    support_z: f32,

    pub fn collisionRect(_: Shelf) ?collision.Rect {
        return null;
    }

    pub fn draw(
        self: Shelf,
        renderer: *render.Renderer,
        phase: DrawPhase,
        actor_depth: f32,
    ) void {
        _ = actor_depth;
        if (phase == .before_actors) {
            renderer.shelf(self.zone, self.support_z);
        }
    }
};

pub const Cone = struct {
    position: math2.Vec2,

    pub fn collisionRect(_: Cone) ?collision.Rect {
        return null;
    }

    pub fn draw(
        self: Cone,
        renderer: *render.Renderer,
        phase: DrawPhase,
        actor_depth: f32,
    ) void {
        _ = actor_depth;
        if (phase == .before_actors) {
            renderer.cone(self.position);
        }
    }
};

pub const TallBox = struct {
    position: math2.Vec2,

    pub fn collisionRect(_: TallBox) ?collision.Rect {
        return null;
    }

    pub fn draw(
        self: TallBox,
        renderer: *render.Renderer,
        phase: DrawPhase,
        actor_depth: f32,
    ) void {
        _ = actor_depth;
        if (phase == .before_actors) {
            renderer.tallBox(self.position);
        }
    }
};

pub fn StaticLevel(comptime objects: anytype) type {
    return struct {
        pub fn collides(
            _: @This(),
            forklift: vehicle.Forklift,
            carried: ?cargo.Pallet,
        ) bool {
            inline for (objects) |object| {
                if (object.collisionRect()) |rect| {
                    if (collision.obbOverlapsRect(
                        vehicle.bodyCollisionCenter(forklift),
                        vehicle.body_half_length,
                        vehicle.body_half_width,
                        forklift.heading_rad,
                        rect,
                    )) return true;

                    if (carried) |pallet| {
                        if (collision.obbOverlapsRect(
                            pallet.position,
                            pallet.footprint.half_length,
                            pallet.footprint.half_width,
                            pallet.heading_rad,
                            rect,
                        )) return true;
                    }
                }
            }
            return false;
        }

        pub fn draw(
            _: @This(),
            renderer: *render.Renderer,
            phase: DrawPhase,
            actor_depth: f32,
        ) void {
            inline for (objects) |object| {
                object.draw(renderer, phase, actor_depth);
            }
        }
    };
}

test "static level checks object collision" {
    const TestLevel = StaticLevel(.{
        Rack{
            .bounds = .{
                .x = 40,
                .y = 25,
                .width = 20,
                .height = 20,
            },
        },
        Cone{ .position = .{ .x = 100, .y = 100 } },
    });
    const test_level = TestLevel{};
    const forklift = vehicle.Forklift{
        .position = .{ .x = 50, .y = 50 },
    };

    try @import("std").testing.expect(
        test_level.collides(forklift, null),
    );
}
