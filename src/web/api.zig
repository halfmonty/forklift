/// Browser-side definition of the Playdate API subset used by Forklift.
///
/// Keep signatures ABI-compatible with `playdate_api_definitions.zig`. This is
/// intentionally a subset: new game API usage must add its type and function
/// pointer here before it can target wasm.
pub const PDButtons = c_int;
pub const BUTTON_LEFT = 1 << 0;
pub const BUTTON_RIGHT = 1 << 1;
pub const BUTTON_UP = 1 << 2;
pub const BUTTON_DOWN = 1 << 3;
pub const BUTTON_B = 1 << 4;
pub const BUTTON_A = 1 << 5;

pub const PDSystemEvent = enum(c_int) {
    EventInit,
};
pub const PDCallbackFunction = *const fn (userdata: ?*anyopaque) callconv(.c) c_int;
pub const PDMenuItemCallbackFunction = *const fn (userdata: ?*anyopaque) callconv(.c) void;
pub const PDMenuItem = opaque {};

pub const PDStringEncoding = enum(c_int) {
    ASCIIEncoding,
    UTF8Encoding,
};

pub const LCDColor = usize;
pub const LCDSolidColor = enum(c_int) {
    ColorBlack,
    ColorWhite,
    ColorClear,
    ColorXOR,
};
pub const LCDFont = opaque {};

pub const FileOptions = c_int;
pub const FILE_READ_DATA = 1 << 1;
pub const FILE_WRITE = 1 << 2;
pub const SDFile = opaque {};
pub const FileStat = extern struct {
    isdir: c_int,
    size: c_uint,
    m_year: c_int,
    m_month: c_int,
    m_day: c_int,
    m_hour: c_int,
    m_minute: c_int,
    m_second: c_int,
};

pub const SoundChannel = opaque {};
pub const SoundSource = opaque {};
pub const PDSynth = SoundSource;
pub const PDSynthInstrument = SoundSource;
pub const PDSynthLFO = opaque {};
pub const PDSynthEnvelope = opaque {};
pub const SoundSequence = opaque {};
pub const SequenceTrack = opaque {};
pub const ControlSignal = opaque {};
pub const PDSynthSignalValue = opaque {};
pub const MIDINote = f32;
pub const SoundWaveform = enum(c_uint) {
    kWaveformSquare,
    kWaveformTriangle,
    kWaveformSine,
    kWaveformNoise,
    kWaveformSawtooth,
};
pub const LFOType = enum(c_uint) {
    kLFOTypeSquare,
    kLFOTypeTriangle,
    kLFOTypeSine,
    kLFOTypeSampleAndHold,
    kLFOTypeSawtoothUp,
    kLFOTypeSawtoothDown,
};
pub const SequenceFinishedCallback = *const fn (
    sequence: ?*SoundSequence,
    userdata: ?*anyopaque,
) callconv(.c) void;

pub const PlaydateAPI = extern struct {
    system: *const PlaydateSys,
    file: *const PlaydateFile,
    graphics: *const PlaydateGraphics,
    display: *const PlaydateDisplay,
    sound: *const PlaydateSound,
};

pub const PlaydateSys = extern struct {
    realloc: *const fn (ptr: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque,
    setUpdateCallback: *const fn (update: ?PDCallbackFunction, userdata: ?*anyopaque) callconv(.c) void,
    getButtonState: *const fn (current: ?*PDButtons, pushed: ?*PDButtons, released: ?*PDButtons) callconv(.c) void,
    getCrankChange: *const fn () callconv(.c) f32,
    getElapsedTime: *const fn () callconv(.c) f32,
    resetElapsedTime: *const fn () callconv(.c) void,
    drawFPS: *const fn (x: c_int, y: c_int) callconv(.c) void,
    addMenuItem: *const fn (title: ?[*:0]const u8, callback: ?PDMenuItemCallbackFunction, userdata: ?*anyopaque) callconv(.c) ?*PDMenuItem,
    addOptionsMenuItem: *const fn (title: ?[*:0]const u8, option_titles: [*c]?[*:0]const u8, options_count: c_int, callback: ?PDMenuItemCallbackFunction, userdata: ?*anyopaque) callconv(.c) ?*PDMenuItem,
    getMenuItemValue: *const fn (menu_item: ?*PDMenuItem) callconv(.c) c_int,
    setMenuItemValue: *const fn (menu_item: ?*PDMenuItem, value: c_int) callconv(.c) void,
    @"error": *const fn (fmt: ?[*:0]const u8, ...) callconv(.c) void,
};

pub const PlaydateGraphics = extern struct {
    clear: *const fn (color: LCDColor) callconv(.c) void,
    drawLine: *const fn (x1: c_int, y1: c_int, x2: c_int, y2: c_int, width: c_int, color: LCDColor) callconv(.c) void,
    fillTriangle: *const fn (x1: c_int, y1: c_int, x2: c_int, y2: c_int, x3: c_int, y3: c_int, color: LCDColor) callconv(.c) void,
    drawRect: *const fn (x: c_int, y: c_int, width: c_int, height: c_int, color: LCDColor) callconv(.c) void,
    fillRect: *const fn (x: c_int, y: c_int, width: c_int, height: c_int, color: LCDColor) callconv(.c) void,
    fillEllipse: *const fn (x: c_int, y: c_int, width: c_int, height: c_int, start_angle: f32, end_angle: f32, color: LCDColor) callconv(.c) void,
    drawText: *const fn (text: ?*const anyopaque, len: usize, encoding: PDStringEncoding, x: c_int, y: c_int) callconv(.c) c_int,
    loadFont: *const fn (path: ?[*:0]const u8, out_err: ?*?[*:0]const u8) callconv(.c) ?*LCDFont,
    setFont: *const fn (font: ?*LCDFont) callconv(.c) void,
    getFrame: *const fn () callconv(.c) [*c]u8,
    getDisplayFrame: *const fn () callconv(.c) [*c]u8,
    markUpdatedRows: *const fn (start: c_int, end: c_int) callconv(.c) void,
    display: *const fn () callconv(.c) void,
};

pub const PlaydateDisplay = extern struct {
    setRefreshRate: *const fn (rate: f32) callconv(.c) void,
};

pub const PlaydateFile = extern struct {
    stat: *const fn (path: ?[*:0]const u8, stat: ?*FileStat) callconv(.c) c_int,
    unlink: *const fn (name: ?[*:0]const u8, recursive: c_int) callconv(.c) c_int,
    open: *const fn (name: ?[*:0]const u8, mode: FileOptions) callconv(.c) ?*SDFile,
    close: *const fn (file: ?*SDFile) callconv(.c) c_int,
    read: *const fn (file: ?*SDFile, buffer: ?*anyopaque, len: c_uint) callconv(.c) c_int,
    write: *const fn (file: ?*SDFile, buffer: ?*const anyopaque, len: c_uint) callconv(.c) c_int,
    flush: *const fn (file: ?*SDFile) callconv(.c) c_int,
};

pub const PlaydateSound = extern struct {
    channel: *const PlaydateSoundChannel,
    synth: *const PlaydateSoundSynth,
    sequence: *const PlaydateSoundSequence,
    lfo: *const PlaydateSoundLFO,
    envelope: *const PlaydateSoundEnvelope,
    controlsignal: *const PlaydateControlSignal,
    track: *const PlaydateSoundTrack,
    instrument: *const PlaydateSoundInstrument,
    getDefaultChannel: *const fn () callconv(.c) ?*SoundChannel,
};

pub const PlaydateSoundChannel = extern struct {
    addSource: *const fn (channel: ?*SoundChannel, source: ?*SoundSource) callconv(.c) c_int,
    removeSource: *const fn (channel: ?*SoundChannel, source: ?*SoundSource) callconv(.c) c_int,
};
pub const PlaydateSoundSynth = extern struct {
    newSynth: *const fn () callconv(.c) ?*PDSynth,
    freeSynth: *const fn (synth: ?*PDSynth) callconv(.c) void,
    setWaveform: *const fn (synth: ?*PDSynth, wave: SoundWaveform) callconv(.c) void,
    setAttackTime: *const fn (synth: ?*PDSynth, attack: f32) callconv(.c) void,
    setDecayTime: *const fn (synth: ?*PDSynth, decay: f32) callconv(.c) void,
    setSustainLevel: *const fn (synth: ?*PDSynth, sustain: f32) callconv(.c) void,
    setReleaseTime: *const fn (synth: ?*PDSynth, release: f32) callconv(.c) void,
    setVolume: *const fn (synth: ?*PDSynth, left: f32, right: f32) callconv(.c) void,
    getEnvelope: *const fn (synth: ?*PDSynth) callconv(.c) ?*PDSynthEnvelope,
    setFrequencyModulator: *const fn (synth: ?*PDSynth, mod: ?*PDSynthSignalValue) callconv(.c) void,
    setAmplitudeModulator: *const fn (synth: ?*PDSynth, mod: ?*PDSynthSignalValue) callconv(.c) void,
    playMIDINote: *const fn (synth: ?*PDSynth, note: MIDINote, velocity: f32, length: f32, when: u32) callconv(.c) void,
    stop: *const fn (synth: ?*PDSynth) callconv(.c) void,
};
pub const PlaydateSoundLFO = extern struct {
    newLFO: *const fn (kind: LFOType) callconv(.c) ?*PDSynthLFO,
    freeLFO: *const fn (lfo: ?*PDSynthLFO) callconv(.c) void,
    setType: *const fn (lfo: ?*PDSynthLFO, kind: LFOType) callconv(.c) void,
    setRate: *const fn (lfo: ?*PDSynthLFO, rate: f32) callconv(.c) void,
    setCenter: *const fn (lfo: ?*PDSynthLFO, center: f32) callconv(.c) void,
    setDepth: *const fn (lfo: ?*PDSynthLFO, depth: f32) callconv(.c) void,
    setDelay: *const fn (lfo: ?*PDSynthLFO, holdoff: f32, ramp_time: f32) callconv(.c) void,
    setStartPhase: *const fn (lfo: ?*PDSynthLFO, phase: f32) callconv(.c) void,
    setRetrigger: *const fn (lfo: ?*PDSynthLFO, flag: c_int) callconv(.c) void,
};
pub const PlaydateSoundEnvelope = extern struct {
    setCurvature: *const fn (envelope: ?*PDSynthEnvelope, amount: f32) callconv(.c) void,
    setVelocitySensitivity: *const fn (envelope: ?*PDSynthEnvelope, sensitivity: f32) callconv(.c) void,
    setLegato: *const fn (envelope: ?*PDSynthEnvelope, flag: c_int) callconv(.c) void,
    setRetrigger: *const fn (envelope: ?*PDSynthEnvelope, flag: c_int) callconv(.c) void,
    setRateScaling: *const fn (envelope: ?*PDSynthEnvelope, scaling: f32, start: MIDINote, end: MIDINote) callconv(.c) void,
};
pub const PlaydateSoundSequence = extern struct {
    newSequence: *const fn () callconv(.c) ?*SoundSequence,
    freeSequence: *const fn (sequence: ?*SoundSequence) callconv(.c) void,
    addTrack: *const fn (sequence: ?*SoundSequence) callconv(.c) ?*SequenceTrack,
    setTempo: *const fn (sequence: ?*SoundSequence, steps_per_second: f32) callconv(.c) void,
    setLoops: *const fn (sequence: ?*SoundSequence, loop_start: c_int, loop_end: c_int, loops: c_int) callconv(.c) void,
    play: *const fn (sequence: ?*SoundSequence, callback: SequenceFinishedCallback, userdata: ?*anyopaque) callconv(.c) void,
    stop: *const fn (sequence: ?*SoundSequence) callconv(.c) void,
};
pub const PlaydateSoundTrack = extern struct {
    setInstrument: *const fn (track: ?*SequenceTrack, instrument: ?*PDSynthInstrument) callconv(.c) void,
    addNoteEvent: *const fn (track: ?*SequenceTrack, step: u32, length: u32, note: MIDINote, velocity: f32) callconv(.c) void,
    getSignalForController: *const fn (track: ?*SequenceTrack, controller: c_int, create: c_int) callconv(.c) ?*ControlSignal,
};
pub const PlaydateControlSignal = extern struct {
    addEvent: *const fn (signal: ?*ControlSignal, step: c_int, value: f32, interpolate: c_int) callconv(.c) void,
};
pub const PlaydateSoundInstrument = extern struct {
    newInstrument: *const fn () callconv(.c) ?*PDSynthInstrument,
    freeInstrument: *const fn (instrument: ?*PDSynthInstrument) callconv(.c) void,
    addVoice: *const fn (instrument: ?*PDSynthInstrument, synth: ?*PDSynth, range_start: MIDINote, range_end: MIDINote, transpose: f32) callconv(.c) c_int,
    setVolume: *const fn (instrument: ?*PDSynthInstrument, left: f32, right: f32) callconv(.c) void,
};
