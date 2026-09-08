const pdapi = @import("../platform_api.zig");
const campaign = @import("campaign.zig");
const progress = @import("progress.zig");

const save_path = "campaign_progress.bin";

pub const LoadResult = struct {
    progress: progress.Progress,
    exists: bool,
};

pub fn load(
    playdate: *pdapi.PlaydateAPI,
    definition: campaign.CampaignDefinition,
) LoadResult {
    var stat: pdapi.FileStat = undefined;
    if (playdate.file.stat(save_path, &stat) != 0) {
        return .{ .progress = progress.Progress.initial(), .exists = false };
    }
    if (stat.size != progress.encoded_size) {
        return .{ .progress = progress.Progress.initial(), .exists = false };
    }

    const file = playdate.file.open(save_path, pdapi.FILE_READ_DATA) orelse {
        return .{ .progress = progress.Progress.initial(), .exists = false };
    };
    defer _ = playdate.file.close(file);

    var bytes: [progress.encoded_size]u8 = undefined;
    const bytes_read = playdate.file.read(
        file,
        @ptrCast(&bytes),
        @intCast(bytes.len),
    );
    if (bytes_read != bytes.len) {
        return .{ .progress = progress.Progress.initial(), .exists = false };
    }

    const loaded = progress.decode(&bytes) catch {
        return .{ .progress = progress.Progress.initial(), .exists = false };
    };
    if (loaded.campaign_complete) {
        return .{ .progress = loaded, .exists = true };
    }

    return if (progress.locationFor(definition, loaded) != null)
        .{ .progress = loaded, .exists = true }
    else
        .{ .progress = progress.Progress.initial(), .exists = false };
}

pub fn save(
    playdate: *pdapi.PlaydateAPI,
    value: progress.Progress,
) bool {
    const file = playdate.file.open(save_path, pdapi.FILE_WRITE) orelse {
        return false;
    };
    defer _ = playdate.file.close(file);

    const bytes = progress.encode(value);
    const bytes_written = playdate.file.write(
        file,
        @ptrCast(&bytes),
        @intCast(bytes.len),
    );
    if (bytes_written != bytes.len) return false;
    return playdate.file.flush(file) == 0;
}

pub fn clear(playdate: *pdapi.PlaydateAPI) bool {
    return playdate.file.unlink(save_path, 0) == 0;
}
