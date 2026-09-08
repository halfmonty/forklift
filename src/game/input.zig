const pdapi = @import("../platform_api.zig");

pub const FrameInput = struct {
    held: pdapi.PDButtons,
    pushed: pdapi.PDButtons,
    crank_delta_deg: f32,
    dt: f32,
    frame_ms: f32,
};

pub fn read(playdate: *pdapi.PlaydateAPI) FrameInput {
    var held: pdapi.PDButtons = 0;
    var pushed: pdapi.PDButtons = 0;
    playdate.system.getButtonState(&held, &pushed, null);

    const raw_dt = playdate.system.getElapsedTime();
    playdate.system.resetElapsedTime();

    return .{
        .held = held,
        .pushed = pushed,
        .crank_delta_deg = playdate.system.getCrankChange(),
        .dt = @min(raw_dt, 1.0 / 15.0),
        .frame_ms = raw_dt * 1000.0,
    };
}
