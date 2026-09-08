const std = @import("std");
const pd = @import("api.zig");
const framebuffer_module = @import("framebuffer.zig");
const font = @import("font.zig");
const input_module = @import("input.zig");
const storage_module = @import("storage.zig");

const EventHandler = *const fn (*pd.PlaydateAPI, pd.PDSystemEvent, u32) callconv(.c) c_int;
extern "env" fn webRuntimeError(code: c_int) void;
extern "env" fn webStorageRead(output: [*]u8, capacity: usize) c_int;
extern "env" fn webStorageWrite(input: [*]const u8, len: usize) c_int;
extern "env" fn webStorageClear() c_int;
extern "env" fn webAudioPlayNote(
    waveform: c_int,
    note: f32,
    velocity: f32,
    duration: f32,
    attack: f32,
    decay: f32,
    sustain: f32,
    release: f32,
    volume: f32,
    frequency_lfo_type: c_int,
    frequency_lfo_rate: f32,
    frequency_lfo_center: f32,
    frequency_lfo_depth: f32,
    frequency_lfo_holdoff: f32,
    frequency_lfo_ramp: f32,
    frequency_lfo_phase: f32,
    frequency_lfo_retrigger: c_int,
    amplitude_lfo_type: c_int,
    amplitude_lfo_rate: f32,
    amplitude_lfo_center: f32,
    amplitude_lfo_depth: f32,
    amplitude_lfo_holdoff: f32,
    amplitude_lfo_ramp: f32,
    amplitude_lfo_phase: f32,
    amplitude_lfo_retrigger: c_int,
) void;
extern "env" fn webAudioResetSequence() void;
extern "env" fn webAudioQueueSequenceNote(
    waveform: c_int,
    note: f32,
    velocity: f32,
    step: u32,
    length: u32,
    attack: f32,
    decay: f32,
    sustain: f32,
    release: f32,
    volume: f32,
    frequency_lfo_type: c_int,
    frequency_lfo_rate: f32,
    frequency_lfo_center: f32,
    frequency_lfo_depth: f32,
    frequency_lfo_holdoff: f32,
    frequency_lfo_ramp: f32,
    frequency_lfo_phase: f32,
    frequency_lfo_retrigger: c_int,
    amplitude_lfo_type: c_int,
    amplitude_lfo_rate: f32,
    amplitude_lfo_center: f32,
    amplitude_lfo_depth: f32,
    amplitude_lfo_holdoff: f32,
    amplitude_lfo_ramp: f32,
    amplitude_lfo_phase: f32,
    amplitude_lfo_retrigger: c_int,
    track_index: u32,
) void;
extern "env" fn webAudioQueueSequenceControlPoint(track_index: u32, step: c_int, value: f32, interpolate: c_int) void;
extern "env" fn webAudioSetSequenceTempo(steps_per_second: f32) void;
extern "env" fn webAudioSetSequenceLoops(loop_start: c_int, loop_end: c_int, loops: c_int) void;
extern "env" fn webAudioStartSequence() void;
extern "env" fn webAudioStopSequence() void;
extern "env" fn webAudioStopSynth() void;

var initialized = false;
var update_callback: ?pd.PDCallbackFunction = null;
var update_userdata: ?*anyopaque = null;
var elapsed_seconds: f32 = 0;
var input_state = input_module.InputState{};
var last_error_code: c_int = 0;
var framebuffer = framebuffer_module.Framebuffer{};
var save_storage = storage_module.Storage{};

var font_handle: u8 = 0;
var file_handle: u8 = 0;
var channel_handle: u8 = 0;
var synth_handle: u8 = 0;
var lfo_handle: u8 = 0;
var envelope_handle: u8 = 0;
var sequence_handle: u8 = 0;
var synth_waveform: pd.SoundWaveform = .kWaveformSine;
var synth_attack: f32 = 0.005;
var synth_decay: f32 = 0.05;
var synth_sustain: f32 = 0.5;
var synth_release: f32 = 0.05;
var synth_volume: f32 = 1;
const LfoRecord = struct {
    waveform: c_int = -1,
    rate: f32 = 0,
    center: f32 = 0,
    depth: f32 = 0,
    holdoff: f32 = 0,
    ramp: f32 = 0,
    phase: f32 = 0,
    retrigger: c_int = 0,
};
var lfo_state = LfoRecord{};
var frequency_lfo = LfoRecord{};
var amplitude_lfo = LfoRecord{};

const max_music_instruments = 4;
const max_instrument_voices = 8;
const max_sequence_tracks = 4;
const max_track_control_points = 32;
const VoiceRecord = struct {
    first_note: pd.MIDINote,
    last_note: pd.MIDINote,
    waveform: c_int,
    attack: f32,
    decay: f32,
    sustain: f32,
    release: f32,
    volume: f32,
    frequency_lfo: LfoRecord,
    amplitude_lfo: LfoRecord,
};
const InstrumentRecord = struct {
    volume: f32 = 1,
    voice_count: usize = 0,
    voices: [max_instrument_voices]VoiceRecord = undefined,
};
const ControlSignalRecord = struct {
    track_index: u32 = 0,
};
const TrackRecord = struct {
    instrument: ?*InstrumentRecord = null,
    index: u32 = 0,
    signal: ControlSignalRecord = .{},
    control_count: usize = 0,
};
var instrument_records: [max_music_instruments]InstrumentRecord = undefined;
var instrument_count: usize = 0;
var track_records: [max_sequence_tracks]TrackRecord = undefined;
var track_count: usize = 0;

const max_menu_items = 2;
const MenuRecord = struct {
    callback: ?pd.PDMenuItemCallbackFunction = null,
    userdata: ?*anyopaque = null,
    value: c_int = 0,
};
var menu_records: [max_menu_items]MenuRecord = undefined;
var menu_count: usize = 0;

const system_api = pd.PlaydateSys{
    .realloc = systemRealloc,
    .setUpdateCallback = setUpdateCallback,
    .getButtonState = getButtonState,
    .getCrankChange = getCrankChange,
    .getElapsedTime = getElapsedTime,
    .resetElapsedTime = resetElapsedTime,
    .drawFPS = drawFPS,
    .addMenuItem = addMenuItem,
    .addOptionsMenuItem = addOptionsMenuItem,
    .getMenuItemValue = getMenuItemValue,
    .setMenuItemValue = setMenuItemValue,
    .@"error" = systemError,
};

const graphics_api = pd.PlaydateGraphics{
    .clear = clear,
    .drawLine = drawLine,
    .fillTriangle = fillTriangle,
    .drawRect = drawRect,
    .fillRect = fillRect,
    .fillEllipse = fillEllipse,
    .drawText = drawText,
    .loadFont = loadFont,
    .setFont = setFont,
    .getFrame = getFrame,
    .getDisplayFrame = getDisplayFrame,
    .markUpdatedRows = markUpdatedRows,
    .display = display,
};

const display_api = pd.PlaydateDisplay{ .setRefreshRate = setRefreshRate };
const file_api = pd.PlaydateFile{
    .stat = stat,
    .unlink = unlink,
    .open = open,
    .close = close,
    .read = read,
    .write = write,
    .flush = flush,
};
const channel_api = pd.PlaydateSoundChannel{
    .addSource = addSource,
    .removeSource = removeSource,
};
const synth_api = pd.PlaydateSoundSynth{
    .newSynth = newSynth,
    .freeSynth = freeSynth,
    .setWaveform = setWaveform,
    .setAttackTime = setAttackTime,
    .setDecayTime = setDecayTime,
    .setSustainLevel = setSustainLevel,
    .setReleaseTime = setReleaseTime,
    .setVolume = setSynthVolume,
    .getEnvelope = getEnvelope,
    .setFrequencyModulator = setFrequencyModulator,
    .setAmplitudeModulator = setAmplitudeModulator,
    .playMIDINote = playMIDINote,
    .stop = stopSynth,
};
const lfo_api = pd.PlaydateSoundLFO{
    .newLFO = newLFO,
    .freeLFO = freeLFO,
    .setType = setLFOType,
    .setRate = setLFORate,
    .setCenter = setLFOCenter,
    .setDepth = setLFODepth,
    .setDelay = setLFODelay,
    .setStartPhase = setLFOStartPhase,
    .setRetrigger = setLFORetrigger,
};
const envelope_api = pd.PlaydateSoundEnvelope{
    .setCurvature = setEnvelopeCurvature,
    .setVelocitySensitivity = setEnvelopeVelocitySensitivity,
    .setLegato = setEnvelopeLegato,
    .setRetrigger = setEnvelopeRetrigger,
    .setRateScaling = setEnvelopeRateScaling,
};
const sequence_api = pd.PlaydateSoundSequence{
    .newSequence = newSequence,
    .freeSequence = freeSequence,
    .addTrack = addTrack,
    .setTempo = setTempo,
    .setLoops = setLoops,
    .play = playSequence,
    .stop = stopSequence,
};
const track_api = pd.PlaydateSoundTrack{
    .setInstrument = setInstrument,
    .addNoteEvent = addNoteEvent,
    .getSignalForController = getSignalForController,
};
const control_signal_api = pd.PlaydateControlSignal{ .addEvent = addControlEvent };
const instrument_api = pd.PlaydateSoundInstrument{
    .newInstrument = newInstrument,
    .freeInstrument = freeInstrument,
    .addVoice = addVoice,
    .setVolume = setInstrumentVolume,
};
const sound_api = pd.PlaydateSound{
    .channel = &channel_api,
    .synth = &synth_api,
    .sequence = &sequence_api,
    .lfo = &lfo_api,
    .envelope = &envelope_api,
    .controlsignal = &control_signal_api,
    .track = &track_api,
    .instrument = &instrument_api,
    .getDefaultChannel = getDefaultChannel,
};

var api = pd.PlaydateAPI{
    .system = &system_api,
    .file = &file_api,
    .graphics = &graphics_api,
    .display = &display_api,
    .sound = &sound_api,
};

pub fn init(event_handler: EventHandler) c_int {
    if (initialized) return 1;
    hydrateSaveStorage();
    // `eventHandler` returns zero after a successful Playdate EventInit; its
    // result is not the update-callback convention used by `webFrame`.
    _ = event_handler(&api, .EventInit, 0);
    if (update_callback == null) {
        last_error_code = 1;
        return 0;
    }
    initialized = true;
    return 1;
}

pub fn frame() c_int {
    const callback = update_callback orelse return 0;
    const result = callback(update_userdata);
    if (result == 0) last_error_code = 2;
    return result;
}

pub fn setInput(buttons: pd.PDButtons, new_crank_change: f32) void {
    input_state.set(buttons, new_crank_change);
}

pub fn setElapsedMilliseconds(milliseconds: f32) void {
    elapsed_seconds = @max(0, milliseconds) / 1000.0;
}

pub fn lastErrorCode() c_int {
    return last_error_code;
}

pub fn activateMenu(index: u32) void {
    if (index >= menu_count) return;
    const record = &menu_records[index];
    if (record.callback) |callback| callback(record.userdata);
}

pub fn setMenuValue(index: u32, value: c_int) void {
    if (index >= menu_count) return;
    const record = &menu_records[index];
    record.value = value;
    if (record.callback) |callback| callback(record.userdata);
}

pub fn framebufferPointer() [*]const u8 {
    return &framebuffer.bytes;
}

pub fn framebufferLength() usize {
    return framebuffer_module.byte_len;
}

fn systemRealloc(ptr: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
    // Forklift's startup allocations are page-lifetime objects. Supporting
    // non-null reallocation needs allocation-size bookkeeping and belongs with
    // the broader runtime allocator work, not this lifecycle bootstrap.
    if (ptr != null) return null;
    const bytes = std.heap.wasm_allocator.alloc(u8, size) catch return null;
    return bytes.ptr;
}

fn setUpdateCallback(callback: ?pd.PDCallbackFunction, userdata: ?*anyopaque) callconv(.c) void {
    update_callback = callback;
    update_userdata = userdata;
}

fn getButtonState(current: ?*pd.PDButtons, pushed: ?*pd.PDButtons, released: ?*pd.PDButtons) callconv(.c) void {
    if (current) |out| out.* = input_state.current;
    if (pushed) |out| out.* = input_state.pushed;
    if (released) |out| out.* = input_state.released;
}

fn getCrankChange() callconv(.c) f32 {
    return input_state.takeCrankChange();
}

fn getElapsedTime() callconv(.c) f32 {
    return elapsed_seconds;
}

fn resetElapsedTime() callconv(.c) void {
    elapsed_seconds = 0;
}

fn drawFPS(_: c_int, _: c_int) callconv(.c) void {}
fn addMenuItem(_: ?[*:0]const u8, callback: ?pd.PDMenuItemCallbackFunction, userdata: ?*anyopaque) callconv(.c) ?*pd.PDMenuItem {
    return newMenuRecord(callback, userdata);
}
fn addOptionsMenuItem(_: ?[*:0]const u8, _: [*c]?[*:0]const u8, _: c_int, callback: ?pd.PDMenuItemCallbackFunction, userdata: ?*anyopaque) callconv(.c) ?*pd.PDMenuItem {
    return newMenuRecord(callback, userdata);
}
fn newMenuRecord(callback: ?pd.PDMenuItemCallbackFunction, userdata: ?*anyopaque) ?*pd.PDMenuItem {
    if (menu_count == max_menu_items) return null;
    const record = &menu_records[menu_count];
    record.* = .{ .callback = callback, .userdata = userdata };
    menu_count += 1;
    return @ptrCast(record);
}
fn menuRecord(item: ?*pd.PDMenuItem) ?*MenuRecord {
    return @ptrCast(@alignCast(item orelse return null));
}
fn getMenuItemValue(item: ?*pd.PDMenuItem) callconv(.c) c_int {
    return (menuRecord(item) orelse return 0).value;
}
fn setMenuItemValue(item: ?*pd.PDMenuItem, value: c_int) callconv(.c) void {
    const record = menuRecord(item) orelse return;
    record.value = value;
}
fn systemError(_: ?[*:0]const u8, ...) callconv(.c) void {
    last_error_code = 3;
    webRuntimeError(last_error_code);
    if (@import("builtin").mode == .Debug) @trap();
}

fn colorFromLCD(color: pd.LCDColor) framebuffer_module.Color {
    return if (color == @intFromEnum(pd.LCDSolidColor.ColorBlack)) .black else .white;
}

fn clear(color: pd.LCDColor) callconv(.c) void {
    framebuffer.clear(colorFromLCD(color));
}
fn drawLine(x0: c_int, y0: c_int, x1: c_int, y1: c_int, width: c_int, color: pd.LCDColor) callconv(.c) void {
    framebuffer.line(x0, y0, x1, y1, width, colorFromLCD(color));
}
fn fillTriangle(x0: c_int, y0: c_int, x1: c_int, y1: c_int, x2: c_int, y2: c_int, color: pd.LCDColor) callconv(.c) void {
    framebuffer.fillTriangle(x0, y0, x1, y1, x2, y2, colorFromLCD(color));
}
fn drawRect(x: c_int, y: c_int, width: c_int, height: c_int, color: pd.LCDColor) callconv(.c) void {
    framebuffer.drawRect(x, y, width, height, colorFromLCD(color));
}
fn fillRect(x: c_int, y: c_int, width: c_int, height: c_int, color: pd.LCDColor) callconv(.c) void {
    framebuffer.fillRect(x, y, width, height, colorFromLCD(color));
}
fn fillEllipse(x: c_int, y: c_int, width: c_int, height: c_int, _: f32, _: f32, color: pd.LCDColor) callconv(.c) void {
    framebuffer.fillEllipse(x, y, width, height, colorFromLCD(color));
}
fn drawText(text: ?*const anyopaque, len: usize, _: pd.PDStringEncoding, x: c_int, y: c_int) callconv(.c) c_int {
    const bytes: [*]const u8 = @ptrCast(text orelse return 0);
    return font.drawText(&framebuffer, bytes[0..len], x, y);
}
fn loadFont(_: ?[*:0]const u8, _: ?*?[*:0]const u8) callconv(.c) ?*pd.LCDFont {
    return @ptrCast(&font_handle);
}
fn setFont(_: ?*pd.LCDFont) callconv(.c) void {}
fn getFrame() callconv(.c) [*c]u8 {
    return @ptrCast(&framebuffer.bytes);
}
fn getDisplayFrame() callconv(.c) [*c]u8 {
    return @ptrCast(&framebuffer.bytes);
}
fn markUpdatedRows(_: c_int, _: c_int) callconv(.c) void {}
fn display() callconv(.c) void {}
fn setRefreshRate(_: f32) callconv(.c) void {}

fn hydrateSaveStorage() void {
    var imported: [storage_module.max_bytes]u8 = undefined;
    const length = webStorageRead(&imported, imported.len);
    if (length < 0 or length > imported.len) return;
    _ = save_storage.load(imported[0..@intCast(length)]);
}
fn stat(_: ?[*:0]const u8, out: ?*pd.FileStat) callconv(.c) c_int {
    if (!save_storage.exists) return -1;
    if (out) |file_stat| file_stat.* = .{
        .isdir = 0,
        .size = @intCast(save_storage.len),
        .m_year = 0,
        .m_month = 0,
        .m_day = 0,
        .m_hour = 0,
        .m_minute = 0,
        .m_second = 0,
    };
    return 0;
}
fn unlink(_: ?[*:0]const u8, _: c_int) callconv(.c) c_int {
    if (webStorageClear() != 0) return -1;
    save_storage.clear();
    return 0;
}
fn open(_: ?[*:0]const u8, mode: pd.FileOptions) callconv(.c) ?*pd.SDFile {
    const storage_mode: storage_module.Mode = if (mode == pd.FILE_READ_DATA)
        .read
    else if (mode == pd.FILE_WRITE)
        .write
    else
        return null;
    if (!save_storage.open(storage_mode)) return null;
    return @ptrCast(&file_handle);
}
fn close(_: ?*pd.SDFile) callconv(.c) c_int {
    save_storage.close();
    return 0;
}
fn read(_: ?*pd.SDFile, buffer: ?*anyopaque, len: c_uint) callconv(.c) c_int {
    const output: [*]u8 = @ptrCast(buffer orelse return -1);
    return @intCast(save_storage.read(output[0..len]));
}
fn write(_: ?*pd.SDFile, buffer: ?*const anyopaque, len: c_uint) callconv(.c) c_int {
    const input: [*]const u8 = @ptrCast(buffer orelse return -1);
    return @intCast(save_storage.write(input[0..len]));
}
fn flush(_: ?*pd.SDFile) callconv(.c) c_int {
    const bytes = save_storage.contents();
    if (webStorageWrite(bytes.ptr, bytes.len) != 0) return -1;
    save_storage.commit();
    return 0;
}

fn getDefaultChannel() callconv(.c) ?*pd.SoundChannel {
    return @ptrCast(&channel_handle);
}
fn addSource(_: ?*pd.SoundChannel, _: ?*pd.SoundSource) callconv(.c) c_int {
    return 1;
}
fn removeSource(_: ?*pd.SoundChannel, _: ?*pd.SoundSource) callconv(.c) c_int {
    return 1;
}
fn newSynth() callconv(.c) ?*pd.PDSynth {
    return @ptrCast(&synth_handle);
}
fn freeSynth(_: ?*pd.PDSynth) callconv(.c) void {}
fn setWaveform(_: ?*pd.PDSynth, waveform: pd.SoundWaveform) callconv(.c) void {
    synth_waveform = waveform;
}
fn setAttackTime(_: ?*pd.PDSynth, attack: f32) callconv(.c) void {
    synth_attack = attack;
}
fn setDecayTime(_: ?*pd.PDSynth, decay: f32) callconv(.c) void {
    synth_decay = decay;
}
fn setSustainLevel(_: ?*pd.PDSynth, sustain: f32) callconv(.c) void {
    synth_sustain = sustain;
}
fn setReleaseTime(_: ?*pd.PDSynth, release: f32) callconv(.c) void {
    synth_release = release;
}
fn setSynthVolume(_: ?*pd.PDSynth, left: f32, right: f32) callconv(.c) void {
    synth_volume = (left + right) * 0.5;
}
fn getEnvelope(_: ?*pd.PDSynth) callconv(.c) ?*pd.PDSynthEnvelope {
    return @ptrCast(&envelope_handle);
}
fn setFrequencyModulator(_: ?*pd.PDSynth, modulator: ?*pd.PDSynthSignalValue) callconv(.c) void {
    frequency_lfo = if (modulator == null) .{} else lfo_state;
}
fn setAmplitudeModulator(_: ?*pd.PDSynth, modulator: ?*pd.PDSynthSignalValue) callconv(.c) void {
    amplitude_lfo = if (modulator == null) .{} else lfo_state;
}
fn playMIDINote(_: ?*pd.PDSynth, note: pd.MIDINote, velocity: f32, duration: f32, _: u32) callconv(.c) void {
    webAudioPlayNote(
        @intCast(@intFromEnum(synth_waveform)),
        note,
        velocity,
        duration,
        synth_attack,
        synth_decay,
        synth_sustain,
        synth_release,
        synth_volume,
        frequency_lfo.waveform,
        frequency_lfo.rate,
        frequency_lfo.center,
        frequency_lfo.depth,
        frequency_lfo.holdoff,
        frequency_lfo.ramp,
        frequency_lfo.phase,
        frequency_lfo.retrigger,
        amplitude_lfo.waveform,
        amplitude_lfo.rate,
        amplitude_lfo.center,
        amplitude_lfo.depth,
        amplitude_lfo.holdoff,
        amplitude_lfo.ramp,
        amplitude_lfo.phase,
        amplitude_lfo.retrigger,
    );
}
fn stopSynth(_: ?*pd.PDSynth) callconv(.c) void {
    webAudioStopSynth();
}
fn newLFO(_: pd.LFOType) callconv(.c) ?*pd.PDSynthLFO {
    return @ptrCast(&lfo_handle);
}
fn freeLFO(_: ?*pd.PDSynthLFO) callconv(.c) void {}
fn setLFOType(_: ?*pd.PDSynthLFO, kind: pd.LFOType) callconv(.c) void {
    lfo_state.waveform = @intCast(@intFromEnum(kind));
}
fn setLFORate(_: ?*pd.PDSynthLFO, rate: f32) callconv(.c) void {
    lfo_state.rate = rate;
}
fn setLFOCenter(_: ?*pd.PDSynthLFO, center: f32) callconv(.c) void {
    lfo_state.center = center;
}
fn setLFODepth(_: ?*pd.PDSynthLFO, depth: f32) callconv(.c) void {
    lfo_state.depth = depth;
}
fn setLFODelay(_: ?*pd.PDSynthLFO, holdoff: f32, ramp: f32) callconv(.c) void {
    lfo_state.holdoff = holdoff;
    lfo_state.ramp = ramp;
}
fn setLFOStartPhase(_: ?*pd.PDSynthLFO, phase: f32) callconv(.c) void {
    lfo_state.phase = phase;
}
fn setLFORetrigger(_: ?*pd.PDSynthLFO, retrigger: c_int) callconv(.c) void {
    lfo_state.retrigger = retrigger;
}
fn setEnvelopeCurvature(_: ?*pd.PDSynthEnvelope, _: f32) callconv(.c) void {}
fn setEnvelopeVelocitySensitivity(_: ?*pd.PDSynthEnvelope, _: f32) callconv(.c) void {}
fn setEnvelopeLegato(_: ?*pd.PDSynthEnvelope, _: c_int) callconv(.c) void {}
fn setEnvelopeRetrigger(_: ?*pd.PDSynthEnvelope, _: c_int) callconv(.c) void {}
fn setEnvelopeRateScaling(_: ?*pd.PDSynthEnvelope, _: f32, _: pd.MIDINote, _: pd.MIDINote) callconv(.c) void {}
fn newSequence() callconv(.c) ?*pd.SoundSequence {
    webAudioResetSequence();
    return @ptrCast(&sequence_handle);
}
fn freeSequence(_: ?*pd.SoundSequence) callconv(.c) void {}
fn addTrack(_: ?*pd.SoundSequence) callconv(.c) ?*pd.SequenceTrack {
    if (track_count == max_sequence_tracks) return null;
    const track = &track_records[track_count];
    track.* = .{ .index = @intCast(track_count), .signal = .{ .track_index = @intCast(track_count) } };
    track_count += 1;
    return @ptrCast(track);
}
fn setTempo(_: ?*pd.SoundSequence, steps_per_second: f32) callconv(.c) void {
    webAudioSetSequenceTempo(steps_per_second);
}
fn setLoops(_: ?*pd.SoundSequence, loop_start: c_int, loop_end: c_int, loops: c_int) callconv(.c) void {
    webAudioSetSequenceLoops(loop_start, loop_end, loops);
}
fn playSequence(_: ?*pd.SoundSequence, _: pd.SequenceFinishedCallback, _: ?*anyopaque) callconv(.c) void {
    webAudioStartSequence();
}
fn stopSequence(_: ?*pd.SoundSequence) callconv(.c) void {
    webAudioStopSequence();
}
fn instrumentRecord(instrument: ?*pd.PDSynthInstrument) ?*InstrumentRecord {
    return @ptrCast(@alignCast(instrument orelse return null));
}
fn trackRecord(track: ?*pd.SequenceTrack) ?*TrackRecord {
    return @ptrCast(@alignCast(track orelse return null));
}
fn setInstrument(track: ?*pd.SequenceTrack, instrument: ?*pd.PDSynthInstrument) callconv(.c) void {
    const target = trackRecord(track) orelse return;
    target.instrument = instrumentRecord(instrument);
}
fn addNoteEvent(track: ?*pd.SequenceTrack, step: u32, length: u32, note: pd.MIDINote, velocity: f32) callconv(.c) void {
    const instrument = (trackRecord(track) orelse return).instrument orelse return;
    for (instrument.voices[0..instrument.voice_count]) |voice| {
        if (note < voice.first_note or note > voice.last_note) continue;
        webAudioQueueSequenceNote(
            voice.waveform,
            note,
            velocity,
            step,
            length,
            voice.attack,
            voice.decay,
            voice.sustain,
            voice.release,
            voice.volume * instrument.volume,
            voice.frequency_lfo.waveform,
            voice.frequency_lfo.rate,
            voice.frequency_lfo.center,
            voice.frequency_lfo.depth,
            voice.frequency_lfo.holdoff,
            voice.frequency_lfo.ramp,
            voice.frequency_lfo.phase,
            voice.frequency_lfo.retrigger,
            voice.amplitude_lfo.waveform,
            voice.amplitude_lfo.rate,
            voice.amplitude_lfo.center,
            voice.amplitude_lfo.depth,
            voice.amplitude_lfo.holdoff,
            voice.amplitude_lfo.ramp,
            voice.amplitude_lfo.phase,
            voice.amplitude_lfo.retrigger,
            (trackRecord(track) orelse return).index,
        );
        return;
    }
}
fn getSignalForController(track: ?*pd.SequenceTrack, _: c_int, _: c_int) callconv(.c) ?*pd.ControlSignal {
    const target = trackRecord(track) orelse return null;
    return @ptrCast(&target.signal);
}
fn addControlEvent(signal: ?*pd.ControlSignal, step: c_int, value: f32, interpolate: c_int) callconv(.c) void {
    const record: *ControlSignalRecord = @ptrCast(@alignCast(signal orelse return));
    webAudioQueueSequenceControlPoint(record.track_index, step, value, interpolate);
}
fn newInstrument() callconv(.c) ?*pd.PDSynthInstrument {
    if (instrument_count == max_music_instruments) return null;
    const instrument = &instrument_records[instrument_count];
    instrument.* = .{};
    instrument_count += 1;
    return @ptrCast(instrument);
}
fn freeInstrument(_: ?*pd.PDSynthInstrument) callconv(.c) void {}
fn addVoice(instrument: ?*pd.PDSynthInstrument, _: ?*pd.PDSynth, first_note: pd.MIDINote, last_note: pd.MIDINote, _: f32) callconv(.c) c_int {
    const target = instrumentRecord(instrument) orelse return 0;
    if (target.voice_count == max_instrument_voices) return 0;
    target.voices[target.voice_count] = .{
        .first_note = first_note,
        .last_note = last_note,
        .waveform = @intCast(@intFromEnum(synth_waveform)),
        .attack = synth_attack,
        .decay = synth_decay,
        .sustain = synth_sustain,
        .release = synth_release,
        .volume = synth_volume,
        .frequency_lfo = frequency_lfo,
        .amplitude_lfo = amplitude_lfo,
    };
    target.voice_count += 1;
    return 1;
}
fn setInstrumentVolume(instrument: ?*pd.PDSynthInstrument, left: f32, right: f32) callconv(.c) void {
    const target = instrumentRecord(instrument) orelse return;
    target.volume = (left + right) * 0.5;
}
