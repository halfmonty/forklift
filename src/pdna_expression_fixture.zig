const pdna = @import("pdna_song_adapter.zig");

const lead_notes = [_]pdna.NoteEvent{.{ .step = 0, .length = 4, .note = 72, .velocity = 0.7 }};
const slide_notes = [_]pdna.NoteEvent{.{ .step = 0, .length = 4, .note = 60, .velocity = 0.7 }};
const tremolo_notes = [_]pdna.NoteEvent{.{ .step = 0, .length = 4, .note = 48, .velocity = 0.7 }};
const kit_notes = [_]pdna.NoteEvent{
    .{ .step = 0, .length = 1, .note = 36, .velocity = 0.8 },
    .{ .step = 2, .length = 1, .note = 42, .velocity = 0.7 },
    .{ .step = 4, .length = 1, .note = 45, .velocity = 0.7 },
};

pub const expressive_fixture = pdna.SongPreset{
    .steps_per_second = 8,
    .length_steps = 8,
    .loop_start_step = 0,
    .loop_end_step_inclusive = 7,
    .tracks = .{
        .{ .voices = &.{.{ .key_start = 0, .key_end = 127, .voice = .{
            .waveform = .square,
            .envelope = .{ .attack_s = 0.005, .decay_s = 0.04, .sustain = 0.5, .release_s = 0.03, .curvature = 0.35 },
            .volume = 0.1,
            .pitch_modulation = .{ .vibrato = .{ .shape = .sine, .rate_hz = 5.5, .depth = 0.2, .ramp_s = 0.08 } },
        } }}, .notes = &lead_notes },
        .{ .voices = &.{.{ .key_start = 0, .key_end = 127, .voice = .{ .waveform = .triangle, .envelope = .{ .attack_s = 0.005, .decay_s = 0.04, .sustain = 0.5, .release_s = 0.03 }, .volume = 0.1 } }}, .notes = &slide_notes, .pitch_automation = &.{ .{ .step = 0, .semitones = 0, .interpolate = false }, .{ .step = 4, .semitones = 7, .interpolate = true }, .{ .step = 7, .semitones = 0, .interpolate = false } } },
        .{ .voices = &.{.{ .key_start = 0, .key_end = 127, .voice = .{
            .waveform = .sawtooth,
            .envelope = .{ .attack_s = 0.005, .decay_s = 0.04, .sustain = 0.5, .release_s = 0.03 },
            .volume = 0.08,
            .amplitude_lfo = .{ .shape = .triangle, .rate_hz = 4, .center = 0.7, .depth = 0.2 },
        } }}, .notes = &tremolo_notes },
        .{ .voices = &.{
            .{ .key_start = 36, .key_end = 36, .voice = .{ .waveform = .triangle, .envelope = .{ .attack_s = 0.001, .decay_s = 0.04, .sustain = 0, .release_s = 0.04 }, .volume = 0.14, .pitch_modulation = .{ .motion = .{ .start_semitones = 12, .end_semitones = 0, .duration_s = 0.08 } } } },
            .{ .key_start = 42, .key_end = 42, .voice = .{ .waveform = .noise, .envelope = .{ .attack_s = 0.001, .decay_s = 0.01, .sustain = 0, .release_s = 0.01 }, .volume = 0.08 } },
            .{ .key_start = 45, .key_end = 45, .voice = .{ .waveform = .sine, .envelope = .{ .attack_s = 0.001, .decay_s = 0.06, .sustain = 0, .release_s = 0.05 }, .volume = 0.12, .pitch_modulation = .{ .motion = .{ .start_semitones = 5, .end_semitones = 0, .duration_s = 0.12 } } } },
        }, .notes = &kit_notes },
    },
};

test "expressive fixture stays within the song voice budget" {
    try @import("std").testing.expectEqual(@as(usize, 6), 1 + 1 + 1 + expressive_fixture.tracks[3].voices.len);
}
