const std = @import("std");
const core = @import("core.zig");
const svf = @import("svf.zig");

const JedecCommand = enum {
    qty_pins,
    qty_fuses,
    note,
    security,
    default,
    location,
    hex,
    usercode,
    checksum,
};

const JedecField = struct {
    cmd: JedecCommand,
    extra: []const u8,
};

const JedecFieldIterator = struct {
    file_name: []const u8,
    remaining: []const u8,

    fn next(self: *JedecFieldIterator) !?JedecField {
        while (std.mem.indexOf(u8, self.remaining, "*")) |end| {
            const cmd = std.mem.trimLeft(u8, self.remaining[0..end], " \t\r\n");
            self.remaining = self.remaining[end + 1 ..];
            if (cmd.len == 0) {
                try std.io.getStdErr().writer().print("{s}: Ignoring empty field\n", .{ self.file_name });
            } else switch (cmd[0]) {
                'Q' => {
                    if (cmd.len >= 2) {
                        switch (cmd[1]) {
                            'F' => return JedecField { .cmd = .qty_fuses, .extra = cmd[2..] },
                            'P' => return JedecField { .cmd = .qty_pins, .extra = cmd[2..] },
                            else => {} // fall through
                        }
                    }
                    try std.io.getStdErr().writer().print("{s}: Ignoring unsupported field: {s}\n", .{ self.file_name, cmd });
                },
                'N' => return JedecField { .cmd = .note, .extra = cmd[1..] },
                'G' => return JedecField { .cmd = .security, .extra = cmd[1..] },
                'F' => return JedecField { .cmd = .default, .extra = cmd[1..] },
                'L' => return JedecField { .cmd = .location, .extra = cmd[1..] },
                'K' => return JedecField { .cmd = .hex, .extra = cmd[1..] },
                'U' => return JedecField { .cmd = .usercode, .extra = cmd[1..] },
                'C' => return JedecField { .cmd = .checksum, .extra = cmd[1..] },
                else => {
                    try std.io.getStdErr().writer().print("{s}: Ignoring unsupported field: {s}\n", .{ self.file_name, cmd });
                },
            }
        }
        return null;
    }
};

pub const JedecData = struct {

    width: u16,
    height: u16,
    raw: std.DynamicBitSet,
    usercode: ?u32 = null,
    security: ?u1 = null,
    pin_count: ?u16 = null,

    fn init(allocator: std.mem.Allocator, width: u16, height: u16, default: u1) error{OutOfMemory}!JedecData {
        return if (default == 0) initEmpty(allocator, width, height) else initFull(allocator, width, height);
    }

    pub fn initEmpty(allocator: std.mem.Allocator, width: u16, height: u16) error{OutOfMemory}!JedecData {
        return JedecData {
            .width = width,
            .height = height,
            .raw = try std.DynamicBitSet.initEmpty(allocator, @as(u32, width) * height),
        };
    }

    pub fn initFull(allocator: std.mem.Allocator, width: u16, height: u16) error{OutOfMemory}!JedecData {
        return JedecData {
            .width = width,
            .height = height,
            .raw = try std.DynamicBitSet.initFull(allocator, @as(u32, width) * height),
        };
    }

    pub fn deinit(self: *JedecData) void {
        self.raw.deinit();
        self.width = 0;
        self.height = 0;
    }

    pub fn clone(self: JedecData, allocator: std.mem.Allocator) error{OutOfMemory}!JedecData {
        return JedecData {
            .width = self.width,
            .height = self.height,
            .raw = try self.raw.clone(allocator),
            .usercode = self.usercode,
            .security = self.security,
            .pin_count = self.pin_count,
        };
    }

    pub fn parse(allocator: std.mem.Allocator, width: u16, height: ?u16, name: []const u8, data: []const u8) !JedecData {
        var pin_count: ?u16 = null;
        var usercode: ?u32 = null;
        var security: ?u1 = null;
        var default: ?u1 = null;
        var fuse_checksum: ?u16 = null;
        var actual_height: ?u16 = height;

        var self: ?JedecData = null;

        const start_of_fields = 1 + (std.mem.indexOf(u8, data, "*") orelse return error.MalformedJedecFile);

        var iter = JedecFieldIterator {
            .file_name = name,
            .remaining = data[start_of_fields..],
        };

        while (try iter.next()) |field| {
            switch (field.cmd) {
                .qty_fuses => {
                    const qf = std.fmt.parseUnsigned(u32, field.extra, 10) catch return error.MalformedJedecFile;
                    if (actual_height) |h| {
                        const expected = @as(u32, h) * width;
                        if (qf != expected) {
                            try std.io.getStdErr().writer().print("{s}: Expected fuse count to be exactly {}, but found {}\n", .{ name, expected, qf });
                            return error.IncorrectFuseCount;
                        }
                    } else {
                        const h = qf / width;
                        if (h * width != qf) {
                            try std.io.getStdErr().writer().print("{s}: Expected fuse count to be a multiple of {}, but found {}\n", .{ name, width, qf });
                            return error.IncorrectFuseCount;
                        }
                        actual_height = @intCast(u16, h);
                    }
                },
                .qty_pins => if (pin_count) |_| {
                    return error.MalformedJedecFile;
                } else {
                    pin_count = std.fmt.parseUnsigned(u16, field.extra, 10) catch return error.MalformedJedecFile;
                },
                .checksum => if (fuse_checksum) |_| {
                    return error.MalformedJedecFile;
                } else {
                    fuse_checksum = std.fmt.parseUnsigned(u16, field.extra, 16) catch return error.MalformedJedecFile;
                },
                .security => if (security) |_| {
                    return error.MalformedJedecFile;
                } else {
                    security = std.fmt.parseUnsigned(u1, field.extra, 10) catch return error.MalformedJedecFile;
                },
                .default => if (default) |_| {
                    return error.MalformedJedecFile;
                } else {
                    default = std.fmt.parseUnsigned(u1, field.extra, 10) catch return error.MalformedJedecFile;
                },
                .usercode => if (usercode) |_| {
                    return error.MalformedJedecFile;
                } else {
                    usercode = std.fmt.parseUnsigned(u32, field.extra, 2) catch return error.MalformedJedecFile;
                },
                .location, .hex => {
                    var end_of_digits: usize = 0;
                    while (end_of_digits < field.extra.len) : (end_of_digits += 1) {
                        var c = field.extra[end_of_digits];
                        if (c < '0' or c > '9') break;
                    }

                    const location_str = field.extra[0..end_of_digits];
                    const data_str = field.extra[end_of_digits..];
                    const starting_fuse = std.fmt.parseUnsigned(u32, location_str, 10) catch return error.MalformedJedecFile;
                    if (self == null) {
                        if (actual_height) |h| {
                            self = try init(allocator, width, h, default orelse 1);
                        } else {
                            try std.io.getStdErr().writer().print("{s}: Expected QF command before L or K command\n", .{ name });
                            return error.MalformedJedecFile;
                        }
                    }
                    switch (field.cmd) {
                        .location => try self.?.parseBinaryString(starting_fuse, data_str),
                        .hex => try self.?.parseHexString(starting_fuse, data_str),
                        else => unreachable,
                    }
                },
                .note => {}, // ignore comment
            }
        }

        if (iter.remaining[0] == 3 and iter.remaining.len >= 5) {
            // check final file checksum
            const found_checksum = std.fmt.parseUnsigned(u16, iter.remaining[1..5], 16) catch return error.MalformedJedecFile;
            var computed_checksum: u16 = 0;
            for (data[0..data.len-iter.remaining.len]) |byte| {
                computed_checksum += byte;
            }

            if (found_checksum != computed_checksum) {
                try std.io.getStdErr().writer().print("{s}: File checksum mismatch; file specifies {X:0>4} but computed {X:0>4}\n", .{ name, found_checksum, computed_checksum });
                return error.CorruptedJedecFile;
            }
        }

        if (self) |*s| {
            if (fuse_checksum) |found_checksum| {
                var computed_checksum = s.checksum();
                if (found_checksum != computed_checksum) {
                    try std.io.getStdErr().writer().print("{s}: Fuse checksum mismatch; file specifies {X:0>4} but computed {X:0>4}\n", .{ name, found_checksum, computed_checksum });
                    return error.CorruptedJedecFile;
                }
            }

            s.security = security;
            s.usercode = usercode;
            s.pin_count = pin_count;
            return s.*;
        } else {
            try std.io.getStdErr().writer().print("{s}: Expected at least one L or K command\n", .{ name });
            return error.MalformedJedecFile;
        }
    }

    pub fn write(self: JedecData, writer: anytype, options: core.FuseFileWriteOptions) !void {
        switch (options.format) {
            .jed => {
                try self.writeJed(writer, options);
            },
            .svf => {
                try svf.write(self, writer, options);
            },
        }
    }

    fn writeJed(self: JedecData, writer: anytype, options: core.FuseFileWriteOptions) !void {
        var w = @import("checksum_writer.zig").checksumWriter(u16, self.raw.allocator, writer);

        try w.writeByte(0x2); // STX
        try w.writeByte('*');
        try w.writeAll(options.line_ending);

        if (self.pin_count) |qp| {
            try w.print("QP{}*{s}", .{ qp, options.line_ending });
        }

        try w.print("QF{}*{s}", .{ self.length(), options.line_ending });

        if (self.security) |g| {
            try w.print("G{}*{s}", .{ g, options.line_ending });
        }

        if (options.jed_compact) {
            const len = self.length();
            const num_set = self.raw.count();
            var default: u1 = undefined;
            var default_hex: u8 = undefined;
            if (num_set * 2 < len) {
                default = 0;
                default_hex = '0';
            } else {
                default = 1;
                default_hex = 'F';
            }

            try w.print("F{}*", .{ default });

            var unwritten_defaults: usize = 8888;
            var fuse: usize = 0;
            while (fuse < len) : (fuse += 4) {
                const b0: u4 = @boolToInt(self.raw.isSet(fuse + 0));
                const b1: u4 = if (fuse + 1 < len) @boolToInt(self.raw.isSet(fuse + 1)) else default;
                const b2: u4 = if (fuse + 2 < len) @boolToInt(self.raw.isSet(fuse + 2)) else default;
                const b3: u4 = if (fuse + 3 < len) @boolToInt(self.raw.isSet(fuse + 3)) else default;

                const val: u8 = 8*b0 + 4*b1 + 2*b2 + b3;
                const hex = if (val < 0xA) '0' + val else 'A' + val - 0xA;

                if (hex == default_hex) {
                    unwritten_defaults += 1;
                } else if (unwritten_defaults > 7) {
                    try w.print("{s}K{} {}", .{ options.line_ending, fuse, hex });
                    unwritten_defaults = 0;
                } else if (unwritten_defaults > 0) {
                    try w.writeByteNTimes(default_hex, unwritten_defaults);
                    try w.writeByte(hex);
                    unwritten_defaults = 0;
                } else {
                    try w.writeByte(hex);
                }
            }
            try w.writeAll(options.line_ending);
        } else {
            try w.print("F0*{s}L0{s}", .{ options.line_ending, options.line_ending });
            var fuse: usize = 0;
            var row: u16 = 0;
            while (row < self.height) : (row += 1) {
                var col: u16 = 0;
                while (col < self.width) : (col += 1) {
                    if (self.raw.isSet(fuse)) {
                        try w.writeByte('1');
                    } else {
                        try w.writeByte('0');
                    }
                    fuse += 1;
                }
                try w.writeAll(options.line_ending);
            }
        }
        try w.print("*{s}", .{options.line_ending});

        const fuse_checksum = self.checksum();
        try w.print("C{X:0>4}*{s}", .{ fuse_checksum, options.line_ending });

        if (self.usercode) |u| {
            try w.print("U{b:0>32}*{s}", .{ u, options.line_ending });
        }

        try w.writeByte(0x3); // ETX
        try writer.print("{X:0>4}{s}", .{ w.checksum, options.line_ending });
    }

    pub fn parseBinaryString(self: *JedecData, starting_fuse: usize, data: []const u8) !void {
        var i: usize = starting_fuse;
        for (data) |c| {
            switch (c) {
                '0' => {
                    try self.setFuse(i, false);
                    i += 1;
                },
                '1' => {
                    try self.setFuse(i, true);
                    i += 1;
                },
                '\r', '\n', '\t', ' ' => {},
                else => {
                    return error.InvalidData;
                },
            }
        }
    }

    pub fn parseHexString(self: *JedecData, starting_fuse: usize, data: []const u8) !void {
        var i: usize = starting_fuse;
        for (data) |c| {
            const val: ?u4 = switch (c) {
                '0'...'9' => @intCast(u4, c - '0'),
                'A'...'F' => @intCast(u4, c - 'A' + 0xA),
                'a'...'f' => @intCast(u4, c - 'a' + 0xA),
                '\r', '\n', '\t', ' ' => null,
                else => return error.InvalidData,
            };
            if (val) |v| {
                const len = self.length();
                try self.setFuse(i, 0 != @truncate(u1, v >> 3));
                i += 1;
                if (i < len) try self.setFuse(i, 0 != @truncate(u1, v >> 2));
                i += 1;
                if (i < len) try self.setFuse(i, 0 != @truncate(u1, v >> 1));
                i += 1;
                if (i < len) try self.setFuse(i, 0 != @truncate(u1, v >> 0));
                i += 1;
            }
        }
    }

    pub fn setFuse(self: *JedecData, fuse: usize, value: bool) !void {
        if (fuse >= self.length()) {
            return error.InvalidFuse;
        }
        self.raw.setValue(fuse, value);
    }

    pub fn checksum(self: JedecData) u16 {
        var sum: u16 = 0;

        const MaskInt = std.DynamicBitSet.MaskInt;
        var masks: []MaskInt = undefined;
        masks.ptr = self.raw.unmanaged.masks;
        masks.len = (self.length() + (@bitSizeOf(MaskInt) - 1)) / @bitSizeOf(MaskInt);

        for (masks) |mask| {
            var x = mask;
            comptime var i = 0;
            inline while (i < @sizeOf(MaskInt)) : (i += 1) {
                sum +%= @truncate(u8, x);
                x = x >> 8;
            }
        }

        return sum;
    }

    pub fn length(self: JedecData) usize {
        return self.width * @as(usize, self.height);
    }

    pub fn getRow(self: JedecData, fuse: u32) u32 {
        return @intCast(u32, fuse / self.width);
    }

    pub fn getColumn(self: JedecData, fuse: u32) u32 {
        return @intCast(u32, fuse - self.getRow(fuse) * self.width);
    }

    pub fn get(self: JedecData, row: u32, col: u32) u1 {
        return switch (self.raw.isSet(row * self.width + col)) {
            true => 1,
            false => 0,
        };
    }

    pub fn set(self: *JedecData, row: u32, col: u32, val: u1) void {
        self.raw.setValue(row * self.width + col, val == 1);
    }

    pub fn xor(self: *JedecData, other: JedecData) !void {
        if (self.length() != other.length()) {
            return error.IncompatibleJedecData;
        }

        self.raw.toggleSet(other.raw);

        if (self.usercode != null or other.usercode != null) {
            const s: u32 = self.usercode orelse 0;
            const o: u32 = other.usercode orelse 0;
            self.usercode = s ^ o;
        }

        if (self.security != null or other.security != null) {
            const s: u1 = self.security orelse 0;
            const o: u1 = other.security orelse 0;
            self.security = s ^ o;
        }
    }

    // pub fn writeHex(self: JedecData, writer: anytype) !void {
    //     var r: u32 = 0;
    //     while (r < Self.rows) : (r += 1) {
    //         var c: u32 = 0;
    //         while (c < Self.width - 3) : (c += 4) {
    //             const v: u4 = self.get(r, Self.width - c - 1)
    //                     + self.get(r, Self.width - c - 2) * @as(u4, 2)
    //                     + self.get(r, Self.width - c - 3) * @as(u4, 4)
    //                     + self.get(r, Self.width - c - 4) * @as(u4, 8);
    //             const base: u8 = if (v > 9) 'A' - 0xA else '0';
    //             _ = try writer.writeByte(base + v);
    //         }

    //         std.debug.assert(c == Self.width);
    //         _ = try writer.writeByte('\n');
    //     }
    // }
};
