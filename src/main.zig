const std = @import("std");
const pdapi = @import("playdate_api_definitions.zig");
const panic_handler = @import("panic_handler.zig");
const math2 = @import("math2.zig");
const config = @import("config.zig");
const vehicle = @import("vehicle.zig");
const camera = @import("camera.zig");
const collision = @import("collision.zig");
const cargo = @import("cargo.zig");
const jobs = @import("jobs.zig");
const render25d = @import("render25d.zig");

pub const panic = panic_handler.panic;

const projection_tuning = render25d.ProjectionTuning{
    .z_skew_x = 0,
    .z_skew_y = 0.75,
    .perspective_strength = 0.001,
};

const tall_box_position = math2.Vec2{
    .x = 1000,
    .y = 150,
};

const destination = collision.Rect{
    .x = 950,
    .y = 600,
    .width = 100,
    .height = 100,
};

const occlusion_rack = collision.Rect{
    .x = 220,
    .y = 200,
    .width = 520,
    .height = 36,
};

const obstacles = [_]collision.Rect{
    occlusion_rack,
    .{ .x = 220, .y = 500, .width = 520, .height = 36 },
    .{ .x = 820, .y = 280, .width = 36, .height = 256 },
};

const pickup_tuning = cargo.PickupTuning{
    .max_angle_error_rad = 0.4,
    .tine_lateral_tolerance = 3,
    .minimum_insertion = 18,
};

const Game = struct {
    playdate: *pdapi.PlaydateAPI,
    font: *pdapi.LCDFont,
    forklift: vehicle.Forklift = .{
        .position = .{ .x = 600, .y = 400 },
    },
    debug_buffer: [192]u8 = undefined,
    camera: camera.Camera = .{},
    pallet: cargo.Pallet = .{
        .position = .{ .x = 600, .y = 330 },
    },
    job_state: jobs.JobState = .waiting_for_pickup,
    job_elapsed_seconds: f32 = 0,
};

pub export fn eventHandler(
    playdate: *pdapi.PlaydateAPI,
    event: pdapi.PDSystemEvent,
    arg: u32,
) callconv(.c) c_int {
    _ = arg;
    if (event != .EventInit) return 0;
    panic_handler.init(playdate);

    const font = playdate.graphics.loadFont(
        "/System/Fonts/Roobert-10-Bold.pft",
        null,
    ) orelse return 0;
    playdate.graphics.setFont(font);

    const game: *Game = @ptrCast(@alignCast(
        playdate.system.realloc(null, @sizeOf(Game)) orelse return 0,
    ));
    game.* = .{
        .playdate = playdate,
        .font = font,
    };

    playdate.system.resetElapsedTime();
    playdate.system.setUpdateCallback(updateAndRender, game);
    return 0;
}

fn updateAndRender(userdata: ?*anyopaque) callconv(.c) c_int {
    const game: *Game = @ptrCast(@alignCast(userdata.?));
    const playdate = game.playdate;

    var current: pdapi.PDButtons = 0;
    var pushed: pdapi.PDButtons = 0;
    playdate.system.getButtonState(&current, &pushed, null);

    const dt = @min(playdate.system.getElapsedTime(), 1.0 / 15.0);
    playdate.system.resetElapsedTime();

    const reset_held =
        (current & (pdapi.BUTTON_A | pdapi.BUTTON_B)) ==
        (pdapi.BUTTON_A | pdapi.BUTTON_B);
    if (reset_held) {
        game.pallet = .{
            .position = .{ .x = 600, .y = 330 },
        };
        game.forklift.reset(.{ .x = 600, .y = 400 });
        game.job_state = .waiting_for_pickup;
        game.job_elapsed_seconds = 0;
    }

    const previous_position = game.forklift.position;
    const previous_heading = game.forklift.heading_rad;
    const previous_pallet = game.pallet;

    vehicle.update(
        &game.forklift,
        .{
            .crank_delta_deg = playdate.system.getCrankChange(),
            .forward = current & pdapi.BUTTON_UP != 0,
            .reverse = current & pdapi.BUTTON_DOWN != 0,
        },
        if (game.pallet.state == .carried)
            config.carried_acceleration_multiplier
        else
            1.0,
        dt,
    );

    if (game.pallet.state == .carried) {
        cargo.followForks(&game.pallet, game.forklift);
    }

    if (forkliftCollides(game.forklift, game.pallet)) {
        game.forklift.position = previous_position;
        game.forklift.heading_rad = previous_heading;
        game.forklift.speed = 0;
        game.pallet = previous_pallet;
    }

    if (pushed & pdapi.BUTTON_A != 0) {
        _ = cargo.tryPickup(
            &game.pallet,
            game.forklift,
            pickup_tuning,
        );
    }

    if (game.pallet.state == .carried) {
        cargo.followForks(&game.pallet, game.forklift);
    }

    if (pushed & pdapi.BUTTON_B != 0) {
        cargo.drop(&game.pallet);
    }

    if (game.job_state != .delivered) {
        game.job_elapsed_seconds += dt;
        game.job_state = jobs.update(
            game.job_state,
            game.pallet,
            destination,
        );
    }

    camera.follow(&game.camera, game.forklift.position);

    draw(game);

    return 1;
}

fn draw(game: *Game) void {
    const playdate = game.playdate;
    var forklift = game.forklift;
    forklift.position = camera.worldToScreen(
        forklift.position,
        game.camera,
    );
    const black: pdapi.LCDColor = @intCast(@intFromEnum(pdapi.LCDSolidColor.ColorBlack));

    playdate.graphics.clear(@intCast(@intFromEnum(pdapi.LCDSolidColor.ColorWhite)));

    playdate.graphics.drawRect(
        @intFromFloat(-game.camera.position.x),
        @intFromFloat(-game.camera.position.y),
        @intFromFloat(config.world_width),
        @intFromFloat(config.world_height),
        black,
    );

    drawTallBox(playdate, tall_box_position, game.camera, black);

    drawRackBack(playdate, occlusion_rack, game.camera, black);
    const forklift_sort_y = if (game.pallet.state == .carried)
        @max(game.forklift.position.y, game.pallet.position.y)
    else
        game.forklift.position.y;
    const rack_front_after_entities =
        forklift_sort_y < occlusion_rack.y +
            occlusion_rack.height;

    if (!rack_front_after_entities) {
        drawRackFront(playdate, occlusion_rack, game.camera, black);
    }

    for (obstacles[1..]) |obstacle| {
        drawObstacle(playdate, obstacle, game.camera, black);
    }

    drawDestination(playdate, destination, game.camera, black);

    drawCone(playdate, .{ .x = 100, .y = 100 }, game.camera, black);
    drawCone(playdate, .{ .x = 1100, .y = 100 }, game.camera, black);
    drawCone(playdate, .{ .x = 100, .y = 700 }, game.camera, black);
    drawCone(playdate, .{ .x = 1100, .y = 700 }, game.camera, black);

    drawCone(playdate, .{ .x = 500, .y = 300 }, game.camera, black);
    drawCone(playdate, .{ .x = 600, .y = 260 }, game.camera, black);
    drawCone(playdate, .{ .x = 700, .y = 300 }, game.camera, black);
    drawCone(playdate, .{ .x = 700, .y = 500 }, game.camera, black);

    drawPalletShadow(
        playdate,
        game.pallet,
        game.camera,
        black,
    );
    drawPallet(playdate, game.pallet, game.camera, black);

    const pickup = cargo.evaluateForkEntry(
        game.forklift,
        game.pallet,
        pickup_tuning,
    );

    const forward = math2.forwardVector(forklift.heading_rad);
    const right = math2.Vec2{
        .x = @cos(forklift.heading_rad),
        .y = @sin(forklift.heading_rad),
    };

    const rear_axle = forklift.position;
    const body_center = vehicle.bodyCenter(forklift);
    const front = math2.scale(
        forward,
        vehicle.body_front_extent,
    );
    const rear = math2.scale(
        forward,
        vehicle.body_rear_extent,
    );
    const side = math2.scale(
        right,
        vehicle.body_half_width,
    );

    const front_left = math2.sub(math2.add(body_center, front), side);
    const front_right = math2.add(math2.add(body_center, front), side);
    const rear_left = math2.sub(math2.sub(body_center, rear), side);
    const rear_right = math2.add(math2.sub(body_center, rear), side);

    line(playdate, front_left, front_right, 2, black);
    line(playdate, front_right, rear_right, 2, black);
    line(playdate, rear_right, rear_left, 2, black);
    line(playdate, rear_left, front_left, 2, black);

    const forks = vehicle.forkGeometry(forklift);
    line(playdate, forks.left_base, forks.left_tip, 3, black);
    line(playdate, forks.right_base, forks.right_tip, 3, black);

    const wheel_direction = vehicle.rearWheelDirection(
        forklift.heading_rad,
        forklift.steer_angle_rad,
    );
    drawDriveArrow(playdate, rear_axle, wheel_direction, black);
    if (rack_front_after_entities) {
        drawRackFront(playdate, occlusion_rack, game.camera, black);
    }

    const job_label = switch (game.job_state) {
        .waiting_for_pickup => "PICK UP PALLET",
        .carrying => "DELIVER PALLET",
        .delivered => "JOB COMPLETE",
    };

    const text = std.fmt.bufPrint(
        &game.debug_buffer,
        "job={s}\ntime={d:.1}\npickup={}\ncarried={}\nangle={d:.0} depth={d:.1}\n",
        .{ job_label, game.job_elapsed_seconds, pickup.valid, game.pallet.state == .carried, pickup.angle_error_rad * 180.0 / std.math.pi, pickup.insertion_depth },
    ) catch unreachable;

    _ = playdate.graphics.drawText(text.ptr, text.len, .UTF8Encoding, 8, 8);
    playdate.system.drawFPS(320, 8);
}

fn line(
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

fn drawDriveArrow(
    playdate: *pdapi.PlaydateAPI,
    origin: math2.Vec2,
    direction: math2.Vec2,
    color: pdapi.LCDColor,
) void {
    const normal = math2.Vec2{
        .x = -direction.y,
        .y = direction.x,
    };
    const base = math2.sub(origin, math2.scale(direction, 10));
    const tip = math2.add(origin, math2.scale(direction, 12));
    const left_wing = math2.sub(
        math2.sub(tip, math2.scale(direction, 6)),
        math2.scale(normal, 4),
    );
    const right_wing = math2.add(
        math2.sub(tip, math2.scale(direction, 6)),
        math2.scale(normal, 4),
    );

    line(playdate, base, tip, 3, color);
    line(playdate, tip, left_wing, 2, color);
    line(playdate, tip, right_wing, 2, color);
}

fn drawCone(
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

fn forkliftCollides(forklift: vehicle.Forklift, pallet: cargo.Pallet) bool {
    for (obstacles) |obstacle| {
        if (collision.obbOverlapsRect(
            vehicle.bodyCollisionCenter(forklift),
            vehicle.body_half_length,
            vehicle.body_half_width,
            forklift.heading_rad,
            obstacle,
        )) return true;
        if (pallet.state == .carried and
            collision.obbOverlapsRect(
                pallet.position,
                pallet.footprint.half_length,
                pallet.footprint.half_width,
                pallet.heading_rad,
                obstacle,
            )) return true;
    }
    return false;
}

fn drawObstacle(
    playdate: *pdapi.PlaydateAPI,
    obstacle: collision.Rect,
    camera_state: camera.Camera,
    color: pdapi.LCDColor,
) void {
    const screen = camera.worldToScreen(
        .{ .x = obstacle.x, .y = obstacle.y },
        camera_state,
    );
    playdate.graphics.drawRect(
        @intFromFloat(screen.x),
        @intFromFloat(screen.y),
        @intFromFloat(obstacle.width),
        @intFromFloat(obstacle.height),
        color,
    );
}

fn drawPallet(
    playdate: *pdapi.PlaydateAPI,
    pallet: cargo.Pallet,
    camera_state: camera.Camera,
    color: pdapi.LCDColor,
) void {
    const center = render25d.project(
        pallet.position,
        pallet.z,
        camera_state,
        projection_tuning,
    );
    const forward =
        math2.forwardVector(pallet.heading_rad);
    const right = math2.Vec2{
        .x = @cos(pallet.heading_rad),
        .y = @sin(pallet.heading_rad),
    };
    const front = math2.scale(forward, pallet.footprint.half_length);
    const side = math2.scale(right, pallet.footprint.half_width);

    const front_left = math2.sub(math2.add(center, front), side);
    const front_right = math2.add(math2.add(center, front), side);
    const rear_left = math2.sub(math2.sub(center, front), side);
    const rear_right = math2.add(math2.sub(center, front), side);

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

    for (entry_turns) |turn| {
        drawPalletEntryLanes(
            playdate,
            center,
            pallet.heading_rad + turn,
            pallet.footprint.half_length,
            color,
        );
    }
}

fn drawPalletEntryLanes(
    playdate: *pdapi.PlaydateAPI,
    center: math2.Vec2,
    entry_heading_rad: f32,
    half_length: f32,
    color: pdapi.LCDColor,
) void {
    const forward = math2.forwardVector(entry_heading_rad);
    const right = math2.Vec2{
        .x = @cos(entry_heading_rad),
        .y = @sin(entry_heading_rad),
    };
    const entry_start = math2.sub(center, math2.scale(forward, half_length));
    const left_entry = math2.sub(entry_start, math2.scale(right, 5));
    const right_entry = math2.add(entry_start, math2.scale(right, 5));
    const entry_length = math2.scale(forward, 24);

    line(playdate, left_entry, math2.add(left_entry, entry_length), 1, color);
    line(playdate, right_entry, math2.add(right_entry, entry_length), 1, color);
}

fn drawPalletShadow(
    playdate: *pdapi.PlaydateAPI,
    pallet: cargo.Pallet,
    camera_state: camera.Camera,
    color: pdapi.LCDColor,
) void {
    if (pallet.z <= 0) return;

    const center = render25d.project(
        pallet.position,
        0,
        camera_state,
        projection_tuning,
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

fn drawDestination(
    playdate: *pdapi.PlaydateAPI,
    zone: collision.Rect,
    camera_state: camera.Camera,
    color: pdapi.LCDColor,
) void {
    const top_left = camera.worldToScreen(
        .{ .x = zone.x, .y = zone.y },
        camera_state,
    );
    const bottom_right = math2.Vec2{
        .x = top_left.x + zone.width,
        .y = top_left.y + zone.height,
    };
    playdate.graphics.drawRect(@intFromFloat(top_left.x), @intFromFloat(top_left.y), @intFromFloat(zone.width), @intFromFloat(zone.height), color);
    line(playdate, top_left, bottom_right, 1, color);
    line(playdate, .{ .x = top_left.x + zone.width, .y = top_left.y }, .{ .x = top_left.x, .y = top_left.y + zone.height }, 1, color);
}

fn drawTallBox(
    playdate: *pdapi.PlaydateAPI,
    world_position: math2.Vec2,
    camera_state: camera.Camera,
    color: pdapi.LCDColor,
) void {
    const base = render25d.project(
        world_position,
        0,
        camera_state,
        projection_tuning,
    );
    const top = render25d.project(
        world_position,
        48,
        camera_state,
        projection_tuning,
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

fn drawRackBack(
    playdate: *pdapi.PlaydateAPI,
    rack: collision.Rect,
    camera_state: camera.Camera,
    color: pdapi.LCDColor,
) void {
    const top_left = camera.worldToScreen(
        .{ .x = rack.x, .y = rack.y },
        camera_state,
    );

    playdate.graphics.drawRect(
        @intFromFloat(top_left.x),
        @intFromFloat(top_left.y),
        @intFromFloat(rack.width),
        @intFromFloat(rack.height),
        color,
    );

    line(
        playdate,
        .{ .x = top_left.x, .y = top_left.y + 10 },
        .{ .x = top_left.x + rack.width, .y = top_left.y +
            10 },
        1,
        color,
    );
}

fn drawRackFront(
    playdate: *pdapi.PlaydateAPI,
    rack: collision.Rect,
    camera_state: camera.Camera,
    color: pdapi.LCDColor,
) void {
    const white: pdapi.LCDColor =
        @intCast(@intFromEnum(pdapi.LCDSolidColor.ColorWhite));

    const front_left_world = math2.Vec2{
        .x = rack.x,
        .y = rack.y + rack.height,
    };
    const front_right_world = math2.Vec2{
        .x = rack.x + rack.width,
        .y = rack.y + rack.height,
    };

    const ground_left = render25d.project(
        front_left_world,
        0,
        camera_state,
        projection_tuning,
    );
    const ground_right = render25d.project(
        front_right_world,
        0,
        camera_state,
        projection_tuning,
    );
    const top_left = render25d.project(
        front_left_world,
        80,
        camera_state,
        projection_tuning,
    );
    const top_right = render25d.project(
        front_right_world,
        80,
        camera_state,
        projection_tuning,
    );

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
