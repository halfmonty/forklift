const std = @import("std");
const cargo = @import("../sim/cargo.zig");
const collision = @import("../sim/collision.zig");
const math2 = @import("../sim/math2.zig");
const vehicle = @import("../sim/vehicle.zig");
const camera = @import("camera.zig");
const renderer_module = @import("renderer.zig");

pub const max_opaque_surfaces = 64;
const max_surface_fragments = max_opaque_surfaces * 6;
pub const pallet_top_z_offset: f32 = 6;

pub const OpaqueSurface = struct {
    bounds: collision.Rect,
    support_z: f32,
};

pub const SurfaceFragment = struct {
    surface: OpaqueSurface,
    depth_min: f32,
    depth_max: f32,
    sort_depth: f32,
    draw_legs_before: bool,
    draw_front_legs_after: bool,
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
    ground_anchor: math2.Vec2,
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

    pub fn drawSurface(self: *RendererSink, fragment: SurfaceFragment) void {
        self.renderer.opaqueSurfaceFragment(
            fragment.surface.bounds,
            fragment.surface.support_z,
            fragment.depth_min,
            fragment.depth_max,
            fragment.draw_legs_before,
            fragment.draw_front_legs_after,
        );
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
    var parts = dynamicParts(forklift, pallet, camera_state);
    sortParts(&parts);

    var fragments: [max_surface_fragments]SurfaceFragment = undefined;
    const fragment_count = buildSurfaceFragments(
        surfaces,
        &parts,
        camera_state,
        &fragments,
    );
    const active_fragments = fragments[0..fragment_count];
    sortSurfaceFragments(active_fragments);

    var surface_index: usize = 0;
    var part_index: usize = 0;
    while (surface_index < active_fragments.len or part_index < parts.len) {
        const take_surface = surface_index < active_fragments.len and
            (part_index == parts.len or
                active_fragments[surface_index].sort_depth <= parts[part_index].depth);

        if (take_surface) {
            const fragment = active_fragments[surface_index];
            sink.drawSurface(fragment);

            // The fragment just covered all previously drawn lower geometry.
            // Replay only parts whose visible plane is at or above it.
            for (parts[0..part_index]) |part| {
                if (!surfaceOccludesPart(fragment.surface, part.occlusion_z)) {
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

fn buildSurfaceFragments(
    surfaces: []const OpaqueSurface,
    parts: *const [5]RenderPart,
    camera_state: camera.Camera,
    output: *[max_surface_fragments]SurfaceFragment,
) usize {
    var unique_depths: [5]f32 = undefined;
    var unique_depth_count: usize = 0;
    for (parts) |part| {
        var duplicate = false;
        for (unique_depths[0..unique_depth_count]) |depth| {
            if (@abs(depth - part.depth) < 0.001) {
                duplicate = true;
                break;
            }
        }
        if (!duplicate) {
            unique_depths[unique_depth_count] = part.depth;
            unique_depth_count += 1;
        }
    }
    sortDepths(unique_depths[0..unique_depth_count]);

    var output_len: usize = 0;
    for (surfaces) |surface| {
        const range = surfaceDepthRange(surface, camera_state);
        if (stackedSurfaceForceDepth(surface, surfaces, parts)) |part_depth| {
            appendSurfaceFragment(
                output,
                &output_len,
                surface,
                range.min,
                range.max,
                true,
                true,
                forcedStackSortDepth(surface, surfaces, part_depth),
            );
            continue;
        }
        var band_start = range.min;
        var first = true;

        for (unique_depths[0..unique_depth_count]) |depth| {
            if (depth <= range.min + 0.001 or depth >= range.max - 0.001) continue;
            appendSurfaceFragment(
                output,
                &output_len,
                surface,
                band_start,
                depth,
                first,
                false,
                null,
            );
            band_start = depth;
            first = false;
        }

        appendSurfaceFragment(
            output,
            &output_len,
            surface,
            band_start,
            range.max,
            first,
            true,
            null,
        );
    }
    return output_len;
}

fn appendSurfaceFragment(
    output: *[max_surface_fragments]SurfaceFragment,
    output_len: *usize,
    surface: OpaqueSurface,
    depth_min: f32,
    depth_max: f32,
    draw_legs_before: bool,
    draw_front_legs_after: bool,
    forced_sort_depth: ?f32,
) void {
    if (output_len.* == output.len) {
        @panic("opaque surface fragment capacity exceeded");
    }
    output[output_len.*] = .{
        .surface = surface,
        .depth_min = depth_min,
        .depth_max = depth_max,
        .sort_depth = if (forced_sort_depth) |depth|
            depth
        else
            (depth_min + depth_max) * 0.5,
        .draw_legs_before = draw_legs_before,
        .draw_front_legs_after = draw_front_legs_after,
    };
    output_len.* += 1;
}

fn stackedSurfaceForceDepth(
    surface: OpaqueSurface,
    surfaces: []const OpaqueSurface,
    parts: *const [5]RenderPart,
) ?f32 {
    var result: ?f32 = null;
    for (surfaces) |candidate| {
        if (!sameSurfaceFootprint(surface, candidate)) continue;
        if (candidate.support_z < surface.support_z) continue;
        for (parts) |part| {
            if (!surfaceOccludesPart(candidate, part.occlusion_z)) continue;
            if (!pointInsideRect(part.ground_anchor, candidate.bounds)) continue;
            result = if (result) |current| @max(current, part.depth) else part.depth;
        }
    }
    return result;
}

fn forcedStackSortDepth(
    surface: OpaqueSurface,
    surfaces: []const OpaqueSurface,
    part_depth: f32,
) f32 {
    var lower_levels: f32 = 1;
    for (surfaces) |candidate| {
        if (!sameSurfaceFootprint(surface, candidate)) continue;
        if (candidate.support_z < surface.support_z) lower_levels += 1;
    }
    return part_depth + lower_levels * 0.0001;
}

fn sameSurfaceFootprint(left: OpaqueSurface, right: OpaqueSurface) bool {
    const a = left.bounds;
    const b = right.bounds;
    return a.x == b.x and a.y == b.y and a.width == b.width and a.height == b.height;
}

fn pointInsideRect(point: math2.Vec2, rect: collision.Rect) bool {
    return point.x >= rect.x and point.x <= rect.x + rect.width and
        point.y >= rect.y and point.y <= rect.y + rect.height;
}

fn sortDepths(depths: []f32) void {
    if (depths.len < 2) return;
    for (1..depths.len) |index| {
        const depth = depths[index];
        var insertion = index;
        while (insertion > 0 and depth < depths[insertion - 1]) {
            depths[insertion] = depths[insertion - 1];
            insertion -= 1;
        }
        depths[insertion] = depth;
    }
}

fn dynamicParts(
    forklift: vehicle.Forklift,
    pallet: cargo.Pallet,
    camera_state: camera.Camera,
) [5]RenderPart {
    const forward = math2.forwardVector(forklift.heading_rad);
    const body_center = vehicle.bodyCenter(forklift);
    const canopy_center = math2.add(body_center, math2.scale(forward, -4));
    const fork_geometry = vehicle.forkGeometry(forklift);
    const mast_center = math2.Vec2{
        .x = (fork_geometry.left_base.x + fork_geometry.right_base.x) * 0.5,
        .y = (fork_geometry.left_base.y + fork_geometry.right_base.y) * 0.5,
    };
    const fork_center = math2.Vec2{
        .x = (fork_geometry.left_base.x + fork_geometry.right_tip.x) * 0.5,
        .y = (fork_geometry.left_base.y + fork_geometry.right_tip.y) * 0.5,
    };
    const base_depth = camera.depth(body_center, camera_state);
    const canopy_depth = camera.depth(canopy_center, camera_state);
    const mast_depth = camera.depth(mast_center, camera_state);
    const fork_depth = camera.depth(fork_center, camera_state);
    const facing_camera = renderer_module.canopyBehindForks(forklift, camera_state);
    const pallet_z = (if (pallet.state == .carried) pallet.z else pallet.support_z) +
        pallet_top_z_offset;

    return .{
        .{
            .kind = .forklift_base,
            .ground_anchor = body_center,
            .depth = base_depth,
            .occlusion_z = 0,
            .local_order = 0,
        },
        .{
            .kind = .forklift_canopy,
            .ground_anchor = canopy_center,
            .depth = canopy_depth,
            .occlusion_z = 0,
            .local_order = if (facing_camera) 1 else 4,
        },
        .{
            .kind = .forklift_mast,
            .ground_anchor = mast_center,
            .depth = mast_depth,
            .occlusion_z = 0,
            .local_order = if (facing_camera) 2 else 3,
        },
        .{
            .kind = .forklift_forks,
            .ground_anchor = fork_center,
            .depth = fork_depth,
            .occlusion_z = vehicle.forkZ(forklift.fork_height),
            .local_order = if (facing_camera) 3 else 1,
        },
        .{
            .kind = .pallet,
            .ground_anchor = pallet.position,
            .depth = if (pallet.state == .carried)
                fork_depth
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

fn sortSurfaceFragments(fragments: []SurfaceFragment) void {
    if (fragments.len < 2) return;
    for (1..fragments.len) |index| {
        const fragment = fragments[index];
        var insertion = index;
        while (insertion > 0 and fragmentBefore(fragment, fragments[insertion - 1])) {
            fragments[insertion] = fragments[insertion - 1];
            insertion -= 1;
        }
        fragments[insertion] = fragment;
    }
}

fn fragmentBefore(left: SurfaceFragment, right: SurfaceFragment) bool {
    if (left.sort_depth != right.sort_depth) return left.sort_depth < right.sort_depth;
    return left.surface.support_z < right.surface.support_z;
}

const DepthRange = struct { min: f32, max: f32 };

pub fn surfaceDepthRange(surface: OpaqueSurface, camera_state: camera.Camera) DepthRange {
    const bounds = surface.bounds;
    const depths = [_]f32{
        camera.depth(.{ .x = bounds.x, .y = bounds.y }, camera_state),
        camera.depth(.{ .x = bounds.x + bounds.width, .y = bounds.y }, camera_state),
        camera.depth(.{ .x = bounds.x + bounds.width, .y = bounds.y + bounds.height }, camera_state),
        camera.depth(.{ .x = bounds.x, .y = bounds.y + bounds.height }, camera_state),
    };
    var result = DepthRange{ .min = depths[0], .max = depths[0] };
    for (depths[1..]) |depth| {
        result.min = @min(result.min, depth);
        result.max = @max(result.max, depth);
    }
    return result;
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

    pub fn drawSurface(self: *TestSink, fragment: SurfaceFragment) void {
        self.items[self.len] = .{ .surface = fragment.surface.support_z };
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

const FragmentTestSink = struct {
    ranges: [4][2]f32 = undefined,
    len: usize = 0,

    pub fn drawSurface(self: *FragmentTestSink, fragment: anytype) void {
        self.ranges[self.len] = .{ fragment.depth_min, fragment.depth_max };
        self.len += 1;
    }

    pub fn drawPart(_: *FragmentTestSink, _: RenderPart) void {}
};

test "diagonal shelf crossing component depths emits contiguous fragments" {
    var surfaces = [_]OpaqueSurface{.{
        .bounds = .{ .x = 0, .y = 0, .width = 20, .height = 20 },
        .support_z = vehicle.forkZ(.rack_low),
    }};
    const camera_state = camera.Camera{ .yaw_rad = std.math.pi / 4.0 };
    // The actor crosses the shelf's depth span at diagonal yaw without being
    // beneath its footprint, so it requires depth fragments rather than the
    // under-shelf height rule.
    const actor_position = math2.Vec2{ .x = 22, .y = 0 };
    var sink = FragmentTestSink{};

    compose(
        .{ .position = actor_position },
        .{ .position = actor_position },
        &surfaces,
        camera_state,
        &sink,
    );

    const actor_depth = camera.depth(actor_position, camera_state);
    try std.testing.expect(sink.len >= 2);
    var found_actor_boundary = false;
    for (1..sink.len) |index| {
        try std.testing.expectApproxEqAbs(
            sink.ranges[index - 1][1],
            sink.ranges[index][0],
            0.001,
        );
        if (@abs(sink.ranges[index][0] - actor_depth) < 0.001) {
            found_actor_boundary = true;
        }
    }
    try std.testing.expect(found_actor_boundary);
}

test "mast shelf ordering uses mast position rather than rear axle" {
    var surfaces = [_]OpaqueSurface{.{
        .bounds = .{ .x = 90, .y = 70, .width = 20, .height = 5 },
        .support_z = vehicle.forkZ(.rack_low),
    }};
    const forklift = vehicle.Forklift{
        .position = .{ .x = 100, .y = 50 },
        .heading_rad = std.math.pi,
    };
    var sink = TestSink{};

    compose(
        forklift,
        .{ .position = .{ .x = 300, .y = 300 } },
        &surfaces,
        .{},
        &sink,
    );

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

const UnderShelfTestSink = struct {
    surfaces: [8]SurfaceFragment = undefined,
    surface_len: usize = 0,
    parts: [16]RenderPartKind = undefined,
    part_len: usize = 0,
    draws: [24]TestDraw = undefined,
    draw_len: usize = 0,

    pub fn drawSurface(self: *UnderShelfTestSink, fragment: SurfaceFragment) void {
        self.surfaces[self.surface_len] = fragment;
        self.surface_len += 1;
        self.draws[self.draw_len] = .{ .surface = fragment.surface.support_z };
        self.draw_len += 1;
    }

    pub fn drawPart(self: *UnderShelfTestSink, part: RenderPart) void {
        self.parts[self.part_len] = part.kind;
        self.part_len += 1;
        self.draws[self.draw_len] = .{ .part = part.kind };
        self.draw_len += 1;
    }
};

test "low pallet inside high shelf footprint is fully occluded by high shelf" {
    const rack_bounds = collision.Rect{ .x = 80, .y = 80, .width = 40, .height = 20 };
    var surfaces = [_]OpaqueSurface{
        .{ .bounds = rack_bounds, .support_z = vehicle.forkZ(.rack_low) },
        .{ .bounds = rack_bounds, .support_z = vehicle.forkZ(.rack_high) },
    };
    const pallet = cargo.Pallet{
        .position = .{ .x = 100, .y = 90 },
        .support_z = vehicle.forkZ(.rack_low),
        .z = vehicle.forkZ(.rack_low),
    };
    var sink = UnderShelfTestSink{};

    compose(
        .{ .position = .{ .x = 300, .y = 20 } },
        pallet,
        &surfaces,
        .{},
        &sink,
    );

    var high_fragment_count: usize = 0;
    var high_fragment_index: usize = 0;
    for (sink.surfaces[0..sink.surface_len], 0..) |fragment, index| {
        if (fragment.surface.support_z == vehicle.forkZ(.rack_high)) {
            high_fragment_count += 1;
            high_fragment_index = index;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), high_fragment_count);
    try std.testing.expectEqual(vehicle.forkZ(.rack_high), sink.surfaces[high_fragment_index].surface.support_z);

    const low_surface = lastTestDrawIndex(
        sink.draws[0..sink.draw_len],
        .{ .surface = vehicle.forkZ(.rack_low) },
    ).?;
    const pallet_index = lastTestDrawIndex(
        sink.draws[0..sink.draw_len],
        .{ .part = .pallet },
    ).?;
    const high_surface = lastTestDrawIndex(
        sink.draws[0..sink.draw_len],
        .{ .surface = vehicle.forkZ(.rack_high) },
    ).?;
    try std.testing.expect(low_surface < pallet_index);
    try std.testing.expect(pallet_index < high_surface);
}
