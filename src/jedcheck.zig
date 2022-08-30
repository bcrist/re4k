const std = @import("std");
const jedec = @import("jedec.zig");

var temp_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);

// TODO handle other device layouts
const DeviceJed = jedec.JedecData;

fn readJedec(filename: []const u8) !DeviceJed {
    var f = try std.fs.cwd().openFile(filename, .{});
    defer f.close();
    var raw = try f.readToEndAlloc(temp_alloc.allocator(), 0x100000000);
    return try DeviceJed.parse(temp_alloc.allocator(), 172, null, filename, raw);
}

pub fn main() !void {
    var args = try std.process.ArgIterator.initWithAllocator(temp_alloc.allocator());
    _ = args.next() orelse std.os.exit(255);

    while (args.next()) |path| {
        try check(try readJedec(path), path);
    }
}

const MacrocellId = struct {
    glb: u8,
    mc: u8,
};

fn getMacrocellForColumn(col: u32) ?MacrocellId {
    return switch (col) {
        7 => .{ .glb = 1, .mc = 0 },
        8 => .{ .glb = 1, .mc = 1 },
        17 => .{ .glb = 1, .mc = 2 },
        18 => .{ .glb = 1, .mc = 3 },
        27 => .{ .glb = 1, .mc = 4 },
        28 => .{ .glb = 1, .mc = 5 },
        37 => .{ .glb = 1, .mc = 6 },
        38 => .{ .glb = 1, .mc = 7 },
        47 => .{ .glb = 1, .mc = 8 },
        48 => .{ .glb = 1, .mc = 9 },
        57 => .{ .glb = 1, .mc = 10 },
        58 => .{ .glb = 1, .mc = 11 },
        67 => .{ .glb = 1, .mc = 12 },
        68 => .{ .glb = 1, .mc = 13 },
        77 => .{ .glb = 1, .mc = 14 },
        78 => .{ .glb = 1, .mc = 15 },

        93 => .{ .glb = 0, .mc = 0 },
        94 => .{ .glb = 0, .mc = 1 },
        103 => .{ .glb = 0, .mc = 2 },
        104 => .{ .glb = 0, .mc = 3 },
        113 => .{ .glb = 0, .mc = 4 },
        114 => .{ .glb = 0, .mc = 5 },
        123 => .{ .glb = 0, .mc = 6 },
        124 => .{ .glb = 0, .mc = 7 },
        133 => .{ .glb = 0, .mc = 8 },
        134 => .{ .glb = 0, .mc = 9 },
        143 => .{ .glb = 0, .mc = 10 },
        144 => .{ .glb = 0, .mc = 11 },
        153 => .{ .glb = 0, .mc = 12 },
        154 => .{ .glb = 0, .mc = 13 },
        163 => .{ .glb = 0, .mc = 14 },
        164 => .{ .glb = 0, .mc = 15 },

        else => null,
    };
}

fn isKnownFuse(row: u32, col: u32) bool {
    if (row < 72) return true;
    if (getMacrocellForColumn(col)) |_| {
        return true;
    } else if (row == 99) {
        // pgdf flags
        if (col >= 92) {
            var n = col - 92;
            n /= 5;
            if (col == n * 5 + 92) {
                return true;
            }
        } else if (col >= 6) {
            var n = col - 6;
            n /= 5;
            if (col == n * 5 + 6) {
                return true;
            }
        }
    } else if (row == 72 and (col == 85 or col == 171)) {
        // shared ptclk polarity
        return true;
    } else if ((row == 73 or row == 74) and (col == 85 or col == 171)) {
        // BIE to GOE2/3
        return true;
    } else if ((col == 3 or col == 89) and row >= 79 and row <= 82) {
        // block clock polarity
        return true;
    } else if ((row == 85 or row == 86) and col >= 168) {
        // gclk/input bus maintenance
        return true;
    } else if (col == 168 and row >= 87 and row <= 90) {
        // gclk pgdf
        return true;
    } else if (row == 95 and col >= 168) {
        // gclk input threshold
        return true;
    } else if (row == 87 and col == 171) {
        // zero hold time
        return true;
    } else if (col == 171 and row >= 88 and row <= 91) {
        // goe polarity
        return true;
    } else if (col == 168 and (row == 91 or row == 92)) {
        // OSCTIMER enables
        return true;
    } else if ((col == 169 or col == 170) and row == 92) {
        // OSCTIMER divisor
        return true;
    }
    return false;
}

fn check(jed: DeviceJed, filename: []const u8) !void {
    var iter = jed.raw.iterator(.{
        .kind = .unset
    });
    while (iter.next()) |fuse| {
        var row = jed.getRow(@intCast(u32, fuse));
        var col = jed.getColumn(@intCast(u32, fuse));
        if (!isKnownFuse(row, col)) {
            if (getMacrocellForColumn(col)) |mc| {
                try std.io.getStdOut().writer().print("{s}: Unknown fuse set at {}:{}\t{}\n", .{ filename, row, col, mc });
            } else {
                try std.io.getStdOut().writer().print("{s}: Unknown fuse set at {}:{}\n", .{ filename, row, col });
            }
        }
    }
}
