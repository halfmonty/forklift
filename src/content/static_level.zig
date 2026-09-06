const std = @import("std");
const cargo = @import("../sim/cargo.zig");
const collision = @import("../sim/collision.zig");
const math2 = @import("../sim/math2.zig");
const render = @import("../render/renderer.zig");
const compositor = @import("../render/compositor.zig");
const vehicle = @import("../sim/vehicle.zig");

pub const DrawPhase = enum {
    before_actors,
    after_actors,
};

pub const FloorExpansionJoints = struct {
    world_size: math2.Vec2,
    cell_size: math2.Vec2,

    pub fn collisionRect(_: FloorExpansionJoints) ?collision.Rect {
        return null;
    }

    pub fn draw(
        self: FloorExpansionJoints,
        renderer: *render.Renderer,
        phase: DrawPhase,
        actor_depth: f32,
    ) void {
        _ = actor_depth;
        if (phase == .before_actors) {
            renderer.floorExpansionJoints(self.world_size, self.cell_size);
        }
    }
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
                renderer.rackFront(self.bounds, actor_depth, true);
            },
            .after_actors => {
                renderer.rackFront(self.bounds, actor_depth, false);
            },
        }
    }
};

pub const StorageRackLevel = enum {
    low,
    high,
};

pub const StorageRack = struct {
    bounds: collision.Rect,
    level: StorageRackLevel,

    pub fn collisionRect(self: StorageRack) ?collision.Rect {
        return self.bounds;
    }

    pub fn draw(
        self: StorageRack,
        renderer: *render.Renderer,
        phase: DrawPhase,
        actor_depth: f32,
    ) void {
        _ = actor_depth;
        _ = self;
        _ = renderer;
        _ = phase;
    }

    pub fn emitOpaqueSurfaces(
        self: StorageRack,
        collector: *compositor.OpaqueSurfaceCollector,
    ) void {
        collector.append(.{
            .bounds = self.bounds,
            .support_z = vehicle.forkZ(.rack_low),
        });
        if (self.level == .high) {
            collector.append(.{
                .bounds = self.bounds,
                .support_z = vehicle.forkZ(.rack_high),
            });
        }
    }

    pub fn dropSupport(
        self: StorageRack,
        fork_height: vehicle.ForkHeight,
        pallet: cargo.Pallet,
    ) ?f32 {
        if (!palletFitsZone(pallet, self.bounds)) return null;

        return switch (fork_height) {
            .rack_low => vehicle.forkZ(.rack_low),
            .rack_high => if (self.level == .high)
                vehicle.forkZ(.rack_high)
            else
                null,
            else => null,
        };
    }

    pub fn blocksCarriedCargo(_: StorageRack) bool {
        return false;
    }

    pub fn blocksForkLowering(
        self: StorageRack,
        forklift: vehicle.Forklift,
        carried: ?cargo.Pallet,
        from_height: vehicle.ForkHeight,
        to_height: vehicle.ForkHeight,
    ) bool {
        const crosses_low_shelf = crossesShelf(
            from_height,
            to_height,
            .rack_low,
        );
        const crosses_high_shelf = self.level == .high and
            crossesShelf(from_height, to_height, .rack_high);

        if (!crosses_low_shelf and !crosses_high_shelf) return false;

        if (vehicle.forksOverlapRect(forklift, self.bounds)) return true;

        if (carried) |pallet| {
            return collision.obbOverlapsRect(
                pallet.position,
                pallet.footprint.half_length,
                pallet.footprint.half_width,
                pallet.heading_rad,
                self.bounds,
            );
        }

        return false;
    }

    pub fn blocksForkRaising(
        self: StorageRack,
        forklift: vehicle.Forklift,
        carried: ?cargo.Pallet,
        from_height: vehicle.ForkHeight,
        to_height: vehicle.ForkHeight,
    ) bool {
        const crosses_low_shelf = crossesShelfUp(
            from_height,
            to_height,
            .rack_low,
        );
        const crosses_high_shelf = self.level == .high and
            crossesShelfUp(from_height, to_height, .rack_high);

        if (!crosses_low_shelf and !crosses_high_shelf) return false;

        if (vehicle.forksOverlapRect(forklift, self.bounds)) return true;

        if (carried) |pallet| {
            return collision.obbOverlapsRect(
                pallet.position,
                pallet.footprint.half_length,
                pallet.footprint.half_width,
                pallet.heading_rad,
                self.bounds,
            );
        }

        return false;
    }

    fn crossesShelf(
        from_height: vehicle.ForkHeight,
        to_height: vehicle.ForkHeight,
        shelf_height: vehicle.ForkHeight,
    ) bool {
        return vehicle.forkZ(from_height) >= vehicle.forkZ(shelf_height) and
            vehicle.forkZ(to_height) < vehicle.forkZ(shelf_height);
    }

    fn crossesShelfUp(
        from_height: vehicle.ForkHeight,
        to_height: vehicle.ForkHeight,
        shelf_height: vehicle.ForkHeight,
    ) bool {
        return vehicle.forkZ(from_height) < vehicle.forkZ(shelf_height) and
            vehicle.forkZ(to_height) >= vehicle.forkZ(shelf_height);
    }
};

fn palletFitsZone(pallet: cargo.Pallet, zone: collision.Rect) bool {
    return collision.obbContainedInRect(
        pallet.position,
        pallet.footprint.half_length,
        pallet.footprint.half_width,
        pallet.heading_rad,
        zone,
    );
}

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
        _ = self;
        _ = renderer;
        _ = phase;
    }

    pub fn emitOpaqueSurfaces(
        self: Shelf,
        collector: *compositor.OpaqueSurfaceCollector,
    ) void {
        collector.append(.{
            .bounds = self.zone,
            .support_z = self.support_z,
        });
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

                    const blocks_carried_cargo = if (@hasDecl(
                        @TypeOf(object),
                        "blocksCarriedCargo",
                    ))
                        object.blocksCarriedCargo()
                    else
                        true;

                    if (blocks_carried_cargo) {
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
            }
            return false;
        }

        pub fn blocksForkLowering(
            _: @This(),
            forklift: vehicle.Forklift,
            carried: ?cargo.Pallet,
            from_height: vehicle.ForkHeight,
            to_height: vehicle.ForkHeight,
        ) bool {
            inline for (objects) |object| {
                if (@hasDecl(@TypeOf(object), "blocksForkLowering")) {
                    if (object.blocksForkLowering(
                        forklift,
                        carried,
                        from_height,
                        to_height,
                    )) return true;
                }
            }
            return false;
        }

        pub fn blocksForkRaising(
            _: @This(),
            forklift: vehicle.Forklift,
            carried: ?cargo.Pallet,
            from_height: vehicle.ForkHeight,
            to_height: vehicle.ForkHeight,
        ) bool {
            inline for (objects) |object| {
                if (@hasDecl(@TypeOf(object), "blocksForkRaising")) {
                    if (object.blocksForkRaising(
                        forklift,
                        carried,
                        from_height,
                        to_height,
                    )) return true;
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

        pub fn collectOpaqueSurfaces(
            _: @This(),
            collector: *compositor.OpaqueSurfaceCollector,
        ) void {
            inline for (objects) |object| {
                if (@hasDecl(@TypeOf(object), "emitOpaqueSurfaces")) {
                    object.emitOpaqueSurfaces(collector);
                }
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

test "storage racks emit their configured opaque shelf surfaces" {
    var renderer_instance = render.Renderer{
        .playdate = undefined,
        .camera_state = .{},
        .cull_margin = 0,
    };
    var collector = compositor.OpaqueSurfaceCollector.init(&renderer_instance);
    const level = StaticLevel(.{
        StorageRack{
            .bounds = .{ .x = 0, .y = 0, .width = 56, .height = 140 },
            .level = .low,
        },
        StorageRack{
            .bounds = .{ .x = 100, .y = 0, .width = 56, .height = 140 },
            .level = .high,
        },
    }){};

    level.collectOpaqueSurfaces(&collector);

    try std.testing.expectEqual(@as(usize, 3), collector.len);
    try std.testing.expectEqual(vehicle.forkZ(.rack_low), collector.items[0].support_z);
    try std.testing.expectEqual(vehicle.forkZ(.rack_low), collector.items[1].support_z);
    try std.testing.expectEqual(vehicle.forkZ(.rack_high), collector.items[2].support_z);
}
