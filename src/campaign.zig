const jobs = @import("jobs.zig");
const scoring = @import("scoring.zig");

pub const FlowState = enum {
    title,
    briefing,
    playing_shift,
    shift_results,
};

pub const StageId = enum {
    training_facility,
    stress_test,
};

pub const ShiftId = enum {
    training_orientation,
    stress_test,
};

pub const BossBriefing = struct {
    pages: []const []const u8,
};

pub const ShiftDefinition = struct {
    id: ShiftId,
    title: []const u8,
    jobs: []const jobs.JobDefinition,
    opening_briefing: BossBriefing,
    scoring: scoring.ShiftScoring,
};

pub const StageDefinition = struct {
    id: StageId,
    title: []const u8,
    shifts: []const ShiftDefinition,
};

pub const CampaignDefinition = struct {
    stages: []const StageDefinition,
};
