const std = @import("std");

pub const width = 400;
pub const height = 240;
pub const row_stride = 52;
pub const byte_len = row_stride * height;

pub const Color = enum { black, white };

pub const Framebuffer = struct {
    bytes: [byte_len]u8 = [_]u8{0} ** byte_len,

    pub fn clear(self: *Framebuffer, color: Color) void {
        @memset(&self.bytes, if (color == .black) 0xff else 0x00);
    }

    pub fn setPixel(self: *Framebuffer, x: i32, y: i32, color: Color) void {
        if (x < 0 or x >= width or y < 0 or y >= height) return;
        const offset: usize = @intCast(y * row_stride + @divTrunc(x, 8));
        const mask: u8 = @as(u8, 0x80) >> @intCast(@mod(x, 8));
        if (color == .black) {
            self.bytes[offset] |= mask;
        } else {
            self.bytes[offset] &= ~mask;
        }
    }

    pub fn line(self: *Framebuffer, x0: i32, y0: i32, x1: i32, y1: i32, line_width: i32, color: Color) void {
        if (line_width <= 0) return;

        var x = x0;
        var y = y0;
        const dx: i32 = @intCast(@abs(x1 - x0));
        const sx: i32 = if (x0 < x1) 1 else -1;
        const dy: i32 = -@as(i32, @intCast(@abs(y1 - y0)));
        const sy: i32 = if (y0 < y1) 1 else -1;
        var error_term = dx + dy;
        const radius = @divTrunc(line_width - 1, 2);

        while (true) {
            self.fillRect(x - radius, y - radius, line_width, line_width, color);
            if (x == x1 and y == y1) break;
            const twice_error = 2 * error_term;
            if (twice_error >= dy) {
                error_term += dy;
                x += sx;
            }
            if (twice_error <= dx) {
                error_term += dx;
                y += sy;
            }
        }
    }

    pub fn drawRect(self: *Framebuffer, x: i32, y: i32, rect_width: i32, rect_height: i32, color: Color) void {
        if (rect_width <= 0 or rect_height <= 0) return;
        self.line(x, y, x + rect_width - 1, y, 1, color);
        self.line(x, y + rect_height - 1, x + rect_width - 1, y + rect_height - 1, 1, color);
        self.line(x, y, x, y + rect_height - 1, 1, color);
        self.line(x + rect_width - 1, y, x + rect_width - 1, y + rect_height - 1, 1, color);
    }

    pub fn fillRect(self: *Framebuffer, x: i32, y: i32, rect_width: i32, rect_height: i32, color: Color) void {
        if (rect_width <= 0 or rect_height <= 0) return;
        const x_start = @max(x, 0);
        const x_end = @min(x + rect_width, width);
        const y_start = @max(y, 0);
        const y_end = @min(y + rect_height, height);
        var pixel_y = y_start;
        while (pixel_y < y_end) : (pixel_y += 1) {
            var pixel_x = x_start;
            while (pixel_x < x_end) : (pixel_x += 1) self.setPixel(pixel_x, pixel_y, color);
        }
    }

    pub fn fillTriangle(self: *Framebuffer, x0: i32, y0: i32, x1: i32, y1: i32, x2: i32, y2: i32, color: Color) void {
        const x_min = @max(@min(x0, @min(x1, x2)), 0);
        const x_max = @min(@max(x0, @max(x1, x2)), width - 1);
        const y_min = @max(@min(y0, @min(y1, y2)), 0);
        const y_max = @min(@max(y0, @max(y1, y2)), height - 1);
        const area = edge(x0, y0, x1, y1, x2, y2);
        if (area == 0) return;

        var pixel_y = y_min;
        while (pixel_y <= y_max) : (pixel_y += 1) {
            var pixel_x = x_min;
            while (pixel_x <= x_max) : (pixel_x += 1) {
                const first = edge(x0, y0, x1, y1, pixel_x, pixel_y);
                const second = edge(x1, y1, x2, y2, pixel_x, pixel_y);
                const third = edge(x2, y2, x0, y0, pixel_x, pixel_y);
                if ((area > 0 and first >= 0 and second >= 0 and third >= 0) or
                    (area < 0 and first <= 0 and second <= 0 and third <= 0))
                {
                    self.setPixel(pixel_x, pixel_y, color);
                }
            }
        }
    }

    pub fn fillEllipse(self: *Framebuffer, x: i32, y: i32, ellipse_width: i32, ellipse_height: i32, color: Color) void {
        if (ellipse_width <= 0 or ellipse_height <= 0) return;
        const x_start = @max(x, 0);
        const x_end = @min(x + ellipse_width, width);
        const y_start = @max(y, 0);
        const y_end = @min(y + ellipse_height, height);
        const width_squared: i64 = @as(i64, ellipse_width) * ellipse_width;
        const height_squared: i64 = @as(i64, ellipse_height) * ellipse_height;
        const threshold = width_squared * height_squared;

        var pixel_y = y_start;
        while (pixel_y < y_end) : (pixel_y += 1) {
            const centered_y: i64 = 2 * @as(i64, pixel_y - y) + 1 - ellipse_height;
            var pixel_x = x_start;
            while (pixel_x < x_end) : (pixel_x += 1) {
                const centered_x: i64 = 2 * @as(i64, pixel_x - x) + 1 - ellipse_width;
                if (centered_x * centered_x * height_squared + centered_y * centered_y * width_squared <= threshold) {
                    self.setPixel(pixel_x, pixel_y, color);
                }
            }
        }
    }
};

fn edge(x0: i32, y0: i32, x1: i32, y1: i32, x: i32, y: i32) i64 {
    return @as(i64, x - x0) * (y1 - y0) - @as(i64, y - y0) * (x1 - x0);
}

test "a black pixel uses the most-significant bit of its row byte" {
    var framebuffer = Framebuffer{};
    framebuffer.clear(.white);
    framebuffer.setPixel(0, 0, .black);

    try std.testing.expectEqual(@as(u8, 0x80), framebuffer.bytes[0]);
}

test "a line includes both endpoints" {
    var framebuffer = Framebuffer{};
    framebuffer.clear(.white);
    framebuffer.line(1, 1, 3, 1, 1, .black);

    try std.testing.expectEqual(@as(u8, 0x70), framebuffer.bytes[row_stride]);
}

test "filled rectangles clip without writing row padding" {
    var framebuffer = Framebuffer{};
    framebuffer.clear(.white);
    framebuffer.fillRect(398, 0, 4, 1, .black);

    try std.testing.expectEqual(@as(u8, 0x03), framebuffer.bytes[49]);
    try std.testing.expectEqual(@as(u8, 0x00), framebuffer.bytes[50]);
    try std.testing.expectEqual(@as(u8, 0x00), framebuffer.bytes[51]);
}

test "filled triangle includes its edges" {
    var framebuffer = Framebuffer{};
    framebuffer.clear(.white);
    framebuffer.fillTriangle(1, 1, 3, 1, 1, 3, .black);

    try std.testing.expectEqual(@as(u8, 0x70), framebuffer.bytes[row_stride]);
    try std.testing.expectEqual(@as(u8, 0x60), framebuffer.bytes[row_stride * 2]);
    try std.testing.expectEqual(@as(u8, 0x40), framebuffer.bytes[row_stride * 3]);
}

test "filled ellipses exclude a five-by-five bounding-box corner" {
    var framebuffer = Framebuffer{};
    framebuffer.clear(.white);
    framebuffer.fillEllipse(0, 0, 5, 5, .black);

    try std.testing.expectEqual(@as(u8, 0x70), framebuffer.bytes[0]);
    try std.testing.expectEqual(@as(u8, 0xF8), framebuffer.bytes[row_stride * 2]);
}
