pub const ShiftScoring = struct {
    completion_points: u32,
    target_time_seconds: f32,
    time_bonus_per_second: u32,
    collision_penalty: u32,
};

pub const ShiftResult = struct {
    elapsed_seconds: f32,
    completed_jobs: usize,
    collision_impacts: u32,
    time_bonus: u32,
    points: u32,
};

pub fn calculate(
    scoring: ShiftScoring,
    elapsed_seconds: f32,
    completed_jobs: usize,
    collision_impacts: u32,
) ShiftResult {
    const remaining_seconds = @max(0.0, scoring.target_time_seconds - elapsed_seconds);
    const time_bonus: u32 = @intFromFloat(
        @floor(remaining_seconds * @as(f32, @floatFromInt(scoring.time_bonus_per_second))),
    );
    const penalty = collision_impacts * scoring.collision_penalty;
    const subtotal = scoring.completion_points + time_bonus;

    return .{
        .elapsed_seconds = elapsed_seconds,
        .completed_jobs = completed_jobs,
        .collision_impacts = collision_impacts,
        .time_bonus = time_bonus,
        .points = if (penalty >= subtotal) 0 else subtotal - penalty,
    };
}
