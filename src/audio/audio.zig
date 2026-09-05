const pd = @import("../playdate_api_definitions.zig");
const effect = @import("pdna_effect_adapter.zig");
const song = @import("pdna_song_adapter.zig");

pub const InitError = error{NoDefaultChannel} || effect.InitError || song.InitError;

pub const Audio = struct {
    effect_player: effect.EffectPlayer,
    song_player: song.SongPlayer,

    pub fn init(playdate: *pd.PlaydateAPI, music: *const song.SongPreset) InitError!Audio {
        const channel = playdate.sound.getDefaultChannel() orelse return error.NoDefaultChannel;
        var audio = Audio{
            .effect_player = try effect.EffectPlayer.init(playdate, channel),
            .song_player = undefined,
        };
        errdefer audio.effect_player.deinit();
        audio.song_player = try song.SongPlayer.init(playdate, channel, music);
        return audio;
    }

    pub fn play(self: *Audio, preset: effect.EffectPreset) void {
        self.effect_player.play(preset);
    }

    pub fn startMusic(self: *Audio) void {
        self.song_player.start();
    }

    pub fn deinit(self: *Audio) void {
        self.song_player.deinit();
        self.effect_player.deinit();
    }
};
