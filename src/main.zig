const std = @import("std");
const pdapi = @import("playdate_api_definitions.zig");
const panic_handler = @import("panic_handler.zig");
const math2 = @import("math2.zig");
const vehicle = @import("vehicle.zig");
const camera = @import("camera.zig");
const collision = @import("collision.zig");
const cargo = @import("cargo.zig");
const jobs = @import("jobs.zig");
const render = @import("render.zig");
const audio = @import("audio.zig");
const pdna_effects = @import("pdna_effects.zig");
const pdna_song = @import("pdna_song_1.zig");
const campaign = @import("campaign.zig");
const scoring = @import("scoring.zig");
const training_facility = @import("content/training_facility.zig");
const stress_test = @import("content/stress_test.zig");

const use_stress_stage = false;
const ActiveStage = if (use_stress_stage) stress_test else training_facility;
const render_cull_margin: f32 = 50;
const impact_rearm_distance: f32 = 12;
var steering_ratio_option_titles = [_]?[*:0]const u8{ "Low", "Medium", "High" };

pub const panic = panic_handler.panic;

const pickup_tuning = cargo.PickupTuning{
    .max_angle_error_rad = 0.4,
    .tine_lateral_tolerance = 3,
    .minimum_insertion = 18,
};

const campaign_data = campaign.CampaignDefinition{
    .stages = &[_]campaign.StageDefinition{
        ActiveStage.stage,
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

fn activeShift(game: *const Game) *const campaign.ShiftDefinition {
    return &campaign_data.stages[game.stage_index].shifts[game.shift_index];
}

pub const Game = struct {
    playdate: *pdapi.PlaydateAPI,
    audio: audio.Audio,
    font: *pdapi.LCDFont,
    forklift: vehicle.Forklift = .{
        .position = ActiveStage.forklift_spawn,
    },
    debug_buffer: [192]u8 = undefined,
    camera: camera.Camera = .{},
    job_index: usize = 0,
    pallet: cargo.Pallet = palletForJob(ActiveStage.shift.jobs[0]),
    job_state: jobs.JobState = .waiting_for_pickup,
    shift_elapsed_seconds: f32 = 0,
    collision_impacts: u32 = 0,
    impact_origin: ?math2.Vec2 = null,
    shift_result: ?scoring.ShiftResult = null,
    frame_ms: f32 = 0,
    restart_requested: bool = false,
    steering_ratio: vehicle.SteeringRatio = .medium,
    steering_ratio_menu_item: ?*pdapi.PDMenuItem = null,
    flow_state: campaign.FlowState = .title,
    stage_index: usize = 0,
    shift_index: usize = 0,
    briefing_page_index: usize = 0,
};

pub export fn eventHandler(
    playdate: *pdapi.PlaydateAPI,
    event: pdapi.PDSystemEvent,
    arg: u32,
) callconv(.c) c_int {
    _ = arg;
    if (event != .EventInit) return 0;
    panic_handler.init(playdate);

    var game_audio = audio.Audio.init(playdate, &pdna_song.song1) catch return 0;
    errdefer game_audio.deinit();
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
        .audio = game_audio,
        .font = font,
    };
    _ = playdate.system.addMenuItem(
        "Restart Job",
        restartJobMenuItemSelected,
        game,
    ) orelse return 0;
    game.steering_ratio_menu_item = playdate.system.addOptionsMenuItem(
        "Steering",
        @ptrCast(&steering_ratio_option_titles),
        steering_ratio_option_titles.len,
        steeringRatioMenuItemSelected,
        game,
    ) orelse return 0;
    playdate.system.setMenuItemValue(
        game.steering_ratio_menu_item,
        1,
    );
    game.audio.startMusic();

    playdate.system.resetElapsedTime();
    playdate.system.setUpdateCallback(updateAndRender, game);
    return 0;
}

fn beginShift(game: *Game) void {
    game.job_index = 0;
    game.shift_elapsed_seconds = 0;
    game.collision_impacts = 0;
    game.impact_origin = null;
    game.shift_result = null;
    resetCurrentJob(game);
}

fn updateTitle(game: *Game, pushed: pdapi.PDButtons) void {
    if (pushed & pdapi.BUTTON_A == 0) return;

    beginShift(game);
    game.briefing_page_index = 0;
    game.flow_state = .briefing;
}

fn updateBriefing(game: *Game, pushed: pdapi.PDButtons) void {
    if (pushed & pdapi.BUTTON_A == 0) return;

    const pages = activeShift(game).opening_briefing.pages;
    if (game.briefing_page_index + 1 < pages.len) {
        game.briefing_page_index += 1;
    } else {
        game.flow_state = .playing_shift;
    }
}

fn updateAndRender(userdata: ?*anyopaque) callconv(.c) c_int {
    const game: *Game = @ptrCast(@alignCast(userdata.?));
    const playdate = game.playdate;

    var current: pdapi.PDButtons = 0;
    var pushed: pdapi.PDButtons = 0;
    playdate.system.getButtonState(&current, &pushed, null);

    const raw_dt = playdate.system.getElapsedTime();
    const dt = @min(raw_dt, 1.0 / 15.0);
    game.frame_ms = raw_dt * 1000.0;
    playdate.system.resetElapsedTime();
    const crank_delta_deg = playdate.system.getCrankChange();

    switch (game.flow_state) {
        .title => {
            updateTitle(game, pushed);
            drawTitle(game);
            return 1;
        },
        .briefing => {
            updateBriefing(game, pushed);
            drawBriefing(game);
            return 1;
        },
        .playing_shift => {},
        .shift_results => {
            updateShiftResults(game, pushed);
            drawShiftResults(game);
            return 1;
        },
    }

    if (game.restart_requested) resetCurrentJob(game);

    const previous_position = game.forklift.position;
    const previous_heading = game.forklift.heading_rad;
    const previous_pallet = game.pallet;

    vehicle.update(
        &game.forklift,
        .{
            .crank_delta_deg = crank_delta_deg,
            .steering_ratio = game.steering_ratio,
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

    const previous_fork_height = game.forklift.fork_height;
    if (rotate_view_pressed) {
        camera.rotateClockwise(&game.camera);
    } else if (lateral_pressed & pdapi.BUTTON_RIGHT != 0) {
        vehicle.raiseForks(&game.forklift);
    } else if (lateral_pressed & pdapi.BUTTON_LEFT != 0) {
        vehicle.lowerForks(&game.forklift);
    }
    if (game.forklift.fork_height != previous_fork_height) {
        game.audio.play(pdna_effects.fork_height_move);
    }

    if (game.pallet.state == .carried) {
        cargo.followForks(&game.pallet, game.forklift);
    }

    if (game.impact_origin) |origin| {
        const displacement = math2.sub(game.forklift.position, origin);
        if (math2.dot(displacement, displacement) >=
            impact_rearm_distance * impact_rearm_distance)
        {
            game.impact_origin = null;
        }
    }

    if (forkliftCollides(game.forklift, game.pallet)) {
        if (game.impact_origin == null) {
            game.collision_impacts += 1;
            game.impact_origin = previous_position;
        }

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
            game.audio.play(pdna_effects.pallet_engagement);
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
            ActiveStage.palletFitsRackLowShelf(game.pallet))
        {
            cargo.dropAt(&game.pallet, ActiveStage.rack_low_support_z);
        }
    }

    const shift = activeShift(game);
    if (game.job_state != .delivered) {
        game.shift_elapsed_seconds += dt;
        game.job_state = jobs.update(
            game.job_state,
            game.pallet,
            shift.jobs[game.job_index].destination,
        );

        if (game.job_state == .delivered) {
            if (game.job_index + 1 < shift.jobs.len) {
                game.job_index += 1;
                game.pallet = palletForJob(shift.jobs[game.job_index]);
                game.job_state = .waiting_for_pickup;
            } else {
                game.shift_result = scoring.calculate(
                    shift.scoring,
                    game.shift_elapsed_seconds,
                    shift.jobs.len,
                    game.collision_impacts,
                );
                game.flow_state = .shift_results;
            }
        }
    }

    camera.follow(&game.camera, game.forklift.position);

    draw(game);

    return 1;
}

fn restartJobMenuItemSelected(userdata: ?*anyopaque) callconv(.c) void {
    const game: *Game = @ptrCast(@alignCast(userdata orelse return));
    game.restart_requested = true;
}

fn steeringRatioMenuItemSelected(userdata: ?*anyopaque) callconv(.c) void {
    const game: *Game = @ptrCast(@alignCast(userdata orelse return));
    const menu_item = game.steering_ratio_menu_item orelse return;
    game.steering_ratio = vehicle.SteeringRatio.fromMenuValue(
        game.playdate.system.getMenuItemValue(menu_item),
    );
}

fn resetCurrentJob(game: *Game) void {
    const shift = activeShift(game);
    game.restart_requested = false;
    game.forklift.reset(ActiveStage.forklift_spawn);
    game.camera = .{};
    game.pallet = palletForJob(shift.jobs[game.job_index]);
    game.job_state = .waiting_for_pickup;
}

fn updateShiftResults(game: *Game, pushed: pdapi.PDButtons) void {
    if (pushed & pdapi.BUTTON_A != 0) {
        game.flow_state = .title;
    }
}

fn drawShiftResults(game: *Game) void {
    const result = game.shift_result orelse return;
    const shift = activeShift(game);
    const playdate = game.playdate;

    playdate.graphics.clear(@intCast(@intFromEnum(
        pdapi.LCDSolidColor.ColorWhite,
    )));

    const heading = "SHIFT COMPLETE";
    _ = playdate.graphics.drawText(heading.ptr, heading.len, .UTF8Encoding, 118, 24);

    const text = std.fmt.bufPrint(&game.debug_buffer, "{s}\ntime: {d:.1}s\njobs: {d}/{d}\ndamage: {d}\ntime bonus: {d}\npoints: {d}\n\nA: Continue", .{
        shift.title,
        result.elapsed_seconds,
        result.completed_jobs,
        shift.jobs.len,
        result.collision_impacts,
        result.time_bonus,
        result.points,
    }) catch unreachable;

    _ = playdate.graphics.drawText(
        text.ptr,
        text.len,
        .UTF8Encoding,
        32,
        56,
    );
}

fn drawTitle(game: *Game) void {
    const playdate = game.playdate;
    playdate.graphics.clear(@intCast(@intFromEnum(
        pdapi.LCDSolidColor.ColorWhite,
    )));

    const title = "FORKLIFT CERTIFIED";
    const prompt = "A: Continue Main Game";

    _ = playdate.graphics.drawText(
        title.ptr,
        title.len,
        .UTF8Encoding,
        72,
        88,
    );
    _ = playdate.graphics.drawText(
        prompt.ptr,
        prompt.len,
        .UTF8Encoding,
        88,
        136,
    );
}

fn drawBriefing(game: *Game) void {
    const playdate = game.playdate;
    const pages = activeShift(game).opening_briefing.pages;
    const page = pages[game.briefing_page_index];
    const prompt = if (game.briefing_page_index + 1 < pages.len)
        "A: Next"
    else
        "A: Start Shift";

    playdate.graphics.clear(@intCast(@intFromEnum(
        pdapi.LCDSolidColor.ColorWhite,
    )));
    playdate.graphics.drawRect(
        8,
        48,
        384,
        144,
        @intCast(@intFromEnum(pdapi.LCDSolidColor.ColorBlack)),
    );

    const boss = "BOSS";
    _ = playdate.graphics.drawText(boss.ptr, boss.len, .UTF8Encoding, 24, 64);
    _ = playdate.graphics.drawText(page.ptr, page.len, .UTF8Encoding, 24, 96);
    _ = playdate.graphics.drawText(prompt.ptr, prompt.len, .UTF8Encoding, 24, 168);
}

fn draw(game: *Game) void {
    const playdate = game.playdate;

    playdate.graphics.clear(@intCast(@intFromEnum(pdapi.LCDSolidColor.ColorWhite)));

    var renderer = render.Renderer.init(
        playdate,
        game.camera,
        render_cull_margin,
    );

    const entity_depth = if (game.pallet.state == .carried)
        @max(
            camera.depth(game.forklift.position, game.camera),
            camera.depth(game.pallet.position, game.camera),
        )
    else
        camera.depth(game.forklift.position, game.camera);

    ActiveStage.warehouse.draw(&renderer, .before_actors, entity_depth);

    const shift = activeShift(game);
    renderer.destination(shift.jobs[game.job_index].destination);

    for (ActiveStage.decorative_pallets) |pallet| {
        renderer.palletShadow(pallet);
        renderer.pallet(pallet);
    }
    renderer.palletShadow(game.pallet);
    renderer.pallet(game.pallet);
    renderer.forklift(game.forklift);

    ActiveStage.warehouse.draw(&renderer, .after_actors, entity_depth);

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
    const render_stats = renderer.stats;
    const render_passes: usize = 10;
    const text = std.fmt.bufPrint(
        &game.debug_buffer,
        "job={s}\ntime={d:.1}\npickup={}\ncarried={}\nangle={d:.0} depth={d:.1}\nfork_z={d:.0}\nframe={d:.1}ms\nsubmit={d} cull={d}\npasses={d}",
        .{
            job_label,
            game.shift_elapsed_seconds,
            pickup.valid and game.forklift.fork_height == .floor,
            game.pallet.state == .carried,
            pickup.angle_error_rad * 180.0 / std.math.pi,
            pickup.insertion_depth,
            vehicle.forkZ(game.forklift.fork_height),
            game.frame_ms,
            render_stats.submitted,
            render_stats.culled,
            render_passes,
        },
    ) catch unreachable;

    _ = playdate.graphics.drawText(text.ptr, text.len, .UTF8Encoding, 8, 8);
    playdate.system.drawFPS(320, 8);
}

fn forkliftCollides(forklift: vehicle.Forklift, pallet: cargo.Pallet) bool {
    const carried = if (pallet.state == .carried) pallet else null;
    return ActiveStage.warehouse.collides(forklift, carried);
}
