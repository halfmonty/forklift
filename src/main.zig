const pdapi = @import("platform_api.zig");
const panic_handler = @import("panic_handler.zig");
const audio = @import("audio/audio.zig");
const pdna_song = @import("audio/pdna_song_1.zig");
const game_module = @import("game/game.zig");

var steering_ratio_option_titles = [_]?[*:0]const u8{ "Low", "Medium", "High" };

pub const panic = panic_handler.panic;

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

    const game: *game_module.Game = @ptrCast(@alignCast(
        playdate.system.realloc(null, @sizeOf(game_module.Game)) orelse return 0,
    ));
    const surface_fragment_buffer: *game_module.SurfaceFragmentBuffer = @ptrCast(@alignCast(
        playdate.system.realloc(null, @sizeOf(game_module.SurfaceFragmentBuffer)) orelse return 0,
    ));
    const render_scene: *game_module.RenderScene = @ptrCast(@alignCast(
        playdate.system.realloc(null, @sizeOf(game_module.RenderScene)) orelse return 0,
    ));
    render_scene.* = .{};
    game.* = game_module.Game.init(
        playdate,
        game_audio,
        font,
        surface_fragment_buffer,
        render_scene,
    );

    _ = playdate.system.addMenuItem(
        "Restart Job",
        restartJobMenuItemSelected,
        game,
    ) orelse return 0;
    const steering_menu_item = playdate.system.addOptionsMenuItem(
        "Steering",
        @ptrCast(&steering_ratio_option_titles),
        steering_ratio_option_titles.len,
        steeringRatioMenuItemSelected,
        game,
    ) orelse return 0;
    game.setSteeringRatioMenuItem(steering_menu_item);
    playdate.system.setMenuItemValue(steering_menu_item, 1);
    game.audio.startMusic();

    playdate.system.resetElapsedTime();
    playdate.system.setUpdateCallback(game_module.Game.updateAndRender, game);
    return 0;
}

fn restartJobMenuItemSelected(userdata: ?*anyopaque) callconv(.c) void {
    const game: *game_module.Game = @ptrCast(@alignCast(userdata orelse return));
    game.requestRestart();
}

fn steeringRatioMenuItemSelected(userdata: ?*anyopaque) callconv(.c) void {
    const game: *game_module.Game = @ptrCast(@alignCast(userdata orelse return));
    game.applySteeringRatioMenuSelection();
}
