const std = @import("std");
const campaign = @import("../game/campaign.zig");
const cargo = @import("../sim/cargo.zig");
const collision = @import("../sim/collision.zig");
const vehicle = @import("../sim/vehicle.zig");
const stages = @import("../content/stages.zig");
const static_level = @import("../content/static_level.zig");
const compositor = @import("compositor.zig");
const renderer_module = @import("renderer.zig");

pub const max_entries = 128;

pub const Entry = union(enum) {
    warehouse: struct { stage_id: campaign.StageId, phase: static_level.DrawPhase, actor_depth: f32 },
    destination: collision.Rect,
    decorative_pallets: campaign.StageId,
    conveyors: campaign.StageId,
    pallet_shadow: cargo.Pallet,
    dynamic: struct { stage_id: campaign.StageId, forklift: vehicle.Forklift, pallet: cargo.Pallet },
};

pub const RenderScene = struct {
    entries: [max_entries]Entry = undefined,
    len: usize = 0,

    pub fn clear(self: *RenderScene) void {
        self.len = 0;
    }
    pub fn append(self: *RenderScene, entry: Entry) void {
        if (self.len == self.entries.len) @panic("render scene capacity exceeded");
        self.entries[self.len] = entry;
        self.len += 1;
    }
    pub fn submit(self: *const RenderScene, renderer: *renderer_module.Renderer, fragments: *compositor.SurfaceFragmentBuffer) void {
        for (self.entries[0..self.len]) |entry| switch (entry) {
            .warehouse => |item| stages.drawWarehouse(item.stage_id, renderer, item.phase, item.actor_depth),
            .destination => |zone| renderer.destination(zone),
            .decorative_pallets => |stage_id| stages.drawDecorativePallets(stage_id, renderer),
            .conveyors => |stage_id| for (stages.conveyors(stage_id)) |belt| renderer.destination(belt.bounds),
            .pallet_shadow => |pallet| renderer.palletShadow(pallet),
            .dynamic => |item| {
                var collector = compositor.OpaqueSurfaceCollector.init(renderer);
                stages.collectOpaqueSurfaces(item.stage_id, &collector);
                var scene_compositor = compositor.Compositor.init(renderer, collector.slice(), fragments);
                scene_compositor.drawDynamic(item.forklift, item.pallet);
            },
        };
    }
};

test "render scene preserves semantic submission order" {
    var scene = RenderScene{};
    const zone = collision.Rect{ .x = 1, .y = 2, .width = 3, .height = 4 };
    scene.append(.{ .destination = zone });
    scene.append(.{ .decorative_pallets = .training_facility });
    try std.testing.expectEqual(@as(usize, 2), scene.len);
    try std.testing.expectEqual(zone, scene.entries[0].destination);
    try std.testing.expectEqual(campaign.StageId.training_facility, scene.entries[1].decorative_pallets);
}
