const pd = @import("../playdate_api_definitions.zig");

const effect_voice_count = 2;

pub const InitError = error{ NewEffectSynthFailed, NewEffectLfoFailed, AddEffectVoiceFailed };
pub const Waveform = enum { square, triangle, sine, noise, sawtooth };
pub const LfoShape = enum { square, triangle, sine, sample_and_hold, sawtooth_up, sawtooth_down };

pub const EnvelopePreset = struct {
    attack_s: f32,
    decay_s: f32,
    sustain: f32,
    release_s: f32,
    curvature: f32 = 0,
    velocity_sensitivity: f32 = 1,
    legato: bool = false,
    retrigger: bool = false,
    rate_scaling: ?RateScaling = null,
};
pub const RateScaling = struct { scaling: f32, start_note: pd.MIDINote, end_note: pd.MIDINote };
pub const LfoPreset = struct {
    shape: LfoShape,
    rate_hz: f32,
    center: f32 = 0,
    depth: f32,
    holdoff_s: f32 = 0,
    ramp_s: f32 = 0,
    start_phase: f32 = 0,
    retrigger: bool = true,
};
pub const PitchMotion = struct { start_semitones: f32, end_semitones: f32, duration_s: f32 };
pub const PitchSource = union(enum) { none, vibrato: LfoPreset, motion: PitchMotion };
pub const VoicePreset = struct {
    waveform: Waveform,
    envelope: EnvelopePreset,
    volume: f32,
    pitch_source: PitchSource = .none,
    amplitude_lfo: ?LfoPreset = null,
};
pub const EffectPreset = struct { voice: VoicePreset, note: pd.MIDINote, velocity: f32, duration_s: f32 };

pub const EffectPlayer = struct {
    playdate: *pd.PlaydateAPI,
    channel: *pd.SoundChannel,
    synths: [effect_voice_count]*pd.PDSynth,
    pitch_lfos: [effect_voice_count]*pd.PDSynthLFO,
    amplitude_lfos: [effect_voice_count]*pd.PDSynthLFO,
    next_voice: usize = 0,

    pub fn init(playdate: *pd.PlaydateAPI, channel: *pd.SoundChannel) InitError!EffectPlayer {
        var player = EffectPlayer{ .playdate = playdate, .channel = channel, .synths = undefined, .pitch_lfos = undefined, .amplitude_lfos = undefined };
        var created: usize = 0;
        errdefer for (0..created) |index| {
            _ = playdate.sound.channel.removeSource(channel, player.synths[index]);
            playdate.sound.synth.freeSynth(player.synths[index]);
            playdate.sound.lfo.freeLFO(player.pitch_lfos[index]);
            playdate.sound.lfo.freeLFO(player.amplitude_lfos[index]);
        };
        for (0..effect_voice_count) |index| {
            const synth = playdate.sound.synth.newSynth() orelse return error.NewEffectSynthFailed;
            const pitch_lfo = playdate.sound.lfo.newLFO(.kLFOTypeSine) orelse {
                playdate.sound.synth.freeSynth(synth);
                return error.NewEffectLfoFailed;
            };
            const amplitude_lfo = playdate.sound.lfo.newLFO(.kLFOTypeSine) orelse {
                playdate.sound.lfo.freeLFO(pitch_lfo);
                playdate.sound.synth.freeSynth(synth);
                return error.NewEffectLfoFailed;
            };
            if (playdate.sound.channel.addSource(channel, synth) == 0) {
                playdate.sound.lfo.freeLFO(amplitude_lfo);
                playdate.sound.lfo.freeLFO(pitch_lfo);
                playdate.sound.synth.freeSynth(synth);
                return error.AddEffectVoiceFailed;
            }
            player.synths[index] = synth;
            player.pitch_lfos[index] = pitch_lfo;
            player.amplitude_lfos[index] = amplitude_lfo;
            created += 1;
        }
        return player;
    }

    pub fn play(self: *EffectPlayer, preset: EffectPreset) void {
        const index = self.next_voice;
        self.next_voice = (self.next_voice + 1) % effect_voice_count;
        configureVoice(self.playdate, self.synths[index], self.pitch_lfos[index], self.amplitude_lfos[index], preset.voice);
        self.playdate.sound.synth.playMIDINote(self.synths[index], preset.note, preset.velocity, preset.duration_s, 0);
    }

    pub fn deinit(self: *EffectPlayer) void {
        for (self.synths, self.pitch_lfos, self.amplitude_lfos) |synth, pitch_lfo, amplitude_lfo| {
            _ = self.playdate.sound.channel.removeSource(self.channel, synth);
            self.playdate.sound.synth.freeSynth(synth);
            self.playdate.sound.lfo.freeLFO(pitch_lfo);
            self.playdate.sound.lfo.freeLFO(amplitude_lfo);
        }
    }
};

pub fn configureVoice(playdate: *pd.PlaydateAPI, synth: *pd.PDSynth, pitch_lfo: ?*pd.PDSynthLFO, amplitude_lfo: ?*pd.PDSynthLFO, voice: VoicePreset) void {
    playdate.sound.synth.setWaveform(synth, nativeWaveform(voice.waveform));
    playdate.sound.synth.setAttackTime(synth, voice.envelope.attack_s);
    playdate.sound.synth.setDecayTime(synth, voice.envelope.decay_s);
    playdate.sound.synth.setSustainLevel(synth, voice.envelope.sustain);
    playdate.sound.synth.setReleaseTime(synth, voice.envelope.release_s);
    playdate.sound.synth.setVolume(synth, voice.volume, voice.volume);
    if (playdate.sound.synth.getEnvelope(synth)) |envelope| {
        playdate.sound.envelope.setCurvature(envelope, voice.envelope.curvature);
        playdate.sound.envelope.setVelocitySensitivity(envelope, voice.envelope.velocity_sensitivity);
        playdate.sound.envelope.setLegato(envelope, @intFromBool(voice.envelope.legato));
        playdate.sound.envelope.setRetrigger(envelope, @intFromBool(voice.envelope.retrigger));
        if (voice.envelope.rate_scaling) |scaling| playdate.sound.envelope.setRateScaling(envelope, scaling.scaling, scaling.start_note, scaling.end_note) else playdate.sound.envelope.setRateScaling(envelope, 1, 0, 127);
    }
    playdate.sound.synth.setFrequencyModulator(synth, null);
    switch (voice.pitch_source) {
        .none => {},
        else => |source| {
            const lfo = pitch_lfo orelse return;
            switch (source) {
                .none => unreachable,
                .vibrato => |preset| configureLfo(playdate, lfo, preset, 1.0 / 12.0),
                .motion => |motion| configurePitchMotion(playdate, lfo, motion),
            }
            playdate.sound.synth.setFrequencyModulator(synth, @ptrCast(lfo));
        },
    }
    playdate.sound.synth.setAmplitudeModulator(synth, null);
    if (voice.amplitude_lfo) |preset| {
        const lfo = amplitude_lfo orelse return;
        configureLfo(playdate, lfo, preset, 1);
        playdate.sound.synth.setAmplitudeModulator(synth, @ptrCast(lfo));
    }
}

fn configureLfo(playdate: *pd.PlaydateAPI, lfo: *pd.PDSynthLFO, preset: LfoPreset, scale: f32) void {
    playdate.sound.lfo.setType(lfo, nativeLfoShape(preset.shape));
    playdate.sound.lfo.setRate(lfo, preset.rate_hz);
    playdate.sound.lfo.setCenter(lfo, preset.center * scale);
    playdate.sound.lfo.setDepth(lfo, preset.depth * scale);
    playdate.sound.lfo.setDelay(lfo, preset.holdoff_s, preset.ramp_s);
    playdate.sound.lfo.setStartPhase(lfo, preset.start_phase);
    playdate.sound.lfo.setRetrigger(lfo, @intFromBool(preset.retrigger));
}
fn configurePitchMotion(playdate: *pd.PlaydateAPI, lfo: *pd.PDSynthLFO, motion: PitchMotion) void {
    const start = motion.start_semitones / 12.0;
    const end = motion.end_semitones / 12.0;
    playdate.sound.lfo.setType(lfo, if (end >= start) .kLFOTypeSawtoothUp else .kLFOTypeSawtoothDown);
    playdate.sound.lfo.setRate(lfo, 1.0 / motion.duration_s);
    playdate.sound.lfo.setCenter(lfo, (start + end) / 2.0);
    playdate.sound.lfo.setDepth(lfo, @abs(end - start) / 2.0);
    playdate.sound.lfo.setDelay(lfo, 0, 0);
    playdate.sound.lfo.setStartPhase(lfo, 0);
    playdate.sound.lfo.setRetrigger(lfo, 1);
}
pub fn nativeWaveform(waveform: Waveform) pd.SoundWaveform {
    return switch (waveform) {
        .square => .kWaveformSquare,
        .triangle => .kWaveformTriangle,
        .sine => .kWaveformSine,
        .noise => .kWaveformNoise,
        .sawtooth => .kWaveformSawtooth,
    };
}
fn nativeLfoShape(shape: LfoShape) pd.LFOType {
    return switch (shape) {
        .square => .kLFOTypeSquare,
        .triangle => .kLFOTypeTriangle,
        .sine => .kLFOTypeSine,
        .sample_and_hold => .kLFOTypeSampleAndHold,
        .sawtooth_up => .kLFOTypeSawtoothUp,
        .sawtooth_down => .kLFOTypeSawtoothDown,
    };
}

test "pitch motion maps semitones to octaves" {
    const motion = PitchMotion{ .start_semitones = 12, .end_semitones = -12, .duration_s = 0.1 };
    try @import("std").testing.expectEqual(@as(f32, 1), motion.start_semitones / 12.0);
    try @import("std").testing.expectEqual(@as(f32, -1), motion.end_semitones / 12.0);
}
