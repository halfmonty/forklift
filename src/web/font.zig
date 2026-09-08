const std = @import("std");
const framebuffer_module = @import("framebuffer.zig");

pub const glyph_width = 5;
pub const glyph_height = 7;
pub const line_height = 8;
pub const advance = 6;

/// Draws ASCII text into the shared one-bit framebuffer and returns the
/// horizontal advance from the starting x coordinate.
pub fn drawText(framebuffer: *framebuffer_module.Framebuffer, text: []const u8, x: i32, y: i32) c_int {
    var cursor_x = x;
    var cursor_y = y;
    var maximum_advance: i32 = 0;

    for (text) |character| {
        if (character == '\n') {
            maximum_advance = @max(maximum_advance, cursor_x - x);
            cursor_x = x;
            cursor_y += line_height;
            continue;
        }
        drawGlyph(framebuffer, glyphRows(character), cursor_x, cursor_y);
        cursor_x += advance;
    }
    return @max(maximum_advance, cursor_x - x);
}

fn drawGlyph(framebuffer: *framebuffer_module.Framebuffer, rows: [glyph_height]u8, x: i32, y: i32) void {
    for (rows, 0..) |row, row_index| {
        for (0..glyph_width) |column| {
            const shift: u3 = @intCast(glyph_width - 1 - column);
            if (row & (@as(u8, 1) << shift) != 0) {
                framebuffer.setPixel(x + @as(i32, @intCast(column)), y + @as(i32, @intCast(row_index)), .black);
            }
        }
    }
}

fn glyphRows(character: u8) [glyph_height]u8 {
    return switch (character) {
        'A', 'a' => .{ 0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001 },
        'B', 'b' => .{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110 },
        'C', 'c' => .{ 0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110 },
        'D', 'd' => .{ 0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110 },
        'E', 'e' => .{ 0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111 },
        'F', 'f' => .{ 0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000 },
        'G', 'g' => .{ 0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01110 },
        'H', 'h' => .{ 0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001 },
        'I', 'i' => .{ 0b01110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110 },
        'J', 'j' => .{ 0b00001, 0b00001, 0b00001, 0b00001, 0b10001, 0b10001, 0b01110 },
        'K', 'k' => .{ 0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001 },
        'L', 'l' => .{ 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111 },
        'M', 'm' => .{ 0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001 },
        'N', 'n' => .{ 0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001 },
        'O', 'o' => .{ 0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110 },
        'P', 'p' => .{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000 },
        'Q', 'q' => .{ 0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101 },
        'R', 'r' => .{ 0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001 },
        'S', 's' => .{ 0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110 },
        'T', 't' => .{ 0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100 },
        'U', 'u' => .{ 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110 },
        'V', 'v' => .{ 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100 },
        'W', 'w' => .{ 0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b10101, 0b01010 },
        'X', 'x' => .{ 0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001 },
        'Y', 'y' => .{ 0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100 },
        'Z', 'z' => .{ 0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111 },
        '0' => .{ 0b01110, 0b10011, 0b10101, 0b10101, 0b11001, 0b10001, 0b01110 },
        '1' => .{ 0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110 },
        '2' => .{ 0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111 },
        '3' => .{ 0b11110, 0b00001, 0b00001, 0b01110, 0b00001, 0b00001, 0b11110 },
        '4' => .{ 0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010 },
        '5' => .{ 0b11111, 0b10000, 0b10000, 0b11110, 0b00001, 0b00001, 0b11110 },
        '6' => .{ 0b01110, 0b10000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110 },
        '7' => .{ 0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000 },
        '8' => .{ 0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110 },
        '9' => .{ 0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00001, 0b01110 },
        ' ' => .{0} ** glyph_height,
        '.' => .{ 0, 0, 0, 0, 0, 0, 0b00100 },
        ',' => .{ 0, 0, 0, 0, 0, 0b00100, 0b01000 },
        ':' => .{ 0, 0b00100, 0, 0, 0b00100, 0, 0 },
        ';' => .{ 0, 0b00100, 0, 0, 0b00100, 0b01000, 0 },
        '-' => .{ 0, 0, 0, 0b11111, 0, 0, 0 },
        '_' => .{ 0, 0, 0, 0, 0, 0, 0b11111 },
        '/' => .{ 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0, 0 },
        '=' => .{ 0, 0b11111, 0, 0b11111, 0, 0, 0 },
        '>' => .{ 0b10000, 0b01000, 0b00100, 0b00010, 0b00100, 0b01000, 0b10000 },
        '<' => .{ 0b00001, 0b00010, 0b00100, 0b01000, 0b00100, 0b00010, 0b00001 },
        '!' => .{ 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0, 0b00100 },
        '?' => .{ 0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0, 0b00100 },
        '+' => .{ 0, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0 },
        else => .{ 0b11111, 0b10001, 0b10101, 0b10101, 0b10101, 0b10001, 0b11111 },
    };
}

test "drawText renders the A glyph in the requested position" {
    var framebuffer = framebuffer_module.Framebuffer{};
    framebuffer.clear(.white);
    const drawn_width = drawText(&framebuffer, "A", 10, 10);

    try std.testing.expectEqual(@as(c_int, advance), drawn_width);
    try std.testing.expectEqual(@as(u8, 0x1c), framebuffer.bytes[10 * framebuffer_module.row_stride + 1]);
}

test "drawText advances to the next line after a newline" {
    var framebuffer = framebuffer_module.Framebuffer{};
    framebuffer.clear(.white);
    const drawn_width = drawText(&framebuffer, "A\nA", 0, 0);

    try std.testing.expectEqual(@as(c_int, advance), drawn_width);
    try std.testing.expectEqual(@as(u8, 0x70), framebuffer.bytes[0]);
    try std.testing.expectEqual(@as(u8, 0x70), framebuffer.bytes[line_height * framebuffer_module.row_stride]);
}
