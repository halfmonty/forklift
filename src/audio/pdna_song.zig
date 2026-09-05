const adapter = @import("pdna_song_adapter.zig");

// Generated-data shape: PDNA exports replace this data without changing
// runtime audio code.
const lead_notes = [_]adapter.NoteEvent{
    .{ .step = 0, .length = 3, .note = 72, .velocity = 0.7 },   .{ .step = 4, .length = 3, .note = 76, .velocity = 0.7 },
    .{ .step = 8, .length = 3, .note = 79, .velocity = 0.75 },  .{ .step = 12, .length = 3, .note = 76, .velocity = 0.7 },
    .{ .step = 16, .length = 3, .note = 74, .velocity = 0.7 },  .{ .step = 20, .length = 3, .note = 77, .velocity = 0.7 },
    .{ .step = 24, .length = 3, .note = 81, .velocity = 0.75 }, .{ .step = 28, .length = 3, .note = 77, .velocity = 0.7 },
};

const harmony_notes = [_]adapter.NoteEvent{
    .{ .step = 2, .length = 1, .note = 67, .velocity = 0.55 },  .{ .step = 6, .length = 1, .note = 67, .velocity = 0.55 },
    .{ .step = 10, .length = 1, .note = 71, .velocity = 0.55 }, .{ .step = 14, .length = 1, .note = 71, .velocity = 0.55 },
    .{ .step = 18, .length = 1, .note = 69, .velocity = 0.55 }, .{ .step = 22, .length = 1, .note = 69, .velocity = 0.55 },
    .{ .step = 26, .length = 1, .note = 72, .velocity = 0.55 }, .{ .step = 30, .length = 1, .note = 72, .velocity = 0.55 },
};

const bass_notes = [_]adapter.NoteEvent{
    .{ .step = 0, .length = 4, .note = 36, .velocity = 0.8 },  .{ .step = 4, .length = 4, .note = 36, .velocity = 0.8 },
    .{ .step = 8, .length = 4, .note = 43, .velocity = 0.8 },  .{ .step = 12, .length = 4, .note = 43, .velocity = 0.8 },
    .{ .step = 16, .length = 4, .note = 38, .velocity = 0.8 }, .{ .step = 20, .length = 4, .note = 38, .velocity = 0.8 },
    .{ .step = 24, .length = 4, .note = 45, .velocity = 0.8 }, .{ .step = 28, .length = 4, .note = 45, .velocity = 0.8 },
};

const percussion_notes = [_]adapter.NoteEvent{
    .{ .step = 0, .length = 1, .note = 48, .velocity = 0.8 },  .{ .step = 4, .length = 1, .note = 48, .velocity = 0.8 },
    .{ .step = 8, .length = 1, .note = 48, .velocity = 0.8 },  .{ .step = 12, .length = 1, .note = 48, .velocity = 0.8 },
    .{ .step = 16, .length = 1, .note = 48, .velocity = 0.8 }, .{ .step = 20, .length = 1, .note = 48, .velocity = 0.8 },
    .{ .step = 24, .length = 1, .note = 48, .velocity = 0.8 }, .{ .step = 28, .length = 1, .note = 48, .velocity = 0.8 },
};

fn track(voice: adapter.VoicePreset, notes: []const adapter.NoteEvent) adapter.TrackPreset {
    return .{ .voices = &.{.{ .key_range = .{ .first = 0, .last = 127 }, .voice = voice }}, .notes = notes };
}

pub const warehouse_loop = adapter.SongPreset{
    .steps_per_second = 8.0,
    .length_steps = 32,
    .loop_start_step = 0,
    .loop_end_step_inclusive = 31,
    .tracks = .{
        track(.{ .waveform = .square, .envelope = .{ .attack_s = 0.005, .decay_s = 0.04, .sustain = 0.55, .release_s = 0.03 }, .volume = 0.12 }, &lead_notes),
        track(.{ .waveform = .square, .envelope = .{ .attack_s = 0.003, .decay_s = 0.03, .sustain = 0.35, .release_s = 0.02 }, .volume = 0.075 }, &harmony_notes),
        track(.{ .waveform = .triangle, .envelope = .{ .attack_s = 0.005, .decay_s = 0.04, .sustain = 0.8, .release_s = 0.04 }, .volume = 0.18 }, &bass_notes),
        track(.{ .waveform = .noise, .envelope = .{ .attack_s = 0.001, .decay_s = 0.015, .sustain = 0.0, .release_s = 0.02 }, .volume = 0.07 }, &percussion_notes),
    },
};

test "PDNA loop export stores an inclusive endpoint" {
    try @import("std").testing.expectEqual(@as(u32, 31), warehouse_loop.loop_end_step_inclusive);
}
