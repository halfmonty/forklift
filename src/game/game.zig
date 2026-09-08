const std = @import("std");
const pdapi = @import("../platform_api.zig");
const math2 = @import("../sim/math2.zig");
const vehicle = @import("../sim/vehicle.zig");
const camera = @import("../render/camera.zig");
const cargo = @import("../sim/cargo.zig");
const jobs = @import("../sim/jobs.zig");
const render = @import("../render/renderer.zig");
const compositor = @import("../render/compositor.zig");
const audio = @import("../audio/audio.zig");
const pdna_effects = @import("../audio/pdna_effects.zig");
const stages = @import("../content/stages.zig");
const campaign = @import("campaign.zig");
const scoring = @import("scoring.zig");
const input = @import("input.zig");
const progress = @import("progress.zig");
const progress_store = @import("progress_store.zig");
const config = @import("../config.zig");

pub const SurfaceFragmentBuffer = compositor.SurfaceFragmentBuffer;

const render_cull_margin: f32 = 50;
const impact_rearm_distance: f32 = 12;

const pickup_tuning = cargo.PickupTuning{
    .max_angle_error_rad = 0.4,
    .tine_lateral_tolerance = 3,
    .minimum_insertion = 18,
};

const TitleSelection = enum {
    continue_game,
    new_game,
};

const BriefingContinuation = union(enum) {
    shift_start,
    before_job: usize,
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
    return &stages.active_campaign.stages[game.stage_index].shifts[game.shift_index];
}

fn shiftStartBriefing(
    shift: *const campaign.ShiftDefinition,
) ?[]const []const u8 {
    for (shift.briefings) |briefing| {
        switch (briefing.trigger) {
            .shift_start => return briefing.pages,
            .before_job => {},
        }
    }
    return null;
}

fn beforeJobBriefing(
    shift: *const campaign.ShiftDefinition,
    job_index: usize,
) ?[]const []const u8 {
    for (shift.briefings) |briefing| {
        switch (briefing.trigger) {
            .shift_start => {},
            .before_job => |briefing_job_index| {
                if (briefing_job_index == job_index) {
                    return briefing.pages;
                }
            },
        }
    }
    return null;
}

fn activeStageId(game: *const Game) campaign.StageId {
    return stages.active_campaign.stages[game.stage_index].id;
}

pub const Game = struct {
    playdate: *pdapi.PlaydateAPI,
    audio: audio.Audio,
    font: *pdapi.LCDFont,
    surface_fragment_buffer: *compositor.SurfaceFragmentBuffer,
    forklift: vehicle.Forklift = .{ .position = stages.forkliftSpawn(stages.initial_stage_id) },
    debug_buffer: [192]u8 = undefined,
    camera: camera.Camera = .{},
    job_index: usize = 0,
    pallet: cargo.Pallet = palletForJob(stages.initial_shift.jobs[0]),
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
    progress_state: progress.Progress = progress.Progress.initial(),
    has_saved_progress: bool = false,
    title_selection: TitleSelection = .new_game,
    briefing_continuation: BriefingContinuation = .shift_start,

    pub fn init(
        playdate: *pdapi.PlaydateAPI,
        game_audio: audio.Audio,
        font: *pdapi.LCDFont,
        surface_fragment_buffer: *compositor.SurfaceFragmentBuffer,
    ) Game {
        const loaded = if (stages.skip_title_screen)
            progress_store.LoadResult{
                .progress = progress.Progress.initial(),
                .exists = false,
            }
        else
            progress_store.load(playdate, stages.active_campaign);

        var game = Game{
            .playdate = playdate,
            .audio = game_audio,
            .font = font,
            .surface_fragment_buffer = surface_fragment_buffer,
            .progress_state = loaded.progress,
            .has_saved_progress = loaded.exists,
            .title_selection = if (loaded.exists) .continue_game else .new_game,
        };
        if (stages.skip_title_screen) enterShift(&game, 0, 0);
        return game;
    }

    pub fn requestRestart(self: *Game) void {
        self.restart_requested = true;
    }

    pub fn setSteeringRatioMenuItem(
        self: *Game,
        item: *pdapi.PDMenuItem,
    ) void {
        self.steering_ratio_menu_item = item;
    }

    pub fn applySteeringRatioMenuSelection(self: *Game) void {
        const menu_item = self.steering_ratio_menu_item orelse return;
        self.steering_ratio = vehicle.SteeringRatio.fromMenuValue(
            self.playdate.system.getMenuItemValue(menu_item),
        );
    }

    pub fn updateAndRender(userdata: ?*anyopaque) callconv(.c) c_int {
        const game: *Game = @ptrCast(@alignCast(userdata.?));
        const playdate = game.playdate;

        const frame_input = input.read(playdate);
        const camera_mode = frame_input.held & pdapi.BUTTON_B != 0;
        game.frame_ms = frame_input.frame_ms;

        switch (game.flow_state) {
            .title => {
                updateTitle(game, frame_input.pushed);
                drawTitle(game);
                return 1;
            },
            .briefing => {
                updateBriefing(game, frame_input.pushed);
                drawBriefing(game);
                return 1;
            },
            .playing_shift => {},
            .shift_results => {
                updateShiftResults(game, frame_input.pushed);
                drawShiftResults(game);
                return 1;
            },
            .promotion => {
                updatePromotion(game, frame_input.pushed);
                drawPromotion(game);
                return 1;
            },
            .campaign_complete => {
                updateCampaignComplete(game, frame_input.pushed);
                drawCampaignComplete(game);
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
                .crank_delta_deg = if (camera_mode) 0 else frame_input.crank_delta_deg,
                .steering_ratio = game.steering_ratio,
                .forward = !camera_mode and frame_input.held & pdapi.BUTTON_UP != 0,
                .reverse = !camera_mode and frame_input.held & pdapi.BUTTON_DOWN != 0,
            },
            if (game.pallet.state == .carried)
                game.pallet.cargo.carried_acceleration_multiplier
            else
                1.0,
            frame_input.dt,
        );

        const lateral_pressed = frame_input.pushed &
            (pdapi.BUTTON_LEFT | pdapi.BUTTON_RIGHT);

        const previous_fork_height = game.forklift.fork_height;
        if (camera_mode) {
            if (frame_input.pushed & pdapi.BUTTON_UP != 0) {
                camera.snapTo(&game.camera, .north);
            } else if (frame_input.pushed & pdapi.BUTTON_RIGHT != 0) {
                camera.snapTo(&game.camera, .east);
            } else if (frame_input.pushed & pdapi.BUTTON_DOWN != 0) {
                camera.snapTo(&game.camera, .south);
            } else if (frame_input.pushed & pdapi.BUTTON_LEFT != 0) {
                camera.snapTo(&game.camera, .west);
            } else {
                camera.rotateBy(
                    &game.camera,
                    math2.degreesToRadians(
                        frame_input.crank_delta_deg *
                            config.camera_yaw_per_crank_degree,
                    ),
                );
            }
        } else if (lateral_pressed & pdapi.BUTTON_RIGHT != 0) {
            var raised_forklift = game.forklift;
            vehicle.raiseForks(&raised_forklift);

            const carried = if (game.pallet.state == .carried)
                game.pallet
            else
                null;

            if (!stages.blocksForkRaising(
                activeStageId(game),
                game.forklift,
                carried,
                game.forklift.fork_height,
                raised_forklift.fork_height,
            )) {
                game.forklift.fork_height = raised_forklift.fork_height;
            }
        } else if (lateral_pressed & pdapi.BUTTON_LEFT != 0) {
            var lowered_forklift = game.forklift;
            vehicle.lowerForks(&lowered_forklift);

            const carried = if (game.pallet.state == .carried)
                game.pallet
            else
                null;

            if (!stages.blocksForkLowering(
                activeStageId(game),
                game.forklift,
                carried,
                game.forklift.fork_height,
                lowered_forklift.fork_height,
            )) {
                game.forklift.fork_height = lowered_forklift.fork_height;
            }
        }

        if (game.forklift.fork_height != previous_fork_height) {
            game.audio.play(pdna_effects.fork_height_move);
        }

        if (game.pallet.state == .carried) cargo.followForks(&game.pallet, game.forklift);

        if (game.impact_origin) |origin| {
            const displacement = math2.sub(game.forklift.position, origin);
            if (math2.dot(displacement, displacement) >= impact_rearm_distance * impact_rearm_distance) {
                game.impact_origin = null;
            }
        }

        if (forkliftCollides(activeStageId(game), game.forklift, game.pallet)) {
            if (game.impact_origin == null) {
                game.collision_impacts += 1;
                game.impact_origin = previous_position;
            }
            game.forklift.position = previous_position;
            game.forklift.heading_rad = previous_heading;
            game.forklift.speed = 0;
            game.pallet = previous_pallet;
        }

        if (frame_input.pushed & pdapi.BUTTON_A != 0) {
            if (game.pallet.state == .carried) {
                if (game.forklift.fork_height == .floor) {
                    cargo.drop(&game.pallet);
                } else if (stages.palletDropSupport(
                    activeStageId(game),
                    game.forklift.fork_height,
                    game.pallet,
                )) |support_z| {
                    cargo.dropAt(&game.pallet, support_z);
                }
            } else {
                const pickup_height_matches = @abs(
                    vehicle.forkZ(game.forklift.fork_height) -
                        game.pallet.support_z,
                ) < 0.1;

                if (pickup_height_matches and
                    cargo.tryPickup(&game.pallet, game.forklift, pickup_tuning))
                {
                    game.audio.play(pdna_effects.pallet_engagement);
                    if (game.forklift.fork_height == .floor) {
                        game.forklift.fork_height = .carry;
                    }
                }
            }
        }

        if (game.pallet.state == .carried) {
            cargo.followForks(&game.pallet, game.forklift);
            game.pallet.z = vehicle.forkZ(game.forklift.fork_height);
        }

        const shift = activeShift(game);
        if (game.job_state != .delivered) {
            game.shift_elapsed_seconds += frame_input.dt;
            game.job_state = jobs.update(game.job_state, game.pallet, shift.jobs[game.job_index].destination);
            if (game.job_state == .delivered) {
                if (game.job_index + 1 < shift.jobs.len) {
                    const next_job_index = game.job_index + 1;
                    if (beforeJobBriefing(shift, next_job_index) != null) {
                        beginBriefing(game, .{ .before_job = next_job_index });
                    } else {
                        startJob(game, next_job_index);
                    }
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

        const forward = math2.forwardVector(game.forklift.heading_rad);
        const camera_target = math2.add(
            vehicle.bodyCenter(game.forklift),
            math2.scale(forward, 20),
        );
        // camera.follow(&game.camera, camera_target, activeStageWorldSize(game));
        camera.follow(&game.camera, camera_target, stages.worldSize(activeStageId(game)));
        draw(game);
        return 1;
    }
};

fn beginShift(game: *Game) void {
    game.job_index = 0;
    game.shift_elapsed_seconds = 0;
    game.collision_impacts = 0;
    game.impact_origin = null;
    game.shift_result = null;
    resetCurrentJob(game);
}

fn beginBriefing(
    game: *Game,
    continuation: BriefingContinuation,
) void {
    game.briefing_continuation = continuation;
    game.briefing_page_index = 0;
    game.flow_state = .briefing;
}

fn activeBriefingPages(game: *const Game) []const []const u8 {
    const shift = activeShift(game);

    return switch (game.briefing_continuation) {
        .shift_start => shiftStartBriefing(shift) orelse unreachable,
        .before_job => |job_index| beforeJobBriefing(
            shift,
            job_index,
        ) orelse unreachable,
    };
}

fn startJob(game: *Game, job_index: usize) void {
    const shift = activeShift(game);
    game.job_index = job_index;
    game.pallet = palletForJob(shift.jobs[job_index]);
    game.job_state = .waiting_for_pickup;
}

fn enterShift(
    game: *Game,
    stage_index: usize,
    shift_index: usize,
) void {
    game.stage_index = stage_index;
    game.shift_index = shift_index;
    beginShift(game);

    if (shiftStartBriefing(activeShift(game)) != null) {
        beginBriefing(game, .shift_start);
    } else {
        game.flow_state = .playing_shift;
    }
}

fn saveNextUnfinishedShift(
    game: *Game,
    stage_index: usize,
    shift_index: usize,
) void {
    if (stages.skip_title_screen) return;
    const stage = stages.active_campaign.stages[stage_index];
    const shift = stage.shifts[shift_index];
    std.debug.assert(shift.stage_id == stage.id);

    game.progress_state = .{
        .next_unfinished_stage_id = stage.id,
        .next_unfinished_shift_id = shift.id,
        .campaign_complete = false,
    };
    game.has_saved_progress = progress_store.save(game.playdate, game.progress_state);
}

fn saveCampaignComplete(game: *Game) void {
    if (stages.skip_title_screen) return;
    game.progress_state.campaign_complete = true;
    game.has_saved_progress = progress_store.save(game.playdate, game.progress_state);
}

fn updateTitle(game: *Game, pushed: pdapi.PDButtons) void {
    if (game.has_saved_progress and
        pushed & (pdapi.BUTTON_UP | pdapi.BUTTON_DOWN) != 0)
    {
        game.title_selection = switch (game.title_selection) {
            .continue_game => .new_game,
            .new_game => .continue_game,
        };
    }

    if (pushed & pdapi.BUTTON_A == 0) return;

    if (game.title_selection == .new_game) {
        if (game.has_saved_progress and !progress_store.clear(game.playdate)) return;
        game.progress_state = progress.Progress.initial();
        game.has_saved_progress = false;
        enterShift(game, 0, 0);
        return;
    }

    if (game.progress_state.campaign_complete) {
        game.briefing_page_index = 0;
        game.flow_state = .campaign_complete;
        return;
    }

    const location = progress.locationFor(
        stages.active_campaign,
        game.progress_state,
    ) orelse {
        game.progress_state = progress.Progress.initial();
        enterShift(game, 0, 0);
        return;
    };

    enterShift(game, location.stage_index, location.shift_index);
}

fn updateBriefing(game: *Game, pushed: pdapi.PDButtons) void {
    if (pushed & pdapi.BUTTON_A == 0) return;
    const pages = activeBriefingPages(game);
    if (game.briefing_page_index + 1 < pages.len) {
        game.briefing_page_index += 1;
        return;
    }
    switch (game.briefing_continuation) {
        .shift_start => game.flow_state = .playing_shift,
        .before_job => |job_index| {
            startJob(game, job_index);
            game.flow_state = .playing_shift;
        },
    }
}

fn resetCurrentJob(game: *Game) void {
    const shift = activeShift(game);
    game.restart_requested = false;
    game.forklift.reset(stages.forkliftSpawn(activeStageId(game)));
    game.camera = .{};
    game.pallet = palletForJob(shift.jobs[game.job_index]);
    game.job_state = .waiting_for_pickup;
}

fn updateShiftResults(game: *Game, pushed: pdapi.PDButtons) void {
    if (pushed & pdapi.BUTTON_A == 0) return;

    switch (campaign.routeAfterCompletedShift(
        stages.active_campaign,
        game.stage_index,
        game.shift_index,
    )) {
        .next_shift => |next| {
            saveNextUnfinishedShift(game, next.stage_index, next.shift_index);
            enterShift(game, next.stage_index, next.shift_index);
        },
        .promotion => {
            game.briefing_page_index = 0;
            game.flow_state = .promotion;
        },
        .campaign_complete => {
            saveCampaignComplete(game);
            game.briefing_page_index = 0;
            game.flow_state = .campaign_complete;
        },
    }
}

fn updatePromotion(game: *Game, pushed: pdapi.PDButtons) void {
    if (pushed & pdapi.BUTTON_A == 0) return;

    const pages = stages.active_campaign.stages[game.stage_index].promotion_pages;
    if (game.briefing_page_index + 1 < pages.len) {
        game.briefing_page_index += 1;
        return;
    }

    const next_stage_index = game.stage_index + 1;
    saveNextUnfinishedShift(game, next_stage_index, 0);
    enterShift(game, next_stage_index, 0);
}

fn updateCampaignComplete(game: *Game, pushed: pdapi.PDButtons) void {
    if (pushed & pdapi.BUTTON_A == 0) return;

    const pages = stages.active_campaign.campaign_complete_pages;
    if (game.briefing_page_index + 1 < pages.len) {
        game.briefing_page_index += 1;
        return;
    }

    game.flow_state = .title;
}

fn drawShiftResults(game: *Game) void {
    const result = game.shift_result orelse return;
    const shift = activeShift(game);
    const playdate = game.playdate;
    playdate.graphics.clear(@intCast(@intFromEnum(pdapi.LCDSolidColor.ColorWhite)));
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
    _ = playdate.graphics.drawText(text.ptr, text.len, .UTF8Encoding, 32, 56);
}

fn drawTitle(game: *Game) void {
    const playdate = game.playdate;
    playdate.graphics.clear(@intCast(@intFromEnum(pdapi.LCDSolidColor.ColorWhite)));
    const title = "FORKLIFT CERTIFIED";
    _ = playdate.graphics.drawText(title.ptr, title.len, .UTF8Encoding, 72, 88);
    if (!game.has_saved_progress) {
        const prompt = "A: New Game";
        _ = playdate.graphics.drawText(prompt.ptr, prompt.len, .UTF8Encoding, 136, 136);
        return;
    }

    const options = std.fmt.bufPrint(&game.debug_buffer, "{s} Continue\n{s} New Game\n\nUp/Down: Select\nA: Confirm", .{
        if (game.title_selection == .continue_game) ">" else " ",
        if (game.title_selection == .new_game) ">" else " ",
    }) catch unreachable;
    _ = playdate.graphics.drawText(options.ptr, options.len, .UTF8Encoding, 120, 128);
}

fn drawBriefing(game: *Game) void {
    const playdate = game.playdate;
    const pages = activeBriefingPages(game);
    const page = pages[game.briefing_page_index];
    const prompt = if (game.briefing_page_index + 1 < pages.len) "A: Next" else "A: Start Shift";
    playdate.graphics.clear(@intCast(@intFromEnum(pdapi.LCDSolidColor.ColorWhite)));
    playdate.graphics.drawRect(8, 48, 384, 144, @intCast(@intFromEnum(pdapi.LCDSolidColor.ColorBlack)));
    const boss = "BOSS";
    _ = playdate.graphics.drawText(boss.ptr, boss.len, .UTF8Encoding, 24, 64);
    _ = playdate.graphics.drawText(page.ptr, page.len, .UTF8Encoding, 24, 96);
    _ = playdate.graphics.drawText(prompt.ptr, prompt.len, .UTF8Encoding, 24, 168);
}

fn drawPromotion(game: *Game) void {
    const playdate = game.playdate;
    const pages = stages.active_campaign.stages[game.stage_index].promotion_pages;
    const page = pages[game.briefing_page_index];
    const prompt = if (game.briefing_page_index + 1 < pages.len)
        "A: Next"
    else
        "A: Continue";
    playdate.graphics.clear(@intCast(@intFromEnum(pdapi.LCDSolidColor.ColorWhite)));
    playdate.graphics.drawRect(8, 48, 384, 144, @intCast(@intFromEnum(pdapi.LCDSolidColor.ColorBlack)));
    const boss = "BOSS";
    _ = playdate.graphics.drawText(boss.ptr, boss.len, .UTF8Encoding, 24, 64);
    _ = playdate.graphics.drawText(page.ptr, page.len, .UTF8Encoding, 24, 96);
    _ = playdate.graphics.drawText(prompt.ptr, prompt.len, .UTF8Encoding, 24, 168);
}

fn drawCampaignComplete(game: *Game) void {
    const playdate = game.playdate;
    const pages = stages.active_campaign.campaign_complete_pages;
    const page = pages[game.briefing_page_index];
    const prompt = if (game.briefing_page_index + 1 < pages.len)
        "A: Next"
    else
        "A: Return to Title";
    playdate.graphics.clear(@intCast(@intFromEnum(pdapi.LCDSolidColor.ColorWhite)));
    playdate.graphics.drawRect(8, 48, 384, 144, @intCast(@intFromEnum(pdapi.LCDSolidColor.ColorBlack)));
    const boss = "BOSS";
    _ = playdate.graphics.drawText(boss.ptr, boss.len, .UTF8Encoding, 24, 64);
    _ = playdate.graphics.drawText(page.ptr, page.len, .UTF8Encoding, 24, 96);
    _ = playdate.graphics.drawText(prompt.ptr, prompt.len, .UTF8Encoding, 24, 168);
}

fn draw(game: *Game) void {
    const playdate = game.playdate;
    playdate.graphics.clear(@intCast(@intFromEnum(pdapi.LCDSolidColor.ColorWhite)));
    var renderer = render.Renderer.init(playdate, game.camera, render_cull_margin);
    const entity_depth = if (game.pallet.state == .carried)
        @max(camera.depth(game.forklift.position, game.camera), camera.depth(game.pallet.position, game.camera))
    else
        camera.depth(game.forklift.position, game.camera);
    const stage_id = activeStageId(game);
    stages.drawWarehouse(stage_id, &renderer, .before_actors, entity_depth);
    const shift = activeShift(game);
    renderer.destination(shift.jobs[game.job_index].destination);
    stages.drawDecorativePallets(stage_id, &renderer);
    renderer.palletShadow(game.pallet);
    var surface_collector = compositor.OpaqueSurfaceCollector.init(&renderer);
    stages.collectOpaqueSurfaces(stage_id, &surface_collector);
    var scene_compositor = compositor.Compositor.init(
        &renderer,
        surface_collector.slice(),
        game.surface_fragment_buffer,
    );
    scene_compositor.drawDynamic(game.forklift, game.pallet);

    stages.drawWarehouse(stage_id, &renderer, .after_actors, entity_depth);
    const job_label = switch (game.job_state) {
        .waiting_for_pickup => "PICK UP PALLET",
        .carrying => "DELIVER PALLET",
        .delivered => "JOB COMPLETE",
    };
    const pickup = cargo.evaluateForkEntry(game.forklift, game.pallet, pickup_tuning);
    const render_stats = renderer.stats;
    const text = std.fmt.bufPrint(&game.debug_buffer, "job={s}\ntime={d:.1}\npickup={}\ncarried={}\nangle={d:.0} depth={d:.1}\nfork_z={d:.0}\nframe={d:.1}ms\nsubmit={d} cull={d}", .{
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
    }) catch unreachable;
    _ = playdate.graphics.drawText(text.ptr, text.len, .UTF8Encoding, 8, 8);
    playdate.system.drawFPS(320, 8);
}

fn forkliftCollides(
    stage_id: campaign.StageId,
    forklift: vehicle.Forklift,
    pallet: cargo.Pallet,
) bool {
    const carried = if (pallet.state == .carried) pallet else null;
    return stages.collides(stage_id, forklift, carried);
}
