const std = @import("std");
const jobs = @import("../sim/jobs.zig");
const scoring = @import("scoring.zig");

pub const FlowState = enum {
    title,
    briefing,
    playing_shift,
    shift_results,
    promotion,
    campaign_complete,
};

pub const StageId = enum(u8) {
    training_facility = 1,
    stress_test = 2,
    first_warehouse = 3,
    feature_test = 4,
};

pub const ShiftId = enum(u8) {
    training_orientation = 1,
    stress_test = 2,
    first_delivery = 3,
    feature_test = 4,
};

pub const BriefingTrigger = union(enum) {
    shift_start,
    before_job: usize,
};

pub const BossBriefing = struct {
    pages: []const []const u8,
};

pub const BossMessage = struct {
    trigger: BriefingTrigger,
    pages: []const []const u8,
};

pub const ShiftDefinition = struct {
    id: ShiftId,
    stage_id: StageId,
    title: []const u8,
    jobs: []const jobs.JobDefinition,
    briefings: []const BossMessage,
    scoring: scoring.ShiftScoring,
};

pub const StageDefinition = struct {
    id: StageId,
    title: []const u8,
    shifts: []const ShiftDefinition,
    promotion_pages: []const []const u8,
};

pub const CampaignDefinition = struct {
    stages: []const StageDefinition,
    campaign_complete_pages: []const []const u8,
};

pub const ShiftLocation = struct {
    stage_index: usize,
    shift_index: usize,
};

pub const CompletionRoute = union(enum) {
    next_shift: ShiftLocation,
    promotion,
    campaign_complete,
};

pub fn routeAfterCompletedShift(
    definition: CampaignDefinition,
    stage_index: usize,
    shift_index: usize,
) CompletionRoute {
    std.debug.assert(stage_index < definition.stages.len);
    const stage = definition.stages[stage_index];
    std.debug.assert(shift_index < stage.shifts.len);

    if (shift_index + 1 < stage.shifts.len) {
        return .{
            .next_shift = .{
                .stage_index = stage_index,
                .shift_index = shift_index + 1,
            },
        };
    }

    if (stage_index + 1 < definition.stages.len) {
        return .promotion;
    }

    return .campaign_complete;
}
