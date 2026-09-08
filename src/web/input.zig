const std = @import("std");
const pd = @import("api.zig");

pub const InputState = struct {
    current: pd.PDButtons = 0,
    pushed: pd.PDButtons = 0,
    released: pd.PDButtons = 0,
    crank_change: f32 = 0,

    /// Called once by the host before every game frame. Button edges describe
    /// the transition since the immediately preceding host update.
    pub fn set(self: *InputState, buttons: pd.PDButtons, crank_delta: f32) void {
        self.pushed = buttons & ~self.current;
        self.released = self.current & ~buttons;
        self.current = buttons;
        self.crank_change += crank_delta;
    }

    /// Playdate's crank API consumes accumulated motion exactly once.
    pub fn takeCrankChange(self: *InputState) f32 {
        const result = self.crank_change;
        self.crank_change = 0;
        return result;
    }
};

test "button edges are retained until the next host input update" {
    var input = InputState{};
    input.set(pd.BUTTON_A, 3.5);

    try std.testing.expectEqual(pd.BUTTON_A, input.current);
    try std.testing.expectEqual(pd.BUTTON_A, input.pushed);
    try std.testing.expectEqual(@as(pd.PDButtons, 0), input.released);
    try std.testing.expectEqual(@as(f32, 3.5), input.takeCrankChange());
}

test "releasing a held button reports a release edge and clears pushed" {
    var input = InputState{};
    input.set(pd.BUTTON_A, 0);
    input.set(0, 0);

    try std.testing.expectEqual(@as(pd.PDButtons, 0), input.current);
    try std.testing.expectEqual(@as(pd.PDButtons, 0), input.pushed);
    try std.testing.expectEqual(pd.BUTTON_A, input.released);
}
