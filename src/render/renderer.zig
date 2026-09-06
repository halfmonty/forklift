const std = @import("std");
const pdapi = @import("../playdate_api_definitions.zig");
const vehicle = @import("../sim/vehicle.zig");
const camera = @import("camera.zig");
const math2 = @import("../sim/math2.zig");
const projection = @import("projection.zig");
const cargo = @import("../sim/cargo.zig");
const collision = @import("../sim/collision.zig");

const black: pdapi.LCDColor = @intCast(@intFromEnum(pdapi.LCDSolidColor.ColorBlack));

const RackEdge = struct {
    start: math2.Vec2,
    end: math2.Vec2,
    outward_normal: math2.Vec2,
};

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
        const visible = self.isRectVisible(rect);

        if (visible) {
            self.stats.submitted += 1;
        } else {
            self.stats.culled += 1;
        }
        return visible;
    }

    pub fn isRectVisible(self: Renderer, rect: collision.Rect) bool {
        const bounds = camera.visibleWorldBounds(self.camera_state);
        return rect.x + rect.width >= bounds.min.x - self.cull_margin and
            rect.x <= bounds.max.x + self.cull_margin and
            rect.y + rect.height >= bounds.min.y - self.cull_margin and
            rect.y <= bounds.max.y + self.cull_margin;
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

    pub fn floorExpansionJoints(
        self: *Renderer,
        world_size: math2.Vec2,
        cell_size: math2.Vec2,
    ) void {
        const bounds = camera.visibleWorldBounds(self.camera_state);
        const minimum_x = @max(0, bounds.min.x - self.cull_margin);
        const maximum_x = @min(world_size.x, bounds.max.x + self.cull_margin);
        const minimum_y = @max(0, bounds.min.y - self.cull_margin);
        const maximum_y = @min(world_size.y, bounds.max.y + self.cull_margin);

        var x = @max(0, @floor(minimum_x / cell_size.x) * cell_size.x);
        while (x <= maximum_x) : (x += cell_size.x) {
            line(
                self.playdate,
                projection.project(.{ .x = x, .y = 0 }, 0, self.camera_state, projection.default_tuning),
                projection.project(.{ .x = x, .y = world_size.y }, 0, self.camera_state, projection.default_tuning),
                1,
                black,
            );
        }

        var y = @max(0, @floor(minimum_y / cell_size.y) * cell_size.y);
        while (y <= maximum_y) : (y += cell_size.y) {
            line(
                self.playdate,
                projection.project(.{ .x = 0, .y = y }, 0, self.camera_state, projection.default_tuning),
                projection.project(.{ .x = world_size.x, .y = y }, 0, self.camera_state, projection.default_tuning),
                1,
                black,
            );
        }
    }

    pub fn rackBack(self: *Renderer, rack: collision.Rect) void {
        if (!self.acceptsRect(rack)) return;
        drawRackBack(self.playdate, rack, self.camera_state, black);
    }

    pub fn rackFront(
        self: *Renderer,
        rack: collision.Rect,
        actor_depth: f32,
        draw_before_actors: bool,
    ) void {
        if (!self.acceptsRect(rack)) return;
        drawRackFront(
            self.playdate,
            rack,
            self.camera_state,
            actor_depth,
            draw_before_actors,
            black,
        );
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

    pub fn opaqueSurface(
        self: *Renderer,
        zone: collision.Rect,
        support_z: f32,
    ) void {
        drawShelf(self.playdate, zone, support_z, self.camera_state, black);
    }

    pub fn opaqueSurfaceFragment(
        self: *Renderer,
        zone: collision.Rect,
        support_z: f32,
        depth_min: f32,
        depth_max: f32,
        draw_legs_before: bool,
        draw_front_legs_after: bool,
    ) void {
        drawShelfFragment(
            self.playdate,
            zone,
            support_z,
            depth_min,
            depth_max,
            draw_legs_before,
            draw_front_legs_after,
            self.camera_state,
            black,
        );
    }

    pub fn palletShadow(self: *Renderer, pallet_data: cargo.Pallet) void {
        if (!self.acceptsPallet(pallet_data)) return;
        drawPalletShadow(self.playdate, pallet_data, self.camera_state, black);
    }

    pub fn pallet(self: *Renderer, pallet_data: cargo.Pallet) void {
        if (!self.acceptsPallet(pallet_data)) return;
        drawPallet(self.playdate, pallet_data, self.camera_state, black);
    }

    pub fn forkliftBase(self: *Renderer, forklift_data: vehicle.Forklift) void {
        self.stats.submitted += 1;
        drawForkliftBase(self.playdate, forklift_data, self.camera_state);
    }

    pub fn forkliftCanopy(self: *Renderer, forklift_data: vehicle.Forklift) void {
        self.stats.submitted += 1;
        drawForkliftCanopy(self.playdate, forklift_data, self.camera_state);
    }

    pub fn forkliftMast(self: *Renderer, forklift_data: vehicle.Forklift) void {
        self.stats.submitted += 1;
        drawForkliftMast(self.playdate, forklift_data, self.camera_state);
    }

    pub fn forkliftForks(self: *Renderer, forklift_data: vehicle.Forklift) void {
        self.stats.submitted += 1;
        drawForkliftForks(self.playdate, forklift_data, self.camera_state);
    }
};

pub fn canopyBehindForks(
    forklift: vehicle.Forklift,
    camera_state: camera.Camera,
) bool {
    const forward = math2.forwardVector(forklift.heading_rad);
    const right = math2.Vec2{
        .x = @cos(forklift.heading_rad),
        .y = @sin(forklift.heading_rad),
    };
    const canopy_center = offsetPoint(
        vehicle.bodyCenter(forklift),
        forward,
        right,
        -4,
        0,
    );
    const forks = vehicle.forkGeometry(forklift);
    const fork_center = math2.Vec2{
        .x = (forks.left_base.x + forks.right_tip.x) * 0.5,
        .y = (forks.left_base.y + forks.right_tip.y) * 0.5,
    };
    return camera.depth(canopy_center, camera_state) <
        camera.depth(fork_center, camera_state);
}

pub fn drawForkliftBase(
    playdate: *pdapi.PlaydateAPI,
    forklift: vehicle.Forklift,
    camera_state: camera.Camera,
) void {
    const white: pdapi.LCDColor =
        @intCast(@intFromEnum(pdapi.LCDSolidColor.ColorWhite));
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
}

pub fn drawForkliftMast(
    playdate: *pdapi.PlaydateAPI,
    forklift: vehicle.Forklift,
    camera_state: camera.Camera,
) void {
    const forks = vehicle.forkGeometry(forklift);
    const mast_top_z: f32 = 68;
    const left_mast_base = projection.project(forks.left_base, 0, camera_state, projection.default_tuning);
    const right_mast_base = projection.project(forks.right_base, 0, camera_state, projection.default_tuning);
    const left_mast_top = projection.project(forks.left_base, mast_top_z, camera_state, projection.default_tuning);
    const right_mast_top = projection.project(forks.right_base, mast_top_z, camera_state, projection.default_tuning);

    line(playdate, left_mast_base, left_mast_top, 2, black);
    line(playdate, right_mast_base, right_mast_top, 2, black);
    line(playdate, left_mast_top, right_mast_top, 2, black);
}

pub fn drawForkliftCanopy(
    playdate: *pdapi.PlaydateAPI,
    forklift: vehicle.Forklift,
    camera_state: camera.Camera,
) void {
    const white: pdapi.LCDColor =
        @intCast(@intFromEnum(pdapi.LCDSolidColor.ColorWhite));
    const forward = math2.forwardVector(forklift.heading_rad);
    const right = math2.Vec2{
        .x = @cos(forklift.heading_rad),
        .y = @sin(forklift.heading_rad),
    };
    const body_center = vehicle.bodyCenter(forklift);
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

pub fn drawForkliftForks(
    playdate: *pdapi.PlaydateAPI,
    forklift: vehicle.Forklift,
    camera_state: camera.Camera,
) void {
    const fork_z = vehicle.forkZ(forklift.fork_height);
    const forks = vehicle.forkGeometry(forklift);
    const left_base = projection.project(forks.left_base, fork_z, camera_state, projection.default_tuning);
    const left_tip = projection.project(forks.left_tip, fork_z, camera_state, projection.default_tuning);
    const right_base = projection.project(forks.right_base, fork_z, camera_state, projection.default_tuning);
    const right_tip = projection.project(forks.right_tip, fork_z, camera_state, projection.default_tuning);

    line(playdate, left_base, left_tip, 3, black);
    line(playdate, right_base, right_tip, 3, black);
    line(playdate, left_base, right_base, 3, black);
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

    const white: pdapi.LCDColor =
        @intCast(@intFromEnum(pdapi.LCDSolidColor.ColorWhite));
    playdate.graphics.fillTriangle(
        @intFromFloat(front_left.x),
        @intFromFloat(front_left.y),
        @intFromFloat(front_right.x),
        @intFromFloat(front_right.y),
        @intFromFloat(rear_right.x),
        @intFromFloat(rear_right.y),
        white,
    );
    playdate.graphics.fillTriangle(
        @intFromFloat(front_left.x),
        @intFromFloat(front_left.y),
        @intFromFloat(rear_right.x),
        @intFromFloat(rear_right.y),
        @intFromFloat(rear_left.x),
        @intFromFloat(rear_left.y),
        white,
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

fn rackEdges(rack: collision.Rect) [4]RackEdge {
    return .{
        .{ .start = .{ .x = rack.x, .y = rack.y }, .end = .{ .x = rack.x + rack.width, .y = rack.y }, .outward_normal = .{ .x = 0, .y = -1 } },
        .{ .start = .{ .x = rack.x + rack.width, .y = rack.y }, .end = .{ .x = rack.x + rack.width, .y = rack.y + rack.height }, .outward_normal = .{ .x = 1, .y = 0 } },
        .{ .start = .{ .x = rack.x + rack.width, .y = rack.y + rack.height }, .end = .{ .x = rack.x, .y = rack.y + rack.height }, .outward_normal = .{ .x = 0, .y = 1 } },
        .{ .start = .{ .x = rack.x, .y = rack.y + rack.height }, .end = .{ .x = rack.x, .y = rack.y }, .outward_normal = .{ .x = -1, .y = 0 } },
    };
}

fn rackEdgeFacesCamera(edge: RackEdge, camera_state: camera.Camera) bool {
    const camera_front = math2.Vec2{
        .x = @sin(camera_state.yaw_rad),
        .y = @cos(camera_state.yaw_rad),
    };
    return math2.dot(edge.outward_normal, camera_front) > 0.001;
}

fn rackEdgeDepth(edge: RackEdge, camera_state: camera.Camera) f32 {
    return camera.depth(.{
        .x = (edge.start.x + edge.end.x) * 0.5,
        .y = (edge.start.y + edge.end.y) * 0.5,
    }, camera_state);
}

fn shouldDrawRackPart(actor_depth: f32, rack_part_depth: f32, draw_before_actors: bool) bool {
    return if (draw_before_actors) actor_depth >= rack_part_depth else actor_depth < rack_part_depth;
}

fn drawRackFront(
    playdate: *pdapi.PlaydateAPI,
    rack: collision.Rect,
    camera_state: camera.Camera,
    actor_depth: f32,
    draw_before_actors: bool,
    color: pdapi.LCDColor,
) void {
    const edges = rackEdges(rack);
    var maximum_facing_depth: ?f32 = null;
    for (edges) |edge| {
        if (!rackEdgeFacesCamera(edge, camera_state)) continue;
        const edge_depth = rackEdgeDepth(edge, camera_state);
        maximum_facing_depth = if (maximum_facing_depth) |maximum|
            @max(maximum, edge_depth)
        else
            edge_depth;
    }

    const front_depth = maximum_facing_depth orelse unreachable;
    if (shouldDrawRackPart(actor_depth, front_depth, draw_before_actors)) {
        drawRackTop(playdate, rack, camera_state, color);
    }

    for (edges) |edge| {
        if (!rackEdgeFacesCamera(edge, camera_state)) continue;
        if (!shouldDrawRackPart(actor_depth, rackEdgeDepth(edge, camera_state), draw_before_actors)) continue;
        drawRackWall(playdate, edge, camera_state, color);
    }
}

fn drawRackTop(
    playdate: *pdapi.PlaydateAPI,
    rack: collision.Rect,
    camera_state: camera.Camera,
    color: pdapi.LCDColor,
) void {
    const white: pdapi.LCDColor =
        @intCast(@intFromEnum(pdapi.LCDSolidColor.ColorWhite));

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
}

fn drawRackWall(
    playdate: *pdapi.PlaydateAPI,
    edge: RackEdge,
    camera_state: camera.Camera,
    color: pdapi.LCDColor,
) void {
    const white: pdapi.LCDColor =
        @intCast(@intFromEnum(pdapi.LCDSolidColor.ColorWhite));
    const ground_left = projection.project(edge.start, 0, camera_state, projection.default_tuning);
    const ground_right = projection.project(edge.end, 0, camera_state, projection.default_tuning);
    const top_left = projection.project(edge.start, 80, camera_state, projection.default_tuning);
    const top_right = projection.project(edge.end, 80, camera_state, projection.default_tuning);

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

test "rack-facing edges follow camera yaw" {
    const rack = collision.Rect{ .x = 10, .y = 20, .width = 30, .height = 40 };
    const edges = rackEdges(rack);
    const cases = [_]struct { yaw_rad: f32, facing: [4]bool }{
        .{ .yaw_rad = 0, .facing = .{ false, false, true, false } },
        .{ .yaw_rad = std.math.pi / 2.0, .facing = .{ false, true, false, false } },
        .{ .yaw_rad = std.math.pi / 4.0, .facing = .{ false, true, true, false } },
        .{ .yaw_rad = 3.0 * std.math.pi / 2.0, .facing = .{ false, false, false, true } },
    };

    for (cases) |case| {
        const camera_state = camera.Camera{ .yaw_rad = case.yaw_rad };
        for (edges, 0..) |edge, index| {
            try std.testing.expectEqual(case.facing[index], rackEdgeFacesCamera(edge, camera_state));
        }
    }
}

test "canopy is behind forks only when the lift faces the camera" {
    const camera_state = camera.Camera{};
    const toward_camera = vehicle.Forklift{
        .position = .{ .x = 100, .y = 100 },
        .heading_rad = std.math.pi,
    };
    const away_from_camera = vehicle.Forklift{
        .position = .{ .x = 100, .y = 100 },
        .heading_rad = 0,
    };

    try std.testing.expect(canopyBehindForks(toward_camera, camera_state));
    try std.testing.expect(!canopyBehindForks(away_from_camera, camera_state));
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

    var front_depth = camera.depth(world_corners[0], camera_state);
    for (world_corners[1..]) |corner| {
        front_depth = @max(front_depth, camera.depth(corner, camera_state));
    }

    // Back legs are behind the opaque shelf surface.
    for (0..4) |index| {
        line(playdate, ground[index], top[index], 1, color);
    }

    const white: pdapi.LCDColor =
        @intCast(@intFromEnum(pdapi.LCDSolidColor.ColorWhite));
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
        const next = (index + 1) % 4;
        line(playdate, top[index], top[next], 2, color);
        if (camera.depth(world_corners[index], camera_state) >= front_depth - 0.001) {
            line(playdate, ground[index], top[index], 1, color);
        }
    }
}

const max_shelf_fragment_points = 8;

const WorldPolygon = struct {
    points: [max_shelf_fragment_points]math2.Vec2 = undefined,
    len: usize = 0,
};

fn drawShelfFragment(
    playdate: *pdapi.PlaydateAPI,
    zone: collision.Rect,
    support_z: f32,
    depth_min: f32,
    depth_max: f32,
    draw_legs_before: bool,
    draw_front_legs_after: bool,
    camera_state: camera.Camera,
    color: pdapi.LCDColor,
) void {
    const corners = shelfWorldCorners(zone);

    if (draw_legs_before) {
        for (corners) |corner| {
            drawShelfLeg(playdate, corner, support_z, camera_state, color);
        }
    }

    const polygon = clipShelfToDepthBand(zone, depth_min, depth_max, camera_state);
    if (polygon.len >= 3) {
        const white: pdapi.LCDColor =
            @intCast(@intFromEnum(pdapi.LCDSolidColor.ColorWhite));
        const origin = projection.project(
            polygon.points[0],
            support_z,
            camera_state,
            projection.default_tuning,
        );
        for (1..polygon.len - 1) |index| {
            const second = projection.project(
                polygon.points[index],
                support_z,
                camera_state,
                projection.default_tuning,
            );
            const third = projection.project(
                polygon.points[index + 1],
                support_z,
                camera_state,
                projection.default_tuning,
            );
            playdate.graphics.fillTriangle(
                @intFromFloat(origin.x),
                @intFromFloat(origin.y),
                @intFromFloat(second.x),
                @intFromFloat(second.y),
                @intFromFloat(third.x),
                @intFromFloat(third.y),
                white,
            );
        }
    }

    // Draw only original perimeter segments. Clipping boundaries are internal to
    // the shelf and must not appear as lines while the camera rotates.
    for (0..4) |index| {
        const segment = clipSegmentToDepthBand(
            corners[index],
            corners[(index + 1) % 4],
            depth_min,
            depth_max,
            camera_state,
        ) orelse continue;
        line(
            playdate,
            projection.project(segment[0], support_z, camera_state, projection.default_tuning),
            projection.project(segment[1], support_z, camera_state, projection.default_tuning),
            2,
            color,
        );
    }

    if (draw_front_legs_after) {
        var front_depth = camera.depth(corners[0], camera_state);
        for (corners[1..]) |corner| {
            front_depth = @max(front_depth, camera.depth(corner, camera_state));
        }
        for (corners) |corner| {
            if (camera.depth(corner, camera_state) >= front_depth - 0.001) {
                drawShelfLeg(playdate, corner, support_z, camera_state, color);
            }
        }
    }
}

fn shelfWorldCorners(zone: collision.Rect) [4]math2.Vec2 {
    return .{
        .{ .x = zone.x, .y = zone.y },
        .{ .x = zone.x + zone.width, .y = zone.y },
        .{ .x = zone.x + zone.width, .y = zone.y + zone.height },
        .{ .x = zone.x, .y = zone.y + zone.height },
    };
}

fn drawShelfLeg(
    playdate: *pdapi.PlaydateAPI,
    position: math2.Vec2,
    support_z: f32,
    camera_state: camera.Camera,
    color: pdapi.LCDColor,
) void {
    line(
        playdate,
        projection.project(position, 0, camera_state, projection.default_tuning),
        projection.project(position, support_z, camera_state, projection.default_tuning),
        1,
        color,
    );
}

fn clipShelfToDepthBand(
    zone: collision.Rect,
    depth_min: f32,
    depth_max: f32,
    camera_state: camera.Camera,
) WorldPolygon {
    var polygon = WorldPolygon{ .len = 4 };
    const corners = shelfWorldCorners(zone);
    @memcpy(polygon.points[0..4], corners[0..]);
    polygon = clipPolygonAtDepth(polygon, depth_min, true, camera_state);
    return clipPolygonAtDepth(polygon, depth_max, false, camera_state);
}

fn clipPolygonAtDepth(
    input: WorldPolygon,
    threshold: f32,
    keep_greater: bool,
    camera_state: camera.Camera,
) WorldPolygon {
    var output = WorldPolygon{};
    if (input.len == 0) return output;

    var previous = input.points[input.len - 1];
    var previous_depth = camera.depth(previous, camera_state);
    var previous_inside = depthInside(previous_depth, threshold, keep_greater);

    for (input.points[0..input.len]) |current| {
        const current_depth = camera.depth(current, camera_state);
        const current_inside = depthInside(current_depth, threshold, keep_greater);

        if (current_inside != previous_inside) {
            const denominator = current_depth - previous_depth;
            const amount = if (@abs(denominator) < 0.0001)
                0.0
            else
                (threshold - previous_depth) / denominator;
            appendPolygonPoint(&output, .{
                .x = previous.x + (current.x - previous.x) * amount,
                .y = previous.y + (current.y - previous.y) * amount,
            });
        }
        if (current_inside) appendPolygonPoint(&output, current);

        previous = current;
        previous_depth = current_depth;
        previous_inside = current_inside;
    }
    return output;
}

fn depthInside(depth: f32, threshold: f32, keep_greater: bool) bool {
    return if (keep_greater) depth >= threshold - 0.001 else depth <= threshold + 0.001;
}

fn appendPolygonPoint(polygon: *WorldPolygon, point: math2.Vec2) void {
    if (polygon.len == polygon.points.len) @panic("shelf fragment polygon capacity exceeded");
    polygon.points[polygon.len] = point;
    polygon.len += 1;
}

fn clipSegmentToDepthBand(
    start: math2.Vec2,
    end: math2.Vec2,
    depth_min: f32,
    depth_max: f32,
    camera_state: camera.Camera,
) ?[2]math2.Vec2 {
    const start_depth = camera.depth(start, camera_state);
    const end_depth = camera.depth(end, camera_state);
    const depth_delta = end_depth - start_depth;

    if (@abs(depth_delta) < 0.0001) {
        if (start_depth < depth_min - 0.001 or start_depth > depth_max + 0.001) return null;
        return .{ start, end };
    }

    const first = (depth_min - start_depth) / depth_delta;
    const second = (depth_max - start_depth) / depth_delta;
    const amount_min = @max(@as(f32, 0), @min(first, second));
    const amount_max = @min(@as(f32, 1), @max(first, second));
    if (amount_min > amount_max + 0.001) return null;

    return .{
        .{
            .x = start.x + (end.x - start.x) * amount_min,
            .y = start.y + (end.y - start.y) * amount_min,
        },
        .{
            .x = start.x + (end.x - start.x) * amount_max,
            .y = start.y + (end.y - start.y) * amount_max,
        },
    };
}
