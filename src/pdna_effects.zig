const adapter = @import("pdna_effect_adapter.zig");

// Generated-data shape: PDNA exports replace these constants without changing
// runtime audio code.
pub const pallet_engagement = adapter.EffectPreset{
    .voice = .{
        .waveform = .noise,
        .envelope = .{ .attack_s = 0.001, .decay_s = 0.018, .sustain = 0.0, .release_s = 0.045 },
        .volume = 0.24,
    },
    .note = 54,
    .velocity = 0.85,
    .duration_s = 0.065,
};

pub const fork_height_move = adapter.EffectPreset{
    .voice = .{
        .waveform = .triangle,
        .envelope = .{ .attack_s = 0.004, .decay_s = 0.025, .sustain = 0.2, .release_s = 0.045 },
        .volume = 0.5,
        .pitch_source = .{ .motion = .{ .start_semitones = 0, .end_semitones = 4, .duration_s = 0.3 } },
    },
    .note = 57,
    .velocity = 0.65,
    .duration_s = 0.3,
};
