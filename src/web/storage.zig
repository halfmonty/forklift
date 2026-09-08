const std = @import("std");

pub const max_bytes = 64;
pub const Mode = enum { read, write };

pub const Storage = struct {
    bytes: [max_bytes]u8 = undefined,
    len: usize = 0,
    exists: bool = false,
    mode: ?Mode = null,
    cursor: usize = 0,

    pub fn load(self: *Storage, bytes: []const u8) bool {
        if (bytes.len > max_bytes) return false;
        @memcpy(self.bytes[0..bytes.len], bytes);
        self.len = bytes.len;
        self.exists = true;
        self.mode = null;
        self.cursor = 0;
        return true;
    }

    pub fn open(self: *Storage, mode: Mode) bool {
        if (mode == .read and !self.exists) return false;
        if (mode == .write) {
            self.len = 0;
            self.exists = false;
        }
        self.mode = mode;
        self.cursor = 0;
        return true;
    }

    pub fn read(self: *Storage, output: []u8) usize {
        if (self.mode != .read) return 0;
        const count = @min(output.len, self.len - self.cursor);
        @memcpy(output[0..count], self.bytes[self.cursor .. self.cursor + count]);
        self.cursor += count;
        return count;
    }

    pub fn write(self: *Storage, input: []const u8) usize {
        if (self.mode != .write) return 0;
        const count = @min(input.len, max_bytes - self.cursor);
        @memcpy(self.bytes[self.cursor .. self.cursor + count], input[0..count]);
        self.cursor += count;
        self.len = @max(self.len, self.cursor);
        return count;
    }

    pub fn close(self: *Storage) void {
        self.mode = null;
        self.cursor = 0;
    }

    pub fn contents(self: *const Storage) []const u8 {
        return self.bytes[0..self.len];
    }

    pub fn commit(self: *Storage) void {
        self.exists = true;
    }

    pub fn clear(self: *Storage) void {
        self.len = 0;
        self.exists = false;
        self.mode = null;
        self.cursor = 0;
    }
};

test "a loaded save can be read without changing its bytes" {
    var storage = Storage{};
    const saved = [_]u8{ 'F', 'C', 'P', 'S', 1, 4, 4, 0 };
    try std.testing.expect(storage.load(&saved));
    try std.testing.expect(storage.open(.read));

    var output: [saved.len]u8 = undefined;
    try std.testing.expectEqual(saved.len, storage.read(&output));
    try std.testing.expectEqualSlices(u8, &saved, &output);
}

test "writes are bounded and only become visible after commit" {
    var storage = Storage{};
    try std.testing.expect(storage.open(.write));

    const input = [_]u8{ 1, 2, 3 };
    try std.testing.expectEqual(input.len, storage.write(&input));
    try std.testing.expect(!storage.exists);
    storage.commit();
    try std.testing.expect(storage.exists);
    try std.testing.expectEqualSlices(u8, &input, storage.contents());
}

test "oversized host storage is rejected without creating a save" {
    var storage = Storage{};
    const oversized = [_]u8{0} ** (max_bytes + 1);

    try std.testing.expect(!storage.load(&oversized));
    try std.testing.expect(!storage.exists);
}
