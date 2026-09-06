const std = @import("std");
const cargo = @import("../sim/cargo.zig");
const collision = @import("../sim/collision.zig");
const math2 = @import("../sim/math2.zig");
const vehicle = @import("../sim/vehicle.zig");
const camera = @import("camera.zig");
const renderer_module = @import("renderer.zig");

pub const max_opaque_surfaces = 64;
pub const pallet_top_z_offset: f32 = 6;

pub const OpaqueSurface = struct {
    bounds: collision.Rect,
    support_z: f32,
    sort_depth: f32 = 0,
};

pub const OpaqueSurfaceCollector = struct {
    renderer: *renderer_module.Renderer,
    items: [max_opaque_surfaces]OpaqueSurface = undefined,
    len: usize = 0,

    pub fn init(renderer: *renderer_module.Renderer) OpaqueSurfaceCollector {
        return .{ .renderer = renderer };
    }

    pub fn append(self: *OpaqueSurfaceCollector, surface: OpaqueSurface) void {
        if (!self.renderer.isRectVisible(surface.bounds)) return;
        if (self.len == self.items.len) {
            @panic("opaque surface collector capacity exceeded");
        }
        self.items[self.len] = surface;
        self.len += 1;
    }

    pub fn slice(self: *OpaqueSurfaceCollector) []OpaqueSurface {
        return self.items[0..self.len];
    }
};

pub const RenderPartKind = enum {
    forklift_base,
    forklift_mast,
    forklift_canopy,
    pallet,
    forklift_forks,
};

pub const RenderPart = struct {
    kind: RenderPartKind,
    depth: f32,
    occlusion_z: f32,
    local_order: u8,
};

pub const Compositor = struct {
    renderer: *renderer_module.Renderer,
    surfaces: []OpaqueSurface,

    pub fn init(
        renderer: *renderer_module.Renderer,
        surfaces: []OpaqueSurface,
    ) Compositor {
        return .{ .renderer = renderer, .surfaces = surfaces };
    }

    pub fn drawDynamic(
        self: *Compositor,
        forklift: vehicle.Forklift,
        pallet: cargo.Pallet,
    ) void {
        var sink = RendererSink{
            .renderer = self.renderer,
            .forklift = forklift,
            .pallet = pallet,
        };
        compose(
            forklift,
            pallet,
            self.surfaces,
            self.renderer.camera_state,
            &sink,
        );
    }
};

const RendererSink = struct {
    renderer: *renderer_module.Renderer,
    forklift: vehicle.Forklift,
    pallet: cargo.Pallet,

    pub fn drawSurface(self: *RendererSink, surface: OpaqueSurface) void {
        self.renderer.opaqueSurface(surface.bounds, surface.support_z);
    }

    pub fn drawPart(self: *RendererSink, part: RenderPart) void {
        switch (part.kind) {
            .forklift_base => self.renderer.forkliftBase(self.forklift),
            .forklift_mast => self.renderer.forkliftMast(self.forklift),
            .forklift_canopy => self.renderer.forkliftCanopy(self.forklift),
            .forklift_forks => self.renderer.forkliftForks(self.forklift),
            .pallet => {
                var pallet = self.pallet;
                pallet.z = part.occlusion_z;
                self.renderer.pallet(pallet);
            },
        }
    }
};

pub fn compose(
    forklift: vehicle.Forklift,
    pallet: cargo.Pallet,
    surfaces: []OpaqueSurface,
    camera_state: camera.Camera,
    sink: anytype,
) void {
    for (surfaces) |*surface| {
        surface.sort_depth = surfaceGroundDepth(surface.*, camera_state);
    }
    sortSurfaces(surfaces);
    var parts = dynamicParts(forklift, pallet, camera_state);
    sortParts(&parts);

    var surface_index: usize = 0;
    var part_index: usize = 0;
    while (surface_index < surfaces.len or part_index < parts.len) {
        const take_surface = surface_index < surfaces.len and
            (part_index == parts.len or
                surfaces[surface_index].sort_depth <= parts[part_index].depth);

        if (take_surface) {
            const surface = surfaces[surface_index];
            sink.drawSurface(surface);

            // The surface just covered all previously drawn lower geometry.
            // Replay only parts whose visible plane is at or above it.
            for (parts[0..part_index]) |part| {
                if (!surfaceOccludesPart(surface, part.occlusion_z)) {
                    sink.drawPart(part);
                }
            }
            surface_index += 1;
        } else {
            sink.drawPart(parts[part_index]);
            part_index += 1;
        }
    }
}

fn dynamicParts(
    forklift: vehicle.Forklift,
    pallet: cargo.Pallet,
    camera_state: camera.Camera,
) [5]RenderPart {
    const vehicle_depth = camera.depth(forklift.position, camera_state);
    const facing_camera = renderer_module.canopyBehindForks(forklift, camera_state);
    const pallet_z = (if (pallet.state == .carried) pallet.z else pallet.support_z) +
        pallet_top_z_offset;

    return .{
        .{
            .kind = .forklift_base,
            .depth = vehicle_depth,
            .occlusion_z = 0,
            .local_order = 0,
        },
        .{
            .kind = .forklift_canopy,
            .depth = vehicle_depth,
            .occlusion_z = 0,
            .local_order = if (facing_camera) 1 else 4,
        },
        .{
            .kind = .forklift_mast,
            .depth = vehicle_depth,
            .occlusion_z = 0,
            .local_order = if (facing_camera) 2 else 3,
        },
        .{
            .kind = .forklift_forks,
            .depth = vehicle_depth,
            .occlusion_z = vehicle.forkZ(forklift.fork_height),
            .local_order = if (facing_camera) 3 else 1,
        },
        .{
            .kind = .pallet,
            .depth = if (pallet.state == .carried)
                vehicle_depth
            else
                camera.depth(pallet.position, camera_state),
            .occlusion_z = pallet_z,
            .local_order = if (pallet.state == .carried)
                if (facing_camera) 4 else 2
            else
                0,
        },
    };
}

fn sortParts(parts: *[5]RenderPart) void {
    for (1..parts.len) |index| {
        const part = parts[index];
        var insertion = index;
        while (insertion > 0 and partBefore(part, parts[insertion - 1])) {
            parts[insertion] = parts[insertion - 1];
            insertion -= 1;
        }
        parts[insertion] = part;
    }
}

fn partBefore(left: RenderPart, right: RenderPart) bool {
    if (left.depth != right.depth) return left.depth < right.depth;
    return left.local_order < right.local_order;
}

fn sortSurfaces(surfaces: []OpaqueSurface) void {
    if (surfaces.len < 2) return;
    for (1..surfaces.len) |index| {
        const surface = surfaces[index];
        var insertion = index;
        while (insertion > 0 and surfaceBefore(surface, surfaces[insertion - 1])) {
            surfaces[insertion] = surfaces[insertion - 1];
            insertion -= 1;
        }
        surfaces[insertion] = surface;
    }
}

fn surfaceBefore(
    left: OpaqueSurface,
    right: OpaqueSurface,
) bool {
    if (left.sort_depth != right.sort_depth) return left.sort_depth < right.sort_depth;
    return left.support_z < right.support_z;
}

pub fn surfaceGroundDepth(surface: OpaqueSurface, camera_state: camera.Camera) f32 {
    const bounds = surface.bounds;
    return @max(
        @max(
            camera.depth(.{ .x = bounds.x, .y = bounds.y }, camera_state),
            camera.depth(.{ .x = bounds.x + bounds.width, .y = bounds.y }, camera_state),
        ),
        @max(
            camera.depth(.{ .x = bounds.x + bounds.width, .y = bounds.y + bounds.height }, camera_state),
            camera.depth(.{ .x = bounds.x, .y = bounds.y + bounds.height }, camera_state),
        ),
    );
}

pub fn surfaceOccludesPart(surface: OpaqueSurface, part_z: f32) bool {
    return part_z < surface.support_z;
}

test "opaque surface occludes only lower parts" {
    const surface = OpaqueSurface{
        .bounds = .{ .x = 0, .y = 0, .width = 10, .height = 10 },
        .support_z = vehicle.forkZ(.rack_low),
    };

    try std.testing.expect(surfaceOccludesPart(surface, vehicle.forkZ(.carry)));
    try std.testing.expect(!surfaceOccludesPart(surface, vehicle.forkZ(.rack_low)));
    try std.testing.expect(!surfaceOccludesPart(surface, vehicle.forkZ(.rack_high)));
}

const TestDraw = union(enum) {
    surface: f32,
    part: RenderPartKind,
};

const TestSink = struct {
    items: [64]TestDraw = undefined,
    len: usize = 0,

    pub fn drawSurface(self: *TestSink, surface: OpaqueSurface) void {
        self.items[self.len] = .{ .surface = surface.support_z };
        self.len += 1;
    }

    pub fn drawPart(self: *TestSink, part: RenderPart) void {
        self.items[self.len] = .{ .part = part.kind };
        self.len += 1;
    }
};

fn lastTestDrawIndex(items: []const TestDraw, expected: TestDraw) ?usize {
    var result: ?usize = null;
    for (items, 0..) |item, index| {
        if (std.meta.eql(item, expected)) result = index;
    }
    return result;
}

fn testDrawCount(items: []const TestDraw, expected: TestDraw) usize {
    var count: usize = 0;
    for (items) |item| {
        if (std.meta.eql(item, expected)) count += 1;
    }
    return count;
}

test "foreground forklift mast draws after rack surface" {
    var surfaces = [_]OpaqueSurface{.{
        .bounds = .{ .x = 80, .y = 80, .width = 40, .height = 20 },
        .support_z = vehicle.forkZ(.rack_low),
    }};
    const forklift = vehicle.Forklift{
        .position = .{ .x = 100, .y = 140 },
        .heading_rad = std.math.pi,
    };
    const pallet = cargo.Pallet{ .position = .{ .x = 300, .y = 300 } };
    var sink = TestSink{};

    compose(forklift, pallet, &surfaces, .{}, &sink);

    const surface_index = lastTestDrawIndex(
        sink.items[0..sink.len],
        .{ .surface = vehicle.forkZ(.rack_low) },
    ).?;
    const mast_index = lastTestDrawIndex(
        sink.items[0..sink.len],
        .{ .part = .forklift_mast },
    ).?;
    try std.testing.expect(surface_index < mast_index);
}

test "foreground carried load stays above forks and camera-facing mast" {
    var surfaces = [_]OpaqueSurface{.{
        .bounds = .{ .x = 80, .y = 80, .width = 40, .height = 20 },
        .support_z = vehicle.forkZ(.rack_low),
    }};
    const forklift = vehicle.Forklift{
        .position = .{ .x = 100, .y = 140 },
        .heading_rad = std.math.pi,
        .fork_height = .carry,
    };
    const pallet = cargo.Pallet{
        .position = .{ .x = 100, .y = 140 },
        .state = .carried,
        .z = vehicle.forkZ(.carry),
    };
    var sink = TestSink{};

    compose(forklift, pallet, &surfaces, .{}, &sink);

    const surface = lastTestDrawIndex(
        sink.items[0..sink.len],
        .{ .surface = vehicle.forkZ(.rack_low) },
    ).?;
    const mast = lastTestDrawIndex(
        sink.items[0..sink.len],
        .{ .part = .forklift_mast },
    ).?;
    const forks = lastTestDrawIndex(
        sink.items[0..sink.len],
        .{ .part = .forklift_forks },
    ).?;
    const load = lastTestDrawIndex(sink.items[0..sink.len], .{ .part = .pallet }).?;
    try std.testing.expect(surface < mast);
    try std.testing.expect(mast < forks);
    try std.testing.expect(forks < load);
    try std.testing.expectEqual(
        @as(usize, 1),
        testDrawCount(
            sink.items[0..sink.len],
            .{ .surface = vehicle.forkZ(.rack_low) },
        ),
    );
}

test "forklift mast crosses rack surface correctly at cardinal and diagonal yaw" {
    const yaws = [_]f32{
        0,
        std.math.pi / 2.0,
        std.math.pi,
        3.0 * std.math.pi / 2.0,
        std.math.pi / 4.0,
    };
    const rack = OpaqueSurface{
        .bounds = .{ .x = 80, .y = 80, .width = 40, .height = 20 },
        .support_z = vehicle.forkZ(.rack_low),
    };
    const rack_center = math2.Vec2{ .x = 100, .y = 90 };

    for (yaws) |yaw| {
        const depth_direction = math2.Vec2{
            .x = @sin(yaw),
            .y = @cos(yaw),
        };
        const positions = [_]struct { position: math2.Vec2, front: bool }{
            .{
                .position = .{
                    .x = rack_center.x + depth_direction.x * 100,
                    .y = rack_center.y + depth_direction.y * 100,
                },
                .front = true,
            },
            .{
                .position = .{
                    .x = rack_center.x - depth_direction.x * 100,
                    .y = rack_center.y - depth_direction.y * 100,
                },
                .front = false,
            },
        };

        for (positions) |case| {
            var surfaces = [_]OpaqueSurface{rack};
            const forklift = vehicle.Forklift{ .position = case.position };
            const pallet = cargo.Pallet{ .position = .{ .x = 400, .y = 400 } };
            var sink = TestSink{};
            compose(forklift, pallet, &surfaces, .{ .yaw_rad = yaw }, &sink);

            const surface_index = lastTestDrawIndex(
                sink.items[0..sink.len],
                .{ .surface = rack.support_z },
            ).?;
            const mast_index = lastTestDrawIndex(
                sink.items[0..sink.len],
                .{ .part = .forklift_mast },
            ).?;
            try std.testing.expectEqual(case.front, surface_index < mast_index);
        }
    }
}

test "vehicle-local order preserves facing and carried-pallet rules" {
    const pallet = cargo.Pallet{
        .position = .{ .x = 100, .y = 100 },
        .state = .carried,
        .z = vehicle.forkZ(.carry),
    };
    const cases = [_]struct {
        heading_rad: f32,
        facing_camera: bool,
    }{
        .{ .heading_rad = std.math.pi, .facing_camera = true },
        .{ .heading_rad = 0, .facing_camera = false },
    };

    for (cases) |case| {
        var surfaces = [_]OpaqueSurface{};
        var sink = TestSink{};
        compose(
            .{ .position = .{ .x = 100, .y = 100 }, .heading_rad = case.heading_rad },
            pallet,
            &surfaces,
            .{},
            &sink,
        );

        const canopy = lastTestDrawIndex(sink.items[0..sink.len], .{ .part = .forklift_canopy }).?;
        const mast = lastTestDrawIndex(sink.items[0..sink.len], .{ .part = .forklift_mast }).?;
        const forks = lastTestDrawIndex(sink.items[0..sink.len], .{ .part = .forklift_forks }).?;
        const load = lastTestDrawIndex(sink.items[0..sink.len], .{ .part = .pallet }).?;

        try std.testing.expect(forks < load);
        if (case.facing_camera) {
            try std.testing.expect(canopy < mast);
            try std.testing.expect(mast < load);
        } else {
            try std.testing.expect(load < mast);
            try std.testing.expect(mast < canopy);
        }
    }
}

test "stacked shelves replay only parts at or above each shelf" {
    const rack_bounds = collision.Rect{ .x = 80, .y = 80, .width = 40, .height = 20 };
    const forklift = vehicle.Forklift{
        .position = .{ .x = 100, .y = 20 },
        .heading_rad = std.math.pi,
        .fork_height = .rack_low,
    };
    const pallet = cargo.Pallet{
        .position = .{ .x = 100, .y = 20 },
        .state = .carried,
        .z = vehicle.forkZ(.rack_low),
    };
    var surfaces = [_]OpaqueSurface{
        .{ .bounds = rack_bounds, .support_z = vehicle.forkZ(.rack_low) },
        .{ .bounds = rack_bounds, .support_z = vehicle.forkZ(.rack_high) },
    };
    var sink = TestSink{};

    compose(forklift, pallet, &surfaces, .{}, &sink);

    const low_surface = lastTestDrawIndex(
        sink.items[0..sink.len],
        .{ .surface = vehicle.forkZ(.rack_low) },
    ).?;
    const high_surface = lastTestDrawIndex(
        sink.items[0..sink.len],
        .{ .surface = vehicle.forkZ(.rack_high) },
    ).?;
    const forks = lastTestDrawIndex(
        sink.items[0..sink.len],
        .{ .part = .forklift_forks },
    ).?;
    const load = lastTestDrawIndex(sink.items[0..sink.len], .{ .part = .pallet }).?;

    try std.testing.expect(low_surface < forks);
    try std.testing.expect(forks < load);
    try std.testing.expect(load < high_surface);
}

test "rack-high parts replay above both stacked shelves" {
    const rack_bounds = collision.Rect{ .x = 80, .y = 80, .width = 40, .height = 20 };
    const forklift = vehicle.Forklift{
        .position = .{ .x = 100, .y = 20 },
        .heading_rad = std.math.pi,
        .fork_height = .rack_high,
    };
    const pallet = cargo.Pallet{
        .position = .{ .x = 100, .y = 20 },
        .state = .carried,
        .z = vehicle.forkZ(.rack_high),
    };
    var surfaces = [_]OpaqueSurface{
        .{ .bounds = rack_bounds, .support_z = vehicle.forkZ(.rack_low) },
        .{ .bounds = rack_bounds, .support_z = vehicle.forkZ(.rack_high) },
    };
    var sink = TestSink{};

    compose(forklift, pallet, &surfaces, .{}, &sink);

    const high_surface = lastTestDrawIndex(
        sink.items[0..sink.len],
        .{ .surface = vehicle.forkZ(.rack_high) },
    ).?;
    const forks = lastTestDrawIndex(sink.items[0..sink.len], .{ .part = .forklift_forks }).?;
    const load = lastTestDrawIndex(sink.items[0..sink.len], .{ .part = .pallet }).?;
    try std.testing.expect(high_surface < forks);
    try std.testing.expect(forks < load);
}

test "dropped pallet uses support height independently of fork height" {
    const rack_bounds = collision.Rect{ .x = 80, .y = 80, .width = 40, .height = 20 };
    const pallet = cargo.Pallet{
        .position = .{ .x = 100, .y = 20 },
        .state = .floor,
        .z = vehicle.forkZ(.rack_high),
        .support_z = vehicle.forkZ(.rack_high),
    };

    for ([_]vehicle.ForkHeight{ .floor, .rack_high }) |fork_height| {
        var surfaces = [_]OpaqueSurface{
            .{ .bounds = rack_bounds, .support_z = vehicle.forkZ(.rack_low) },
            .{ .bounds = rack_bounds, .support_z = vehicle.forkZ(.rack_high) },
        };
        var sink = TestSink{};
        compose(
            .{ .position = .{ .x = 300, .y = 20 }, .fork_height = fork_height },
            pallet,
            &surfaces,
            .{},
            &sink,
        );

        const high_surface = lastTestDrawIndex(
            sink.items[0..sink.len],
            .{ .surface = vehicle.forkZ(.rack_high) },
        ).?;
        const load = lastTestDrawIndex(sink.items[0..sink.len], .{ .part = .pallet }).?;
        try std.testing.expect(high_surface < load);
    }
}
