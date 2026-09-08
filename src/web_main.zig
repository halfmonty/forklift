const pd = @import("platform_api.zig");
const game_entry = @import("main.zig");
const runtime = @import("web/runtime.zig");

comptime {
    // Keep the initial browser target honest: it must select the web facade,
    // rather than accidentally pulling in the Playdate SDK definition.
    _ = pd.PlaydateAPI;
    _ = pd.PDSystemEvent;
    _ = pd.PlaydateGraphics;
    _ = game_entry.eventHandler;
}

/// Initializes the unchanged Playdate event-handler lifecycle once per page.
pub export fn webInit() c_int {
    return runtime.init(game_entry.eventHandler);
}

/// Advances the update callback installed by the game during `webInit`.
pub export fn webFrame() c_int {
    return runtime.frame();
}

/// Supplies button state and an accumulated crank delta for the next frame.
pub export fn webSetInput(buttons: pd.PDButtons, crank_delta_degrees: f32) void {
    runtime.setInput(buttons, crank_delta_degrees);
}

/// Supplies the browser's elapsed wall time for the next frame.
pub export fn webSetElapsedTime(milliseconds: f32) void {
    runtime.setElapsedMilliseconds(milliseconds);
}

pub export fn webLastErrorCode() c_int {
    return runtime.lastErrorCode();
}

pub export fn webActivateMenu(index: u32) void {
    runtime.activateMenu(index);
}

pub export fn webSetMenuValue(index: u32, value: c_int) void {
    runtime.setMenuValue(index, value);
}

/// The backing storage is a Playdate-shaped one-bit framebuffer.
pub export fn webFramebufferPtr() usize {
    return @intFromPtr(runtime.framebufferPointer());
}

pub export fn webFramebufferLen() usize {
    return runtime.framebufferLength();
}
