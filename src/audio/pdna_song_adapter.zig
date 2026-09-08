const pd = @import("../platform_api.zig");
const voice = @import("pdna_effect_adapter.zig");

pub const track_count = 4;
pub const max_song_voice_count = 8;
pub const Waveform = voice.Waveform;
pub const EnvelopePreset = voice.EnvelopePreset;
pub const LfoPreset = voice.LfoPreset;
pub const PitchMotion = voice.PitchMotion;
pub const PitchSource = voice.PitchSource;
pub const VoicePreset = voice.VoicePreset;

pub const InitError = error{ NewMusicSynthFailed, NewMusicLfoFailed, NewInstrumentFailed, AddVoiceFailed, AddInstrumentSourceFailed, NewSequenceFailed, NewTrackFailed, NewPitchControlSignalFailed, TooManySongVoices, EmptyTrackVoices, InvalidKeyRange, OverlappingKeyRange, UnmappedNote, ConflictingPitchModulation, NoteEventsOutOfOrder, InvalidNoteLength, MultipleLegatoPhraseVoices, LegatoVoiceHasPitchSource };
pub const NoteEvent = struct { step: u32, length: u32, note: pd.MIDINote, velocity: f32 };
pub const PitchPoint = struct { step: u32, semitones: f32, interpolate: bool };
pub const KeyRange = struct { first: pd.MIDINote, last: pd.MIDINote };
pub const InstrumentVoicePreset = struct { key_range: KeyRange, voice: VoicePreset };
pub const TrackPreset = struct { volume: f32 = 1, voices: []const InstrumentVoicePreset, notes: []const NoteEvent, pitch_automation: []const PitchPoint = &.{} };
pub const SongPreset = struct { steps_per_second: f32, length_steps: u32, loop_start_step: u32, loop_end_step_inclusive: u32, tracks: [track_count]TrackPreset };

pub const SongPlayer = struct {
    playdate: *pd.PlaydateAPI,
    channel: *pd.SoundChannel,
    sequence: *pd.SoundSequence,
    synths: [max_song_voice_count]*pd.PDSynth,
    pitch_lfos: [max_song_voice_count]?*pd.PDSynthLFO,
    amplitude_lfos: [max_song_voice_count]?*pd.PDSynthLFO,
    instruments: [track_count]*pd.PDSynthInstrument,
    track_voice_starts: [track_count]usize,
    track_voice_counts: [track_count]usize,
    voice_count: usize,

    pub fn init(playdate: *pd.PlaydateAPI, channel: *pd.SoundChannel, preset: *const SongPreset) InitError!SongPlayer {
        var player = SongPlayer{ .playdate = playdate, .channel = channel, .sequence = undefined, .synths = undefined, .pitch_lfos = undefined, .amplitude_lfos = undefined, .instruments = undefined, .track_voice_starts = undefined, .track_voice_counts = undefined, .voice_count = 0 };
        var instruments_created: usize = 0;
        errdefer {
            for (0..instruments_created) |index| {
                _ = playdate.sound.channel.removeSource(channel, player.instruments[index]);
                playdate.sound.instrument.freeInstrument(player.instruments[index]);
            }
            for (0..player.voice_count) |index| {
                playdate.sound.synth.freeSynth(player.synths[index]);
                if (player.pitch_lfos[index]) |lfo| playdate.sound.lfo.freeLFO(lfo);
                if (player.amplitude_lfos[index]) |lfo| playdate.sound.lfo.freeLFO(lfo);
            }
        }
        for (preset.tracks, 0..) |track_preset, index| {
            const instrument = playdate.sound.instrument.newInstrument() orelse return error.NewInstrumentFailed;
            playdate.sound.instrument.setVolume(instrument, track_preset.volume, track_preset.volume);
            if (playdate.sound.channel.addSource(channel, instrument) == 0) {
                playdate.sound.instrument.freeInstrument(instrument);
                return error.AddInstrumentSourceFailed;
            }
            player.instruments[index] = instrument;
            instruments_created += 1;
        }
        for (preset.tracks, 0..) |track_preset, track_index| {
            if (track_preset.voices.len == 0) return error.EmptyTrackVoices;
            player.track_voice_starts[track_index] = player.voice_count;
            for (track_preset.voices, 0..) |track_voice, voice_index| {
                if (track_voice.key_range.first > track_voice.key_range.last) return error.InvalidKeyRange;
                for (track_preset.voices[0..voice_index]) |prior| if (track_voice.key_range.first <= prior.key_range.last and prior.key_range.first <= track_voice.key_range.last) return error.OverlappingKeyRange;
                if (player.voice_count == max_song_voice_count) return error.TooManySongVoices;
                const allocated = try createVoice(playdate, player.instruments[track_index], track_voice);
                player.synths[player.voice_count] = allocated.synth;
                player.pitch_lfos[player.voice_count] = allocated.pitch_lfo;
                player.amplitude_lfos[player.voice_count] = allocated.amplitude_lfo;
                player.voice_count += 1;
            }
            player.track_voice_counts[track_index] = player.voice_count - player.track_voice_starts[track_index];
            for (track_preset.notes, 0..) |note, note_index| {
                if (note.length == 0) return error.InvalidNoteLength;
                if (note_index != 0 and note.step < track_preset.notes[note_index - 1].step) return error.NoteEventsOutOfOrder;
                if (!mapsNote(track_preset.voices, note.note)) return error.UnmappedNote;
            }
            if (track_preset.pitch_automation.len != 0) for (track_preset.voices) |track_voice| if (track_voice.voice.pitch_source != .none) return error.ConflictingPitchModulation;
        }
        const sequence = playdate.sound.sequence.newSequence() orelse return error.NewSequenceFailed;
        errdefer playdate.sound.sequence.freeSequence(sequence);
        for (preset.tracks, 0..) |track_preset, index| {
            const track = playdate.sound.sequence.addTrack(sequence) orelse return error.NewTrackFailed;
            playdate.sound.track.setInstrument(track, player.instruments[index]);
            const legato_voice_index = try legatoPhraseVoiceIndex(track_preset);
            if (legato_voice_index) |voice_index| {
                if (track_preset.pitch_automation.len != 0) return error.ConflictingPitchModulation;
                if (track_preset.voices[voice_index].voice.pitch_source != .none) return error.LegatoVoiceHasPitchSource;
                const signal = playdate.sound.track.getSignalForController(track, 1, 1) orelse return error.NewPitchControlSignalFailed;
                const synth_index = player.track_voice_starts[index] + voice_index;
                playdate.sound.synth.setFrequencyModulator(player.synths[synth_index], @ptrCast(signal));
                try addTrackNotes(playdate, track, track_preset, voice_index, signal);
            } else {
                for (track_preset.notes) |note| playdate.sound.track.addNoteEvent(track, note.step, note.length, note.note, note.velocity);
            }
            if (track_preset.pitch_automation.len != 0) {
                const signal = playdate.sound.track.getSignalForController(track, 1, 1) orelse return error.NewPitchControlSignalFailed;
                for (track_preset.pitch_automation) |point| playdate.sound.controlsignal.addEvent(signal, @intCast(point.step), point.semitones / 12.0, @intFromBool(point.interpolate));
                const voice_start = player.track_voice_starts[index];
                for (voice_start..voice_start + player.track_voice_counts[index]) |voice_index| playdate.sound.synth.setFrequencyModulator(player.synths[voice_index], @ptrCast(signal));
            }
        }
        playdate.sound.sequence.setTempo(sequence, preset.steps_per_second);
        playdate.sound.sequence.setLoops(sequence, @intCast(preset.loop_start_step), @intCast(preset.loop_end_step_inclusive), 0);
        player.sequence = sequence;
        return player;
    }

    pub fn start(self: *SongPlayer) void {
        self.playdate.sound.sequence.play(self.sequence, musicFinished, null);
    }
    pub fn stop(self: *SongPlayer) void {
        self.playdate.sound.sequence.stop(self.sequence);
    }
    pub fn deinit(self: *SongPlayer) void {
        self.stop();
        self.playdate.sound.sequence.freeSequence(self.sequence);
        for (self.instruments) |instrument| {
            _ = self.playdate.sound.channel.removeSource(self.channel, instrument);
            self.playdate.sound.instrument.freeInstrument(instrument);
        }
        for (0..self.voice_count) |index| {
            self.playdate.sound.synth.freeSynth(self.synths[index]);
            if (self.pitch_lfos[index]) |lfo| self.playdate.sound.lfo.freeLFO(lfo);
            if (self.amplitude_lfos[index]) |lfo| self.playdate.sound.lfo.freeLFO(lfo);
        }
    }
};

fn mapsNote(voices: []const InstrumentVoicePreset, note: pd.MIDINote) bool {
    for (voices) |voice_preset| if (note >= voice_preset.key_range.first and note <= voice_preset.key_range.last) return true;
    return false;
}
fn voiceIndexForNote(voices: []const InstrumentVoicePreset, note: pd.MIDINote) usize {
    for (voices, 0..) |voice_preset, index| if (note >= voice_preset.key_range.first and note <= voice_preset.key_range.last) return index;
    unreachable;
}
fn noteEnd(note: NoteEvent) u32 {
    return note.step + note.length;
}
fn legatoPhraseVoiceIndex(track_preset: TrackPreset) InitError!?usize {
    var phrase_voice_index: ?usize = null;
    for (track_preset.notes, 0..) |note, note_index| {
        const voice_index = voiceIndexForNote(track_preset.voices, note.note);
        if (!track_preset.voices[voice_index].voice.envelope.legato) continue;
        if (phraseStartIndex(track_preset, note_index, voice_index) == note_index) continue;
        if (phrase_voice_index) |existing| {
            if (existing != voice_index) return error.MultipleLegatoPhraseVoices;
        } else phrase_voice_index = voice_index;
    }
    return phrase_voice_index;
}
fn phraseStartIndex(track_preset: TrackPreset, note_index: usize, voice_index: usize) usize {
    var start = note_index;
    while (true) {
        var prior_index: ?usize = null;
        for (track_preset.notes[0..start], 0..) |prior, index| {
            if (voiceIndexForNote(track_preset.voices, prior.note) != voice_index) continue;
            if (noteEnd(prior) > track_preset.notes[start].step) prior_index = index;
        }
        start = prior_index orelse return start;
    }
}
fn phraseEnd(track_preset: TrackPreset, phrase_start_index: usize, voice_index: usize) u32 {
    var end = noteEnd(track_preset.notes[phrase_start_index]);
    for (track_preset.notes[phrase_start_index + 1 ..]) |note| {
        if (note.step >= end) break;
        if (voiceIndexForNote(track_preset.voices, note.note) == voice_index) end = @max(end, noteEnd(note));
    }
    return end;
}
fn addTrackNotes(playdate: *pd.PlaydateAPI, track: *pd.SequenceTrack, track_preset: TrackPreset, legato_voice_index: usize, signal: *pd.ControlSignal) InitError!void {
    for (track_preset.notes, 0..) |note, note_index| {
        if (voiceIndexForNote(track_preset.voices, note.note) != legato_voice_index) {
            playdate.sound.track.addNoteEvent(track, note.step, note.length, note.note, note.velocity);
            continue;
        }
        const phrase_start_index = phraseStartIndex(track_preset, note_index, legato_voice_index);
        if (phrase_start_index == note_index) {
            playdate.sound.track.addNoteEvent(track, note.step, phraseEnd(track_preset, note_index, legato_voice_index) - note.step, note.note, note.velocity);
            playdate.sound.controlsignal.addEvent(signal, @intCast(note.step), 0, 0);
        } else {
            const base_note = track_preset.notes[phrase_start_index].note;
            const semitones = note.note - base_note;
            playdate.sound.controlsignal.addEvent(signal, @intCast(note.step), semitones / 12.0, 1);
        }
    }
}
const AllocatedVoice = struct {
    synth: *pd.PDSynth,
    pitch_lfo: ?*pd.PDSynthLFO,
    amplitude_lfo: ?*pd.PDSynthLFO,
};
fn createVoice(playdate: *pd.PlaydateAPI, instrument: *pd.PDSynthInstrument, preset: InstrumentVoicePreset) InitError!AllocatedVoice {
    const synth = playdate.sound.synth.newSynth() orelse return error.NewMusicSynthFailed;
    errdefer playdate.sound.synth.freeSynth(synth);
    const pitch_lfo = if (preset.voice.pitch_source != .none) playdate.sound.lfo.newLFO(.kLFOTypeSine) orelse return error.NewMusicLfoFailed else null;
    errdefer if (pitch_lfo) |lfo| playdate.sound.lfo.freeLFO(lfo);
    const amplitude_lfo = if (preset.voice.amplitude_lfo != null) playdate.sound.lfo.newLFO(.kLFOTypeSine) orelse return error.NewMusicLfoFailed else null;
    errdefer if (amplitude_lfo) |lfo| playdate.sound.lfo.freeLFO(lfo);
    voice.configureVoice(playdate, synth, pitch_lfo, amplitude_lfo, preset.voice);
    if (playdate.sound.instrument.addVoice(instrument, synth, preset.key_range.first, preset.key_range.last, 0) == 0) return error.AddVoiceFailed;
    return .{ .synth = synth, .pitch_lfo = pitch_lfo, .amplitude_lfo = amplitude_lfo };
}
fn musicFinished(sequence: ?*pd.SoundSequence, userdata: ?*anyopaque) callconv(.c) void {
    _ = sequence;
    _ = userdata;
}
test "song presets retain four logical tracks" {
    try @import("std").testing.expectEqual(@as(usize, 4), track_count);
}
test "overlapping notes on a legato voice form one held phrase" {
    const voices = [_]InstrumentVoicePreset{.{ .key_range = .{ .first = 0, .last = 127 }, .voice = .{ .waveform = .square, .envelope = .{ .attack_s = 0, .decay_s = 0, .sustain = 1, .release_s = 0, .legato = true }, .volume = 1 } }};
    const notes = [_]NoteEvent{
        .{ .step = 0, .length = 2, .note = 72, .velocity = 1 },
        .{ .step = 1, .length = 2, .note = 67, .velocity = 1 },
        .{ .step = 2, .length = 2, .note = 65, .velocity = 1 },
        .{ .step = 3, .length = 2, .note = 60, .velocity = 1 },
        .{ .step = 4, .length = 1, .note = 64, .velocity = 1 },
    };
    const track = TrackPreset{ .voices = &voices, .notes = &notes };
    try @import("std").testing.expectEqual(@as(?usize, 0), try legatoPhraseVoiceIndex(track));
    try @import("std").testing.expectEqual(@as(usize, 0), phraseStartIndex(track, 4, 0));
    try @import("std").testing.expectEqual(@as(u32, 5), phraseEnd(track, 0, 0));
}
