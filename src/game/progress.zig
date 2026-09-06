const std = @import("std");
const campaign = @import("campaign.zig");

pub const save_version: u8 = 1;
pub const encoded_size = 8;
const magic = "FCPS";

pub const Progress = struct {
    next_unfinished_stage_id: campaign.StageId,
    next_unfinished_shift_id: campaign.ShiftId,
    campaign_complete: bool,

    pub fn initial() Progress {
        return .{
            .next_unfinished_stage_id = .training_facility,
            .next_unfinished_shift_id = .training_orientation,
            .campaign_complete = false,
        };
    }
};

pub const DecodeError = error{
    InvalidLength,
    InvalidMagic,
    UnsupportedVersion,
    InvalidStageId,
    InvalidShiftId,
    InvalidCompletionFlag,
};

pub fn encode(progress: Progress) [encoded_size]u8 {
    return .{
        magic[0],
        magic[1],
        magic[2],
        magic[3],
        save_version,
        @intFromEnum(progress.next_unfinished_stage_id),
        @intFromEnum(progress.next_unfinished_shift_id),
        if (progress.campaign_complete) 1 else 0,
    };
}

fn stageIdFromByte(value: u8) ?campaign.StageId {
    return switch (value) {
        1 => .training_facility,
        2 => .stress_test,
        3 => .first_warehouse,
        else => null,
    };
}

fn shiftIdFromByte(value: u8) ?campaign.ShiftId {
    return switch (value) {
        1 => .training_orientation,
        2 => .stress_test,
        3 => .first_delivery,
        else => null,
    };
}

pub fn decode(bytes: []const u8) DecodeError!Progress {
    if (bytes.len != encoded_size) return error.InvalidLength;
    if (!std.mem.eql(u8, bytes[0..4], magic)) return error.InvalidMagic;
    if (bytes[4] != save_version) return error.UnsupportedVersion;

    const stage_id = stageIdFromByte(bytes[5]) orelse return error.InvalidStageId;
    const shift_id = shiftIdFromByte(bytes[6]) orelse return error.InvalidShiftId;
    const campaign_complete = switch (bytes[7]) {
        0 => false,
        1 => true,
        else => return error.InvalidCompletionFlag,
    };

    return .{
        .next_unfinished_stage_id = stage_id,
        .next_unfinished_shift_id = shift_id,
        .campaign_complete = campaign_complete,
    };
}

pub fn locationFor(
    definition: campaign.CampaignDefinition,
    progress: Progress,
) ?campaign.ShiftLocation {
    if (progress.campaign_complete) return null;

    for (definition.stages, 0..) |stage, stage_index| {
        if (stage.id != progress.next_unfinished_stage_id) continue;

        for (stage.shifts, 0..) |shift, shift_index| {
            if (shift.id == progress.next_unfinished_shift_id) {
                return .{
                    .stage_index = stage_index,
                    .shift_index = shift_index,
                };
            }
        }
    }
    return null;
}

test "encode and decode preserve every progress field" {
    const progress = Progress{
        .next_unfinished_stage_id = .stress_test,
        .next_unfinished_shift_id = .training_orientation,
        .campaign_complete = true,
    };

    const decoded = try decode(&encode(progress));
    try std.testing.expectEqual(progress.next_unfinished_stage_id, decoded.next_unfinished_stage_id);
    try std.testing.expectEqual(progress.next_unfinished_shift_id, decoded.next_unfinished_shift_id);
    try std.testing.expectEqual(progress.campaign_complete, decoded.campaign_complete);
}

test "decode rejects corrupted magic and completion flags" {
    var bad_magic = encode(Progress.initial());
    bad_magic[0] = 'X';
    try std.testing.expectError(error.InvalidMagic, decode(&bad_magic));

    var bad_completion_flag = encode(Progress.initial());
    bad_completion_flag[7] = 2;
    try std.testing.expectError(error.InvalidCompletionFlag, decode(&bad_completion_flag));
}

test "locationFor resolves the first active campaign shift" {
    const stages = @import("../content/stages.zig");
    const location = locationFor(stages.active_campaign, Progress.initial()) orelse return error.TestExpectedEqual;

    try std.testing.expectEqual(@as(usize, 0), location.stage_index);
    try std.testing.expectEqual(@as(usize, 0), location.shift_index);
}

test "locationFor has no location after campaign completion" {
    const stages = @import("../content/stages.zig");
    const complete = Progress{
        .next_unfinished_stage_id = .training_facility,
        .next_unfinished_shift_id = .training_orientation,
        .campaign_complete = true,
    };

    try std.testing.expect(locationFor(stages.active_campaign, complete) == null);
}
