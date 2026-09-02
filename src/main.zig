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
const render = @import("render.zig");

const stress_mode = true;
const render_cull_margin: f32 = 50;

const normal_obstacles = [_]collision.Rect{
    occlusion_rack,
    .{ .x = 220, .y = 500, .width = 520, .height = 36 },
    .{ .x = 820, .y = 280, .width = 36, .height = 256 },
};

const stress_obstacles = normal_obstacles ++ [_]collision.Rect{
    .{ .x = 40, .y = 40, .width = 160, .height = 28 },
    .{ .x = 260, .y = 40, .width = 160, .height = 28 },
    .{ .x = 480, .y = 40, .width = 160, .height = 28 },
    .{ .x = 700, .y = 40, .width = 160, .height = 28 },
    .{ .x = 920, .y = 40, .width = 160, .height = 28 },

    .{ .x = 40, .y = 732, .width = 160, .height = 28 },
    .{ .x = 260, .y = 732, .width = 160, .height = 28 },
    .{ .x = 480, .y = 732, .width = 160, .height = 28 },
    .{ .x = 700, .y = 732, .width = 160, .height = 28 },
    .{ .x = 920, .y = 732, .width = 160, .height = 28 },
};

const stress_pallets = [_]cargo.Pallet{
    .{ .position = .{ .x = 440, .y = 330 } },
    .{ .position = .{ .x = 500, .y = 330 } },
    .{ .position = .{ .x = 560, .y = 330 } },
    .{ .position = .{ .x = 620, .y = 330 } },
    .{ .position = .{ .x = 680, .y = 330 } },
    .{ .position = .{ .x = 440, .y = 410 } },
    .{ .position = .{ .x = 500, .y = 410 } },
    .{ .position = .{ .x = 560, .y = 410 } },
    .{ .position = .{ .x = 620, .y = 410 } },
    .{ .position = .{ .x = 680, .y = 410 } },
    .{
        .position = .{ .x = 740, .y = 330 },
        .cargo = cargo.long_cargo,
        .footprint = cargo.long_cargo.footprint,
    },
    .{
        .position = .{ .x = 740, .y = 440 },
        .cargo = cargo.heavy_cargo,
        .footprint = cargo.heavy_cargo.footprint,
    },
};

const stress_racks = [_]collision.Rect{
    .{ .x = 280, .y = 180, .width = 160, .height = 36 },
    .{ .x = 520, .y = 180, .width = 160, .height = 36 },
    .{ .x = 760, .y = 180, .width = 160, .height = 36 },
    .{ .x = 280, .y = 300, .width = 160, .height = 36 },
    .{ .x = 520, .y = 300, .width = 160, .height = 36 },
    .{ .x = 760, .y = 300, .width = 160, .height = 36 },
    .{ .x = 280, .y = 540, .width = 160, .height = 36 },
    .{ .x = 640, .y = 540, .width = 160, .height = 36 },
};

const obstacles: []const collision.Rect =
    if (stress_mode)
        &stress_obstacles
    else
        &normal_obstacles;

pub const panic = panic_handler.panic;

const projection_tuning = render25d.default_tuning;

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

const Shelf = struct {
    zone: collision.Rect,
    support_z: f32,
};

const rack_low_shelf = Shelf{
    .zone = .{
        .x = 960,
        .y = 380,
        .width = 100,
        .height = 100,
    },
    .support_z = vehicle.forkZ(.rack_low),
};

const pickup_tuning = cargo.PickupTuning{
    .max_angle_error_rad = 0.4,
    .tine_lateral_tolerance = 3,
    .minimum_insertion = 18,
};

const jobs_data = [_]jobs.JobDefinition{
    .{
        .pallet_spawn = .{
            .position = .{ .x = 600, .y = 300 },
        },
        .destination = destination,
        .cargo = cargo.standard_cargo,
    },
    .{
        .pallet_spawn = .{
            .position = .{ .x = 300, .y = 600 },
        },
        .destination = .{
            .x = 900,
            .y = 550,
            .width = 75,
            .height = 75,
        },
        .cargo = cargo.heavy_cargo,
    },
    .{
        .pallet_spawn = .{
            .position = .{ .x = 1010, .y = 430 },
            .support_z = vehicle.forkZ(.rack_low),
        },
        .destination = .{
            .x = 500,
            .y = 600,
            .width = 100,
            .height = 100,
        },
        .cargo = cargo.standard_cargo,
    },
    .{
        .pallet_spawn = .{
            .position = .{ .x = 600, .y = 650 },
        },
        .destination = .{
            .x = 880,
            .y = 100,
            .width = 120,
            .height = 120,
        },
        .cargo = cargo.long_cargo,
    },
};

fn palletForJob(job: jobs.JobDefinition) cargo.Pallet {
    return .{
        .position = job.pallet_spawn.position,
        .z = job.pallet_spawn.support_z,
        .support_z = job.pallet_spawn.support_z,
        .cargo = job.cargo,
        .footprint = job.cargo.footprint,
    };
}

pub const Game = struct {
    playdate: *pdapi.PlaydateAPI,
    font: *pdapi.LCDFont,
    forklift: vehicle.Forklift = .{
        .position = .{ .x = 600, .y = 400 },
    },
    debug_buffer: [192]u8 = undefined,
    camera: camera.Camera = .{},
    job_index: usize = 0,
    pallet: cargo.Pallet = palletForJob(jobs_data[0]),
    job_state: jobs.JobState = .waiting_for_pickup,
    job_elapsed_seconds: f32 = 0,
    fame_ms: f32 = 0,
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
    playdate.display.setRefreshRate(50);

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

    const raw_dt = playdate.system.getElapsedTime();
    const dt = @min(raw_dt, 1.0 / 15.0);
    game.fame_ms = raw_dt * 1000.0;
    playdate.system.resetElapsedTime();

    const reset_held =
        (current & (pdapi.BUTTON_A | pdapi.BUTTON_B)) ==
        (pdapi.BUTTON_A | pdapi.BUTTON_B);
    if (reset_held) {
        game.forklift.reset(.{ .x = 600, .y = 400 });
        game.job_index = 0;
        game.pallet = palletForJob(jobs_data[game.job_index]);
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
            game.pallet.cargo.carried_acceleration_multiplier
        else
            1.0,
        dt,
    );

    const lateral_pressed =
        pushed & (pdapi.BUTTON_LEFT | pdapi.BUTTON_RIGHT);
    const rotate_view_pressed =
        current & pdapi.BUTTON_B != 0 and
        pushed & pdapi.BUTTON_RIGHT != 0;

    if (rotate_view_pressed) {
        camera.rotateClockwise(&game.camera);
    } else if (lateral_pressed & pdapi.BUTTON_RIGHT != 0) {
        vehicle.raiseForks(&game.forklift);
    } else if (lateral_pressed & pdapi.BUTTON_LEFT != 0) {
        vehicle.lowerForks(&game.forklift);
    }

    if (game.pallet.state == .carried) {
        cargo.followForks(&game.pallet, game.forklift);
    }

    if (forkliftCollides(game.forklift, game.pallet)) {
        game.forklift.position = previous_position;
        game.forklift.heading_rad = previous_heading;
        game.forklift.speed = 0;
        game.pallet = previous_pallet;
    }

    const pickup_height_matches =
        @abs(
            vehicle.forkZ(game.forklift.fork_height) -
                game.pallet.support_z,
        ) < 0.1;

    if (pushed & pdapi.BUTTON_A != 0 and pickup_height_matches) {
        if (cargo.tryPickup(
            &game.pallet,
            game.forklift,
            pickup_tuning,
        )) {
            if (game.forklift.fork_height == .floor) {
                game.forklift.fork_height = .carry;
            }
        }
    }

    if (game.pallet.state == .carried) {
        cargo.followForks(&game.pallet, game.forklift);
        game.pallet.z = vehicle.forkZ(game.forklift.fork_height);
    }

    if (!rotate_view_pressed and pushed & pdapi.BUTTON_B != 0 and
        game.pallet.state == .carried)
    {
        if (game.forklift.fork_height == .floor) {
            cargo.drop(&game.pallet);
        } else if (game.forklift.fork_height == .rack_low and
            palletFitsShelf(game.pallet, rack_low_shelf))
        {
            cargo.dropAt(&game.pallet, rack_low_shelf.support_z);
        }
    }

    if (game.job_state != .delivered) {
        game.job_elapsed_seconds += dt;
        game.job_state = jobs.update(
            game.job_state,
            game.pallet,
            jobs_data[game.job_index].destination,
        );
        if (game.job_state == .delivered and
            game.job_index + 1 < jobs_data.len)
        {
            game.job_index += 1;
            game.pallet = palletForJob(jobs_data[game.job_index]);
            game.job_state = .waiting_for_pickup;
            game.job_elapsed_seconds = 0;
        }
    }

    camera.follow(&game.camera, game.forklift.position);

    draw(game);

    return 1;
}

fn draw(game: *Game) void {
    const playdate = game.playdate;
    const black: pdapi.LCDColor = @intCast(@intFromEnum(pdapi.LCDSolidColor.ColorBlack));

    playdate.graphics.clear(@intCast(@intFromEnum(pdapi.LCDSolidColor.ColorWhite)));

    render.drawTallBox(playdate, tall_box_position, game.camera, black);

    render.drawRackBack(playdate, occlusion_rack, game.camera, black);

    if (stress_mode) {
        for (stress_racks) |rack| {
            if (!rectMayBeVisible(rack, game.camera)) continue;
            render.drawRackBack(
                playdate,
                rack,
                game.camera,
                black,
            );
        }
    }

    const entity_depth = if (game.pallet.state == .carried)
        @max(
            camera.depth(game.forklift.position, game.camera),
            camera.depth(game.pallet.position, game.camera),
        )
    else
        camera.depth(game.forklift.position, game.camera);

    const rack_front_after_entities =
        entity_depth < render.rackFrontDepth(
            occlusion_rack,
            game.camera,
        );

    if (!rack_front_after_entities) {
        render.drawRackFront(playdate, occlusion_rack, game.camera, black);
    }

    if (stress_mode) {
        for (stress_racks) |rack| {
            if (!rectMayBeVisible(rack, game.camera)) continue;
            render.drawRackFront(
                playdate,
                rack,
                game.camera,
                black,
            );
        }
    }

    for (obstacles[1..]) |obstacle| {
        render.drawObstacle(playdate, obstacle, game.camera, black);
    }

    render.drawDestination(playdate, jobs_data[game.job_index].destination, game.camera, black);

    render.drawCone(playdate, .{ .x = 100, .y = 100 }, game.camera, black);
    render.drawCone(playdate, .{ .x = 1100, .y = 100 }, game.camera, black);
    render.drawCone(playdate, .{ .x = 100, .y = 700 }, game.camera, black);
    render.drawCone(playdate, .{ .x = 1100, .y = 700 }, game.camera, black);

    render.drawCone(playdate, .{ .x = 500, .y = 300 }, game.camera, black);
    render.drawCone(playdate, .{ .x = 600, .y = 260 }, game.camera, black);
    render.drawCone(playdate, .{ .x = 700, .y = 300 }, game.camera, black);
    render.drawCone(playdate, .{ .x = 700, .y = 500 }, game.camera, black);

    render.drawShelf(playdate, rack_low_shelf.zone, rack_low_shelf.support_z, game.camera, black);

    if (stress_mode) {
        for (stress_pallets) |pallet| {
            if (!palletMayBeVisible(pallet, game.camera)) continue;
            render.drawPalletShadow(
                playdate,
                pallet,
                game.camera,
                black,
            );
            render.drawPallet(
                playdate,
                pallet,
                game.camera,
                black,
            );
        }
    }
    render.drawPalletShadow(playdate, game.pallet, game.camera, black);
    render.drawPallet(playdate, game.pallet, game.camera, black);
    render.drawForklift(playdate, game.forklift, game.camera);

    if (rack_front_after_entities) {
        render.drawRackFront(playdate, occlusion_rack, game.camera, black);
    }

    const job_label = switch (game.job_state) {
        .waiting_for_pickup => "PICK UP PALLET",
        .carrying => "DELIVER PALLET",
        .delivered => "JOB COMPLETE",
    };

    const pickup = cargo.evaluateForkEntry(
        game.forklift,
        game.pallet,
        pickup_tuning,
    );
    const rendered_pallets: usize = 1 + if (stress_mode) stress_pallets.len else 0;
    const submitted_renderables: usize = obstacles.len + 13 + rendered_pallets * 2;
    const render_passes: usize = 10;
    const text = std.fmt.bufPrint(
        &game.debug_buffer,
        "job={s}\ntime={d:.1}\npickup={}\ncarried={}\nangle={d:.0} depth={d:.1}\nfork_z={d:.0}\nframe={d:.1}ms\nsubmit={d}\npasses={d}",
        .{
            job_label,
            game.job_elapsed_seconds,
            pickup.valid and game.forklift.fork_height == .floor,
            game.pallet.state == .carried,
            pickup.angle_error_rad * 180.0 / std.math.pi,
            pickup.insertion_depth,
            vehicle.forkZ(game.forklift.fork_height),
            game.fame_ms,
            submitted_renderables,
            render_passes,
        },
    ) catch unreachable;

    _ = playdate.graphics.drawText(text.ptr, text.len, .UTF8Encoding, 8, 8);
    playdate.system.drawFPS(320, 8);
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

fn palletFitsShelf(
    pallet: cargo.Pallet,
    shelf: Shelf,
) bool {
    return collision.obbContainedInRect(
        pallet.position,
        pallet.footprint.half_length,
        pallet.footprint.half_width,
        pallet.heading_rad,
        shelf.zone,
    );
}

fn rectMayBeVisible(
    rect: collision.Rect,
    camera_state: camera.Camera,
) bool {
    const bounds = camera.visibleWorldBounds(camera_state);

    return rect.x + rect.width >=
        bounds.min.x - render_cull_margin and
        rect.x <= bounds.max.x + render_cull_margin and
        rect.y + rect.height >=
            bounds.min.y - render_cull_margin and
        rect.y <= bounds.max.y + render_cull_margin;
}

fn palletMayBeVisible(
    pallet: cargo.Pallet,
    camera_state: camera.Camera,
) bool {
    return rectMayBeVisible(.{
        .x = pallet.position.x - pallet.footprint.half_width,
        .y = pallet.position.y - pallet.footprint.half_length,
        .width = pallet.footprint.half_width * 2,
        .height = pallet.footprint.half_length * 2,
    }, camera_state);
}
