const std = @import("std");

pub const schema_version: u16 = 1;

/// These limits bound editor/WASM input and generated native draw data.
/// Raise one only alongside a fixture that demonstrates the need.
pub const Limits = struct {
    pub const max_commands: u16 = 64;
    pub const max_variants: u8 = 8;
    pub const max_parameters: u8 = 8;
    pub const max_command_buffer_bytes: usize = 1024;
};

pub const Kind = enum(u8) {
    world_render,
    screen_graphic,
};

pub const RenderPass = enum(u8) {
    warehouse_before,
    warehouse_after,
    dynamic,
    hud,
};

/// The serialized draw vocabulary. Convenience editor shapes must lower to
/// these primitives before they enter the normalized command stream.
pub const Primitive = enum(u8) {
    world_line,
    world_polygon,
    screen_line,
    screen_polygon,
    text,
};

pub const ParameterType = enum(u8) {
    bool,
    integer,
    f32,
    named_enum,
    vec2,
    rect,
    text,
};

/// This seed catalog is intentionally tiny. Slice 1 moves it behind the
/// shared pattern catalog and grows it through reviewed additions.
pub const PatternName = enum(u8) {
    checker_50,
};

pub const Style = union(enum) {
    black,
    white,
    clear,
    pattern: PatternName,
};

pub const Error = error{
    UnsupportedSchemaVersion,
    InvalidRenderPass,
    TooManyCommands,
    TooManyVariants,
    TooManyParameters,
    CommandBufferCapacityExceeded,
};

/// Metadata needed to reject an invalid authoring document before parsing or
/// rendering its commands. JSON decoding and command payloads arrive later.
pub const Document = struct {
    schema: u16 = schema_version,
    kind: Kind,
    render_pass: RenderPass,
    command_count: u16 = 0,
    variant_count: u8 = 0,
    parameter_count: u8 = 0,

    pub fn validate(self: Document) Error!void {
        if (self.schema != schema_version) return error.UnsupportedSchemaVersion;
        if (!passAllowedForKind(self.kind, self.render_pass)) return error.InvalidRenderPass;
        if (self.command_count > Limits.max_commands) return error.TooManyCommands;
        if (self.variant_count > Limits.max_variants) return error.TooManyVariants;
        if (self.parameter_count > Limits.max_parameters) return error.TooManyParameters;
    }
};

/// A normalized editor-to-WASM command stream. Commands are opaque until the
/// renderer protocol is introduced; this type owns its capacity contract now.
pub const CommandBuffer = struct {
    bytes: [Limits.max_command_buffer_bytes]u8 = undefined,
    len: usize = 0,

    pub fn append(self: *CommandBuffer, encoded_command: []const u8) Error!void {
        if (encoded_command.len > self.bytes.len - self.len) {
            return error.CommandBufferCapacityExceeded;
        }
        @memcpy(self.bytes[self.len..][0..encoded_command.len], encoded_command);
        self.len += encoded_command.len;
    }

    pub fn written(self: *const CommandBuffer) []const u8 {
        return self.bytes[0..self.len];
    }
};

fn passAllowedForKind(kind: Kind, render_pass: RenderPass) bool {
    return switch (kind) {
        .world_render => render_pass != .hud,
        .screen_graphic => render_pass == .hud,
    };
}

test "accepts a bounded world-render document in a warehouse pass" {
    const document = Document{
        .kind = .world_render,
        .render_pass = .warehouse_after,
        .command_count = Limits.max_commands,
        .variant_count = Limits.max_variants,
        .parameter_count = Limits.max_parameters,
    };

    try document.validate();
}

test "declares the initial primitive style and parameter vocabulary" {
    try std.testing.expectEqual(Primitive.world_polygon, .world_polygon);
    try std.testing.expectEqual(Style.clear, .clear);
    try std.testing.expectEqual(ParameterType.rect, .rect);
}

test "rejects an authoring document from an unsupported schema" {
    const document = Document{
        .schema = schema_version + 1,
        .kind = .screen_graphic,
        .render_pass = .hud,
    };

    try std.testing.expectError(error.UnsupportedSchemaVersion, document.validate());
}

test "rejects a screen graphic assigned to a warehouse pass" {
    const document = Document{
        .kind = .screen_graphic,
        .render_pass = .dynamic,
    };

    try std.testing.expectError(error.InvalidRenderPass, document.validate());
}

test "rejects a document that exceeds the command budget" {
    const document = Document{
        .kind = .world_render,
        .render_pass = .dynamic,
        .command_count = Limits.max_commands + 1,
    };

    try std.testing.expectError(error.TooManyCommands, document.validate());
}

test "rejects a document that exceeds the variant budget" {
    const document = Document{
        .kind = .world_render,
        .render_pass = .dynamic,
        .variant_count = Limits.max_variants + 1,
    };

    try std.testing.expectError(error.TooManyVariants, document.validate());
}

test "rejects a document that exceeds the parameter budget" {
    const document = Document{
        .kind = .screen_graphic,
        .render_pass = .hud,
        .parameter_count = Limits.max_parameters + 1,
    };

    try std.testing.expectError(error.TooManyParameters, document.validate());
}

test "command buffer preserves complete commands and rejects an overflowing append" {
    var buffer = CommandBuffer{};
    try buffer.append(&.{ 0x01, 0x02, 0x03 });
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x02, 0x03 }, buffer.written());

    const remaining = buffer.bytes.len - buffer.len;
    var oversized: [Limits.max_command_buffer_bytes]u8 = undefined;
    try std.testing.expectError(error.CommandBufferCapacityExceeded, buffer.append(oversized[0 .. remaining + 1]));
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x02, 0x03 }, buffer.written());
}
