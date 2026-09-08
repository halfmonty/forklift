const builtin = @import("builtin");
const implementation = if (builtin.cpu.arch == .wasm32)
    @import("web/api.zig")
else
    @import("playdate_api_definitions.zig");

/// The game imports this facade rather than binding itself directly to either
/// runtime's API definition. Native targets retain the full Playdate API;
/// wasm targets receive only the compatibility surface Forklift currently uses.
pub const PlaydateAPI = implementation.PlaydateAPI;
pub const PlaydateGraphics = implementation.PlaydateGraphics;
pub const PDSystemEvent = implementation.PDSystemEvent;
pub const PDButtons = implementation.PDButtons;
pub const BUTTON_LEFT = implementation.BUTTON_LEFT;
pub const BUTTON_RIGHT = implementation.BUTTON_RIGHT;
pub const BUTTON_UP = implementation.BUTTON_UP;
pub const BUTTON_DOWN = implementation.BUTTON_DOWN;
pub const BUTTON_A = implementation.BUTTON_A;
pub const BUTTON_B = implementation.BUTTON_B;
pub const PDMenuItem = implementation.PDMenuItem;
pub const LCDColor = implementation.LCDColor;
pub const LCDSolidColor = implementation.LCDSolidColor;
pub const LCDFont = implementation.LCDFont;
pub const PDStringEncoding = implementation.PDStringEncoding;
pub const FileStat = implementation.FileStat;
pub const FILE_READ_DATA = implementation.FILE_READ_DATA;
pub const FILE_WRITE = implementation.FILE_WRITE;
pub const SoundChannel = implementation.SoundChannel;
pub const PDSynth = implementation.PDSynth;
pub const PDSynthLFO = implementation.PDSynthLFO;
pub const PDSynthInstrument = implementation.PDSynthInstrument;
pub const SoundSequence = implementation.SoundSequence;
pub const SequenceTrack = implementation.SequenceTrack;
pub const ControlSignal = implementation.ControlSignal;
pub const MIDINote = implementation.MIDINote;
pub const SoundWaveform = implementation.SoundWaveform;
pub const LFOType = implementation.LFOType;
