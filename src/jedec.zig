const std = @import("std");

pub fn JedecData(comptime w: u32, comptime h: u32) type {
    return struct {
        const Self = @This();
        pub const width = w;
        pub const rows = h;
        pub const len = w * h;

        raw: std.StaticBitSet(len),

        pub fn initEmpty() Self {
            return .{
                .raw = std.StaticBitSet(len).initEmpty(),
            };
        }
        pub fn initFull() Self {
            return .{
                .raw = std.StaticBitSet(len).initFull(),
            };
        }

        pub fn init(str: []u8) !Self {
            var self = .{
                .raw = std.StaticBitSet(len).initEmpty(),
            };

            // TODO parse header fields?

            const start = 8 + (std.mem.indexOf(u8, str, "\nL00000") orelse return error.MalformedJedecFile);
            const end = start + (std.mem.indexOf(u8, str[start..], "*") orelse return error.MalformedJedecFile);

            var i: usize = 0;
            for (str[start..end]) |c| {
                switch (c) {
                    '0' => i += 1,
                    '1' => {
                        self.raw.set(i);
                        i += 1;
                    },
                    else => {}
                }
            }

            std.debug.assert(i == len);

            return self;
        }

        pub fn getRow(fuse: u32) u32 {
            return @intCast(u32, fuse / Self.width);
        }

        pub fn getColumn(fuse: u32) u32 {
            return @intCast(u32, fuse - getRow(fuse) * Self.width);
        }

        pub fn get(self: Self, row: u32, col: u32) u1 {
            return switch (self.raw.isSet(row * Self.width + col)) {
                true => 1,
                false => 0,
            };
        }

        pub fn set(self: *Self, row: u32, col: u32, val: u1) void {
            self.raw.setValue(row * Self.width + col, val == 1);
        }

        pub fn diff(self: Self, other: Self) Self {
            var result = self;
            result.raw.toggleSet(other.raw);
            return result;
        }

        pub fn writeHex(self: *Self, writer: anytype) !void {
            var r: u32 = 0;
            while (r < Self.rows) : (r += 1) {
                var c: u32 = 0;
                while (c < Self.width - 3) : (c += 4) {
                    const v: u4 = self.get(r, Self.width - c - 1)
                            + self.get(r, Self.width - c - 2) * @as(u4, 2)
                            + self.get(r, Self.width - c - 3) * @as(u4, 4)
                            + self.get(r, Self.width - c - 4) * @as(u4, 8);
                    const base: u8 = if (v > 9) 'A' - 0xA else '0';
                    _ = try writer.writeByte(base + v);
                }

                std.debug.assert(c == Self.width);
                _ = try writer.writeByte('\n');
            }
        }
    };
}

