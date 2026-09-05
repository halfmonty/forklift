const std = @import("std");
const pdapi = @import("../playdate_api_definitions.zig");
const vehicle = @import("../sim/vehicle.zig");
const camera = @import("camera.zig");
const math2 = @import("../sim/math2.zig");
const projection = @import("projection.zig");
const cargo = @import("../sim/cargo.zig");
const collision = @import("../sim/collision.zig");

const black: pdapi.LCDColor = @intCast(@intFromEnum(pdapi.LCDSolidColor.ColorBlack));

pub const RenderStats = struct {
    submitted: usize = 0,
    culled: usize = 0,
};

pub const Renderer = struct {
    playdate: *pdapi.PlaydateAPI,
    camera_state: camera.Camera,
    cull_margin: f32,
    stats: RenderStats = .{},

    pub fn init(
        playdate: *pdapi.PlaydateAPI,
        camera_state: camera.Camera,
        cull_margin: f32,
    ) Renderer {
        return .{
            .playdate = playdate,
            .camera_state = camera_state,
            .cull_margin = cull_margin,
        };
    }

    fn acceptsRect(self: *Renderer, rect: collision.Rect) bool {
        const bounds = camera.visibleWorldBounds(self.camera_state);
        const visible = rect.x + rect.width >= bounds.min.x - self.cull_margin and
            rect.x <= bounds.max.x + self.cull_margin and
            rect.y + rect.height >= bounds.min.y - self.cull_margin and
            rect.y <= bounds.max.y + self.cull_margin;

        if (visible) {
            self.stats.submitted += 1;
        } else {
            self.stats.culled += 1;
        }
        return visible;
    }

    fn acceptsPoint(self: *Renderer, point: math2.Vec2) bool {
        return self.acceptsRect(.{
            .x = point.x,
            .y = point.y,
            .width = 0,
            .height = 0,
        });
    }

    fn acceptsPallet(self: *Renderer, pallet_data: cargo.Pallet) bool {
        return self.acceptsRect(.{
            .x = pallet_data.position.x - pallet_data.footprint.half_width,
            .y = pallet_data.position.y - pallet_data.footprint.half_length,
            .width = pallet_data.footprint.half_width * 2,
            .height = pallet_data.footprint.half_length * 2,
        });
    }

    pub fn tallBox(self: *Renderer, position: math2.Vec2) void {
        if (!self.acceptsPoint(position)) return;
        drawTallBox(self.playdate, position, self.camera_state, black);
    }

    pub fn rackBack(self: *Renderer, rack: collision.Rect) void {
        if (!self.acceptsRect(rack)) return;
        drawRackBack(self.playdate, rack, self.camera_state, black);
    }

    pub fn rackFront(self: *Renderer, rack: collision.Rect) void {
        if (!self.acceptsRect(rack)) return;
        drawRackFront(self.playdate, rack, self.camera_state, black);
    }

    pub fn rackFrontDepth(self: Renderer, rack: collision.Rect) f32 {
        return rackFrontDepthRaw(rack, self.camera_state);
    }

    pub fn obstacle(self: *Renderer, obstacle_rect: collision.Rect) void {
        if (!self.acceptsRect(obstacle_rect)) return;
        drawObstacle(self.playdate, obstacle_rect, self.camera_state, black);
    }

    pub fn destination(self: *Renderer, zone: collision.Rect) void {
        if (!self.acceptsRect(zone)) return;
        drawDestination(self.playdate, zone, self.camera_state, black);
    }

    pub fn cone(self: *Renderer, position: math2.Vec2) void {
        if (!self.acceptsPoint(position)) return;
        drawCone(self.playdate, position, self.camera_state, black);
    }

    pub fn shelf(
        self: *Renderer,
        zone: collision.Rect,
        support_z: f32,
    ) void {
        if (!self.acceptsRect(zone)) return;
        drawShelf(self.playdate, zone, support_z, self.camera_state, black);
    }

    pub fn palletShadow(self: *Renderer, pallet_data: cargo.Pallet) void {
        if (!self.acceptsPallet(pallet_data)) return;
        drawPalletShadow(self.playdate, pallet_data, self.camera_state, black);
    }

    pub fn pallet(self: *Renderer, pallet_data: cargo.Pallet) void {
        if (!self.acceptsPallet(pallet_data)) return;
        drawPallet(self.playdate, pallet_data, self.camera_state, black);
    }

    pub fn forklift(self: *Renderer, forklift_data: vehicle.Forklift) void {
        self.stats.submitted += 1;
        drawForklift(self.playdate, forklift_data, self.camera_state);
    }
};

pub fn drawForklift(
    playdate: *pdapi.PlaydateAPI,
    forklift: vehicle.Forklift,
    camera_state: camera.Camera,
) void {
    const white: pdapi.LCDColor =
        @intCast(@intFromEnum(pdapi.LCDSolidColor.ColorWhite));
    const fork_z = vehicle.forkZ(forklift.fork_height);
    const forward =
        math2.forwardVector(forklift.heading_rad);
    const right = math2.Vec2{
        .x = @cos(forklift.heading_rad),
        .y = @sin(forklift.heading_rad),
    };
    const body_center = vehicle.bodyCenter(forklift);

    const chassis = quadPoints(
        body_center,
        forward,
        right,
        vehicle.body_front_extent,
        vehicle.body_rear_extent,
        vehicle.body_half_width,
        0,
        camera_state,
    );
    drawQuad(playdate, chassis, black, black);

    const deck_center = offsetPoint(
        body_center,
        forward,
        right,
        2,
        0,
    );
    const deck = quadPoints(
        deck_center,
        forward,
        right,
        12,
        12,
        8,
        6,
        camera_state,
    );
    drawQuad(playdate, deck, white, black);

    const forks = vehicle.forkGeometry(forklift);
    const left_base = projection.project(
        forks.left_base,
        fork_z,
        camera_state,
        projection.default_tuning,
    );
    const left_tip = projection.project(
        forks.left_tip,
        fork_z,
        camera_state,
        projection.default_tuning,
    );
    const right_base = projection.project(
        forks.right_base,
        fork_z,
        camera_state,
        projection.default_tuning,
    );
    const right_tip = projection.project(
        forks.right_tip,
        fork_z,
        camera_state,
        projection.default_tuning,
    );

    line(playdate, left_base, left_tip, 3, black);
    line(playdate, right_base, right_tip, 3, black);

    const mast_top_z: f32 = 40;

    const left_mast_base = projection.project(
        forks.left_base,
        0,
        camera_state,
        projection.default_tuning,
    );
    const right_mast_base = projection.project(
        forks.right_base,
        0,
        camera_state,
        projection.default_tuning,
    );
    const left_mast_top = projection.project(
        forks.left_base,
        mast_top_z,
        camera_state,
        projection.default_tuning,
    );
    const right_mast_top = projection.project(
        forks.right_base,
        mast_top_z,
        camera_state,
        projection.default_tuning,
    );

    line(playdate, left_mast_base, left_mast_top, 2, black);
    line(playdate, right_mast_base, right_mast_top, 2, black);
    line(playdate, left_mast_top, right_mast_top, 2, black);

    // Moving carriage.
    line(playdate, left_base, right_base, 3, black);

    const rear_axle = forklift.position;
    const wheel_direction = vehicle.rearWheelDirection(
        forklift.heading_rad,
        forklift.steer_angle_rad,
    );
    line(
        playdate,
        projection.project(
            math2.sub(rear_axle, math2.scale(wheel_direction, 10)),
            0,
            camera_state,
            projection.default_tuning,
        ),
        projection.project(
            math2.add(rear_axle, math2.scale(wheel_direction, 10)),
            0,
            camera_state,
            projection.default_tuning,
        ),
        5,
        black,
    );

    const canopy_center = offsetPoint(
        body_center,
        forward,
        right,
        -4,
        0,
    );
    const canopy = quadPoints(
        canopy_center,
        forward,
        right,
        9,
        9,
        10,
        30,
        camera_state,
    );

    const left_support_base = projection.project(
        offsetPoint(body_center, forward, right, -8, -8),
        6,
        camera_state,
        projection.default_tuning,
    );
    const right_support_base = projection.project(
        offsetPoint(body_center, forward, right, -8, 8),
        6,
        camera_state,
        projection.default_tuning,
    );

    line(playdate, left_support_base, canopy[3], 2, black);
    line(playdate, right_support_base, canopy[2], 2, black);
    drawQuad(playdate, canopy, white, black);
}

pub fn drawPallet(
    playdate: *pdapi.PlaydateAPI,
    pallet: cargo.Pallet,
    camera_state: camera.Camera,
    color: pdapi.LCDColor,
) void {
    const forward =
        math2.forwardVector(pallet.heading_rad);
    const right = math2.Vec2{
        .x = @cos(pallet.heading_rad),
        .y = @sin(pallet.heading_rad),
    };
    const front = math2.scale(forward, pallet.footprint.half_length);
    const side = math2.scale(right, pallet.footprint.half_width);

    const front_left_world =
        math2.sub(math2.add(pallet.position, front), side);
    const front_right_world =
        math2.add(math2.add(pallet.position, front), side);
    const rear_left_world =
        math2.sub(math2.sub(pallet.position, front), side);
    const rear_right_world =
        math2.add(math2.sub(pallet.position, front), side);

    const front_left = projection.project(
        front_left_world,
        pallet.z,
        camera_state,
        projection.default_tuning,
    );
    const front_right = projection.project(
        front_right_world,
        pallet.z,
        camera_state,
        projection.default_tuning,
    );
    const rear_left = projection.project(
        rear_left_world,
        pallet.z,
        camera_state,
        projection.default_tuning,
    );
    const rear_right = projection.project(
        rear_right_world,
        pallet.z,
        camera_state,
        projection.default_tuning,
    );

    line(playdate, front_left, front_right, 2, color);
    line(playdate, front_right, rear_right, 2, color);
    line(playdate, rear_right, rear_left, 2, color);
    line(playdate, rear_left, front_left, 2, color);

    const entry_turns = [_]f32{
        0,
        std.math.pi / 2.0,
        std.math.pi,
        3.0 * std.math.pi / 2.0,
    };

    for (entry_turns, 0..) |turn, index| {
        const entry_half_extent =
            if (index % 2 == 0)
                pallet.footprint.half_length
            else
                pallet.footprint.half_width;

        drawPalletEntryLanes(
            playdate,
            pallet,
            pallet.heading_rad + turn,
            entry_half_extent,
            camera_state,
            color,
        );
    }
}

fn drawPalletEntryLanes(
    playdate: *pdapi.PlaydateAPI,
    pallet: cargo.Pallet,
    entry_heading_rad: f32,
    entry_half_extent: f32,
    camera_state: camera.Camera,
    color: pdapi.LCDColor,
) void {
    const forward = math2.forwardVector(entry_heading_rad);
    const right = math2.Vec2{
        .x = @cos(entry_heading_rad),
        .y = @sin(entry_heading_rad),
    };
    const entry_start = math2.sub(
        pallet.position,
        math2.scale(forward, entry_half_extent),
    );
    const left_entry = math2.sub(
        entry_start,
        math2.scale(right, 5),
    );
    const right_entry = math2.add(
        entry_start,
        math2.scale(right, 5),
    );
    const entry_length = math2.scale(forward, 24);

    line(
        playdate,
        projection.project(
            left_entry,
            pallet.z,
            camera_state,
            projection.default_tuning,
        ),
        projection.project(
            math2.add(left_entry, entry_length),
            pallet.z,
            camera_state,
            projection.default_tuning,
        ),
        1,
        color,
    );
    line(
        playdate,
        projection.project(
            right_entry,
            pallet.z,
            camera_state,
            projection.default_tuning,
        ),
        projection.project(
            math2.add(right_entry, entry_length),
            pallet.z,
            camera_state,
            projection.default_tuning,
        ),
        1,
        color,
    );
}

pub fn drawPalletShadow(
    playdate: *pdapi.PlaydateAPI,
    pallet: cargo.Pallet,
    camera_state: camera.Camera,
    color: pdapi.LCDColor,
) void {
    const should_draw_shadow =
        pallet.z > pallet.support_z or pallet.support_z > 0;
    if (!should_draw_shadow) return;

    const center = projection.project(
        pallet.position,
        pallet.support_z,
        camera_state,
        projection.default_tuning,
    );

    playdate.graphics.fillEllipse(
        @intFromFloat(center.x - 14),
        @intFromFloat(center.y + 8),
        28,
        8,
        0,
        0,
        color,
    );
}

fn offsetPoint(
    center: math2.Vec2,
    forward: math2.Vec2,
    right: math2.Vec2,
    forward_amount: f32,
    right_amount: f32,
) math2.Vec2 {
    return math2.add(
        center,
        math2.add(
            math2.scale(forward, forward_amount),
            math2.scale(right, right_amount),
        ),
    );
}

fn quadPoints(
    center: math2.Vec2,
    forward: math2.Vec2,
    right: math2.Vec2,
    front: f32,
    rear: f32,
    half_width: f32,
    z: f32,
    camera_state: camera.Camera,
) [4]math2.Vec2 {
    return .{
        projection.project(
            offsetPoint(center, forward, right, front, -half_width),
            z,
            camera_state,
            projection.default_tuning,
        ),
        projection.project(
            offsetPoint(center, forward, right, front, half_width),
            z,
            camera_state,
            projection.default_tuning,
        ),
        projection.project(
            offsetPoint(center, forward, right, -rear, half_width),
            z,
            camera_state,
            projection.default_tuning,
        ),
        projection.project(
            offsetPoint(center, forward, right, -rear, -half_width),
            z,
            camera_state,
            projection.default_tuning,
        ),
    };
}

fn drawQuad(
    playdate: *pdapi.PlaydateAPI,
    points: [4]math2.Vec2,
    fill: pdapi.LCDColor,
    outline: pdapi.LCDColor,
) void {
    playdate.graphics.fillTriangle(
        @intFromFloat(points[0].x),
        @intFromFloat(points[0].y),
        @intFromFloat(points[1].x),
        @intFromFloat(points[1].y),
        @intFromFloat(points[2].x),
        @intFromFloat(points[2].y),
        fill,
    );
    playdate.graphics.fillTriangle(
        @intFromFloat(points[0].x),
        @intFromFloat(points[0].y),
        @intFromFloat(points[2].x),
        @intFromFloat(points[2].y),
        @intFromFloat(points[3].x),
        @intFromFloat(points[3].y),
        fill,
    );

    line(playdate, points[0], points[1], 1, outline);
    line(playdate, points[1], points[2], 1, outline);
    line(playdate, points[2], points[3], 1, outline);
    line(playdate, points[3], points[0], 1, outline);
}

pub fn drawTallBox(
    playdate: *pdapi.PlaydateAPI,
    world_position: math2.Vec2,
    camera_state: camera.Camera,
    color: pdapi.LCDColor,
) void {
    const base = projection.project(
        world_position,
        0,
        camera_state,
        projection.default_tuning,
    );
    const top = projection.project(
        world_position,
        48,
        camera_state,
        projection.default_tuning,
    );

    playdate.graphics.fillEllipse(
        @intFromFloat(base.x - 22),
        @intFromFloat(base.y - 6),
        44,
        12,
        0,
        0,
        color,
    );

    playdate.graphics.drawRect(
        @intFromFloat(base.x - 20),
        @intFromFloat(base.y - 20),
        40,
        40,
        color,
    );
    playdate.graphics.drawRect(
        @intFromFloat(top.x - 20),
        @intFromFloat(top.y - 20),
        40,
        40,
        color,
    );

    line(
        playdate,
        .{ .x = base.x - 20, .y = base.y - 20 },
        .{ .x = top.x - 20, .y = top.y - 20 },
        1,
        color,
    );
    line(
        playdate,
        .{ .x = base.x + 20, .y = base.y - 20 },
        .{ .x = top.x + 20, .y = top.y - 20 },
        1,
        color,
    );
    line(
        playdate,
        .{ .x = base.x + 20, .y = base.y + 20 },
        .{ .x = top.x + 20, .y = top.y + 20 },
        1,
        color,
    );
    line(
        playdate,
        .{ .x = base.x - 20, .y = base.y + 20 },
        .{ .x = top.x - 20, .y = top.y + 20 },
        1,
        color,
    );
}

fn projectedRectCorners(
    rect: collision.Rect,
    z: f32,
    camera_state: camera.Camera,
) [4]math2.Vec2 {
    return .{
        projection.project(.{ .x = rect.x, .y = rect.y }, z, camera_state, projection.default_tuning),
        projection.project(.{ .x = rect.x + rect.width, .y = rect.y }, z, camera_state, projection.default_tuning),
        projection.project(.{ .x = rect.x + rect.width, .y = rect.y + rect.height }, z, camera_state, projection.default_tuning),
        projection.project(.{ .x = rect.x, .y = rect.y +
            rect.height }, z, camera_state, projection.default_tuning),
    };
}

fn drawProjectedRect(
    playdate: *pdapi.PlaydateAPI,
    rect: collision.Rect,
    z: f32,
    camera_state: camera.Camera,
    width: c_int,
    color: pdapi.LCDColor,
) void {
    const corners = projectedRectCorners(rect, z, camera_state);
    for (0..4) |index| {
        line(playdate, corners[index], corners[
            (index + 1) % 4
        ], width, color);
    }
}

pub fn drawDestination(
    playdate: *pdapi.PlaydateAPI,
    zone: collision.Rect,
    camera_state: camera.Camera,
    color: pdapi.LCDColor,
) void {
    const corners = projectedRectCorners(zone, 0, camera_state);

    drawProjectedRect(playdate, zone, 0, camera_state, 1, color);
    line(playdate, corners[0], corners[2], 1, color);
    line(playdate, corners[1], corners[3], 1, color);
}

pub fn line(
    playdate: *pdapi.PlaydateAPI,
    from: math2.Vec2,
    to: math2.Vec2,
    width: c_int,
    color: pdapi.LCDColor,
) void {
    playdate.graphics.drawLine(
        @intFromFloat(from.x),
        @intFromFloat(from.y),
        @intFromFloat(to.x),
        @intFromFloat(to.y),
        width,
        color,
    );
}

pub fn drawCone(
    playdate: *pdapi.PlaydateAPI,
    world_position: math2.Vec2,
    camera_state: camera.Camera,
    color: pdapi.LCDColor,
) void {
    const position = camera.worldToScreen(world_position, camera_state);

    playdate.graphics.fillRect(
        @intFromFloat(position.x - 3),
        @intFromFloat(position.y - 3),
        7,
        7,
        color,
    );
}

pub fn drawRackBack(
    playdate: *pdapi.PlaydateAPI,
    rack: collision.Rect,
    camera_state: camera.Camera,
    color: pdapi.LCDColor,
) void {
    drawProjectedRect(playdate, rack, 0, camera_state, 1, color);
}

fn rackFrontEdge(
    rack: collision.Rect,
    view: camera.View,
) [2]math2.Vec2 {
    return switch (view) {
        .north => .{
            .{ .x = rack.x, .y = rack.y + rack.height },
            .{ .x = rack.x + rack.width, .y = rack.y +
                rack.height },
        },
        .east => .{
            .{ .x = rack.x + rack.width, .y = rack.y +
                rack.height },
            .{ .x = rack.x + rack.width, .y = rack.y },
        },
        .south => .{
            .{ .x = rack.x + rack.width, .y = rack.y },
            .{ .x = rack.x, .y = rack.y },
        },
        .west => .{
            .{ .x = rack.x, .y = rack.y },
            .{ .x = rack.x, .y = rack.y + rack.height },
        },
    };
}

fn rackFrontDepthRaw(
    rack: collision.Rect,
    camera_state: camera.Camera,
) f32 {
    const edge = rackFrontEdge(rack, camera_state.view);
    return camera.depth(
        .{
            .x = (edge[0].x + edge[1].x) * 0.5,
            .y = (edge[0].y + edge[1].y) * 0.5,
        },
        camera_state,
    );
}

pub fn drawRackFront(
    playdate: *pdapi.PlaydateAPI,
    rack: collision.Rect,
    camera_state: camera.Camera,
    color: pdapi.LCDColor,
) void {
    const white: pdapi.LCDColor =
        @intCast(@intFromEnum(pdapi.LCDSolidColor.ColorWhite));

    const front_edge = rackFrontEdge(rack, camera_state.view);
    const front_left_world = front_edge[0];
    const front_right_world = front_edge[1];

    const ground_left = projection.project(
        front_left_world,
        0,
        camera_state,
        projection.default_tuning,
    );
    const ground_right = projection.project(
        front_right_world,
        0,
        camera_state,
        projection.default_tuning,
    );
    const top_left = projection.project(
        front_left_world,
        80,
        camera_state,
        projection.default_tuning,
    );
    const top_right = projection.project(
        front_right_world,
        80,
        camera_state,
        projection.default_tuning,
    );

    const top = projectedRectCorners(rack, 80, camera_state);

    playdate.graphics.fillTriangle(
        @intFromFloat(top[0].x),
        @intFromFloat(top[0].y),
        @intFromFloat(top[1].x),
        @intFromFloat(top[1].y),
        @intFromFloat(top[2].x),
        @intFromFloat(top[2].y),
        white,
    );
    playdate.graphics.fillTriangle(
        @intFromFloat(top[0].x),
        @intFromFloat(top[0].y),
        @intFromFloat(top[2].x),
        @intFromFloat(top[2].y),
        @intFromFloat(top[3].x),
        @intFromFloat(top[3].y),
        white,
    );

    for (0..4) |index| {
        line(playdate, top[index], top[(index + 1) % 4], 2, color);
    }

    playdate.graphics.fillTriangle(
        @intFromFloat(top_left.x),
        @intFromFloat(top_left.y),
        @intFromFloat(top_right.x),
        @intFromFloat(top_right.y),
        @intFromFloat(ground_right.x),
        @intFromFloat(ground_right.y),
        white,
    );
    playdate.graphics.fillTriangle(
        @intFromFloat(top_left.x),
        @intFromFloat(top_left.y),
        @intFromFloat(ground_right.x),
        @intFromFloat(ground_right.y),
        @intFromFloat(ground_left.x),
        @intFromFloat(ground_left.y),
        white,
    );

    line(playdate, top_left, top_right, 3, color);
    line(playdate, ground_left, ground_right, 3, color);
    line(playdate, ground_left, top_left, 2, color);
    line(playdate, ground_right, top_right, 2, color);
}

pub fn drawObstacle(
    playdate: *pdapi.PlaydateAPI,
    obstacle: collision.Rect,
    camera_state: camera.Camera,
    color: pdapi.LCDColor,
) void {
    drawProjectedRect(playdate, obstacle, 0, camera_state, 1, color);
}

pub fn drawShelf(
    playdate: *pdapi.PlaydateAPI,
    zone: collision.Rect,
    support_z: f32,
    camera_state: camera.Camera,
    color: pdapi.LCDColor,
) void {
    const world_corners = [_]math2.Vec2{
        .{ .x = zone.x, .y = zone.y },
        .{ .x = zone.x + zone.width, .y = zone.y },
        .{ .x = zone.x + zone.width, .y = zone.y +
            zone.height },
        .{ .x = zone.x, .y = zone.y + zone.height },
    };

    var ground: [4]math2.Vec2 = undefined;
    var top: [4]math2.Vec2 = undefined;

    for (world_corners, 0..) |corner, index| {
        ground[index] = projection.project(
            corner,
            0,
            camera_state,
            projection.default_tuning,
        );
        top[index] = projection.project(
            corner,
            support_z,
            camera_state,
            projection.default_tuning,
        );
    }

    for (0..4) |index| {
        const next = (index + 1) % 4;
        line(playdate, top[index], top[next], 2, color);
        line(playdate, ground[index], top[index], 1, color);
    }
}
