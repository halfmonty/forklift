const std = @import("std");
const pdapi = @import("../platform_api.zig");
const math2 = @import("../sim/math2.zig");
const vehicle = @import("../sim/vehicle.zig");
const camera = @import("../render/camera.zig");
const cargo = @import("../sim/cargo.zig");
const jobs = @import("../sim/jobs.zig");
const render = @import("../render/renderer.zig");
const compositor = @import("../render/compositor.zig");
const scene = @import("../render/scene.zig");
const audio = @import("../audio/audio.zig");
const pdna_effects = @import("../audio/pdna_effects.zig");
const stages = @import("../content/stages.zig");
const campaign = @import("campaign.zig");
const scoring = @import("scoring.zig");
const input = @import("input.zig");
const progress = @import("progress.zig");
const progress_store = @import("progress_store.zig");
const warehouse_runtime = @import("../runtime/warehouse_runtime.zig");
const config = @import("../config.zig");

pub const SurfaceFragmentBuffer = compositor.SurfaceFragmentBuffer;
pub const RenderScene = scene.RenderScene;

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
    render_scene: *scene.RenderScene,
    runtime: warehouse_runtime.WarehouseRuntime = warehouse_runtime.WarehouseRuntime.init(
        stages.initial_stage_id,
        &stages.initial_shift,
    ),
    debug_buffer: [192]u8 = undefined,
    camera: camera.Camera = .{},
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
        render_scene: *scene.RenderScene,
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
            .render_scene = render_scene,
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
        updateCamera(game, frame_input, camera_mode);
        const step = game.runtime.step(.{
            .dt = frame_input.dt,
            .crank_delta_deg = frame_input.crank_delta_deg,
            .steering_ratio = game.steering_ratio,
            .forward = frame_input.held & pdapi.BUTTON_UP != 0,
            .reverse = frame_input.held & pdapi.BUTTON_DOWN != 0,
            .camera_mode = camera_mode,
            .raise_pressed = frame_input.pushed & pdapi.BUTTON_RIGHT != 0,
            .lower_pressed = frame_input.pushed & pdapi.BUTTON_LEFT != 0,
            .action_pressed = frame_input.pushed & pdapi.BUTTON_A != 0,
        });
        if (step.sounds.fork_height_moved) game.audio.play(pdna_effects.fork_height_move);
        if (step.sounds.pallet_engaged) game.audio.play(pdna_effects.pallet_engagement);
        switch (step.transition) {
            .none => {},
            .next_job => {
                const next_job_index = step.next_job_index orelse unreachable;
                if (beforeJobBriefing(activeShift(game), next_job_index) != null) {
                    beginBriefing(game, .{ .before_job = next_job_index });
                } else startJob(game, next_job_index);
            },
            .shift_completed => game.flow_state = .shift_results,
        }

        const forward = math2.forwardVector(game.runtime.world.forklift.heading_rad);
        const camera_target = math2.add(
            vehicle.bodyCenter(game.runtime.world.forklift),
            math2.scale(forward, 20),
        );
        // camera.follow(&game.camera, camera_target, activeStageWorldSize(game));
        camera.follow(&game.camera, camera_target, stages.worldSize(activeStageId(game)));
        draw(game);
        return 1;
    }
};

fn beginShift(game: *Game) void {
    game.restart_requested = false;
    game.runtime.beginShift(activeStageId(game), activeShift(game));
    game.camera = .{};
}

fn updateCamera(game: *Game, frame: input.FrameInput, camera_mode: bool) void {
    if (!camera_mode) return;
    if (frame.pushed & pdapi.BUTTON_UP != 0) {
        camera.snapTo(&game.camera, .north);
    } else if (frame.pushed & pdapi.BUTTON_RIGHT != 0) {
        camera.snapTo(&game.camera, .east);
    } else if (frame.pushed & pdapi.BUTTON_DOWN != 0) {
        camera.snapTo(&game.camera, .south);
    } else if (frame.pushed & pdapi.BUTTON_LEFT != 0) {
        camera.snapTo(&game.camera, .west);
    } else {
        camera.rotateBy(
            &game.camera,
            math2.degreesToRadians(frame.crank_delta_deg * config.camera_yaw_per_crank_degree),
        );
    }
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
    game.runtime.startJob(job_index);
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
    game.restart_requested = false;
    game.runtime.resetCurrentJob();
    game.camera = .{};
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
    const result = game.runtime.world.shift_result orelse return;
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
    const pallet = game.runtime.world.primaryCargo();
    const entity_depth = if (pallet.state == .carried)
        @max(camera.depth(game.runtime.world.forklift.position, game.camera), camera.depth(pallet.position, game.camera))
    else
        camera.depth(game.runtime.world.forklift.position, game.camera);
    const stage_id = activeStageId(game);
    game.render_scene.clear();
    game.render_scene.append(.{ .warehouse = .{ .stage_id = stage_id, .phase = .before_actors, .actor_depth = entity_depth } });
    game.render_scene.append(.{ .pressure_plates = .{ .stage_id = stage_id, .active = game.runtime.world.pressure_plates.active[0..] } });
    game.render_scene.append(.{ .gates = .{ .stage_id = stage_id, .open = game.runtime.world.gates.open[0..] } });
    game.render_scene.append(.{ .destination = game.runtime.world.objective.destination });
    game.render_scene.append(.{ .decorative_pallets = stage_id });
    game.render_scene.append(.{ .conveyors = stage_id });
    game.render_scene.append(.{ .pallet_shadow = pallet.* });
    game.render_scene.append(.{ .dynamic = .{ .stage_id = stage_id, .forklift = game.runtime.world.forklift, .pallet = pallet.* } });
    game.render_scene.append(.{ .warehouse = .{ .stage_id = stage_id, .phase = .after_actors, .actor_depth = entity_depth } });
    game.render_scene.submit(&renderer, game.surface_fragment_buffer);
    const job_label = switch (game.runtime.world.objective.job_state) {
        .waiting_for_pickup => "PICK UP PALLET",
        .carrying => "DELIVER PALLET",
        .delivered => "JOB COMPLETE",
    };
    const pickup = cargo.evaluateForkEntry(game.runtime.world.forklift, pallet.*, pickup_tuning);
    const render_stats = renderer.stats;
    const text = std.fmt.bufPrint(&game.debug_buffer, "job={s}\ntime={d:.1}\npickup={}\ncarried={}\nangle={d:.0} depth={d:.1}\nfork_z={d:.0}\nframe={d:.1}ms\nsubmit={d} cull={d}", .{
        job_label,
        game.runtime.world.shift_elapsed_seconds,
        pickup.valid and game.runtime.world.forklift.fork_height == .floor,
        pallet.state == .carried,
        pickup.angle_error_rad * 180.0 / std.math.pi,
        pickup.insertion_depth,
        vehicle.forkZ(game.runtime.world.forklift.fork_height),
        game.frame_ms,
        render_stats.submitted,
        render_stats.culled,
    }) catch unreachable;
    _ = playdate.graphics.drawText(text.ptr, text.len, .UTF8Encoding, 8, 8);
    playdate.system.drawFPS(320, 8);
}

test "reset current job restores its initial forklift and pallet state" {
    var game: Game = undefined;
    game.stage_index = 0;
    game.shift_index = 0;
    game.restart_requested = true;
    game.runtime = warehouse_runtime.WarehouseRuntime.init(
        stages.initial_stage_id,
        &stages.initial_shift,
    );
    game.runtime.world.forklift = .{
        .position = .{ .x = 0, .y = 0 },
        .heading_rad = 1.2,
        .speed = 50,
        .fork_height = .rack_high,
    };
    game.runtime.world.primaryCargo().* = .{
        .position = .{ .x = 10, .y = 10 },
        .state = .carried,
        .z = vehicle.forkZ(.rack_high),
    };
    game.runtime.world.objective.job_state = .delivered;

    resetCurrentJob(&game);

    const shift = activeShift(&game);
    try std.testing.expect(!game.restart_requested);
    try std.testing.expectEqual(
        stages.forkliftSpawn(activeStageId(&game)),
        game.runtime.world.forklift.position,
    );
    try std.testing.expectEqual(@as(f32, 0), game.runtime.world.forklift.heading_rad);
    try std.testing.expectEqual(@as(f32, 0), game.runtime.world.forklift.speed);
    try std.testing.expectEqual(vehicle.ForkHeight.floor, game.runtime.world.forklift.fork_height);
    try std.testing.expectEqual(game.runtime.world.objective.destination, shift.jobs[0].destination);
    try std.testing.expectEqual(jobs.JobState.waiting_for_pickup, game.runtime.world.objective.job_state);
}
