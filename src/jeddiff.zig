const std = @import("std");
const jedec = @import("jedec.zig");

var temp_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);

// TODO handle other device layouts
const DeviceJed = jedec.JedecData(172, 100);

fn readJedec(filename: []const u8) !jedec.JedecData(172, 100) {
    var f = try std.fs.cwd().openFile(filename, .{});
    defer f.close();
    var raw = try f.readToEndAlloc(temp_alloc.allocator(), 0x100000000);
    return try DeviceJed.init(raw);
}

const Range = struct {
    min_row: u32,
    max_row: u32,
    min_col: u32,
    max_col: u32,

    pub fn parse(str: []const u8) !Range {
        var range_it = std.mem.split(u8, str, "-");
        var first = range_it.next() orelse return error.InvalidRange;

        var first_iter = std.mem.split(u8, first, ":");
        var min_row = try std.fmt.parseUnsigned(u32, first_iter.next() orelse return error.InvalidFuse, 10);
        var min_col: u32 = undefined;
        if (first_iter.next()) |col| {
            min_col = try std.fmt.parseUnsigned(u32, col, 10);
        } else {
            min_col = DeviceJed.getColumn(min_row);
            min_row = DeviceJed.getRow(min_row);
        }

        var second = range_it.next() orelse return error.InvalidRange;
        var second_iter = std.mem.split(u8, second, ":");
        var max_row = try std.fmt.parseUnsigned(u32, second_iter.next() orelse return error.InvalidFuse, 10);
        var max_col: u32 = undefined;
        if (second_iter.next()) |col| {
            max_col = try std.fmt.parseUnsigned(u32, col, 10);
        } else {
            max_col = DeviceJed.getColumn(max_row);
            max_row = DeviceJed.getRow(max_row);
        }

        return Range {
            .min_row = min_row,
            .max_row = max_row,
            .min_col = min_col,
            .max_col = max_col,
        };
    }

    pub fn parseRows(str: []const u8, min_col: u32, max_col: u32) !Range {
        var range_it = std.mem.split(u8, str, "-");
        var min_row = try std.fmt.parseUnsigned(u32, range_it.next() orelse return error.InvalidRange, 10);
        var max_row = try std.fmt.parseUnsigned(u32, range_it.next() orelse return error.InvalidRange, 10);

        return Range {
            .min_row = min_row,
            .max_row = max_row,
            .min_col = min_col,
            .max_col = max_col,
        };
    }
    pub fn parseColumns(str: []const u8, min_row: u32, max_row: u32) !Range {
        var range_it = std.mem.split(u8, str, "-");
        var min_col = try std.fmt.parseUnsigned(u32, range_it.next() orelse return error.InvalidRange, 10);
        var max_col = try std.fmt.parseUnsigned(u32, range_it.next() orelse return error.InvalidRange, 10);

        return Range {
            .min_row = min_row,
            .max_row = max_row,
            .min_col = min_col,
            .max_col = max_col,
        };
    }
    pub fn contains(self: Range, row: u32, col: u32) bool {
        return row >= self.min_row and row <= self.max_row
            and col >= self.min_row and col <= self.max_row;
    }
};

pub fn main() !void {
    var args = try std.process.ArgIterator.initWithAllocator(temp_alloc.allocator());
    _ = args.next() orelse std.os.exit(255);
    var out_path = args.next() orelse std.os.exit(1);

    var data = std.ArrayList(DeviceJed).init(temp_alloc.allocator());

    var args_copy = args;

    var range = Range {
        .min_row = 0,
        .max_row = DeviceJed.rows-1,
        .min_col = 0,
        .max_col = DeviceJed.width-1,
    };

    var exclusions = std.ArrayList(Range).init(temp_alloc.allocator());

    while (args.next()) |path| {
        if (path[0] == '-') {
            if (std.mem.eql(u8, path, "--rows")) {
                range = try Range.parseRows(args.next() orelse return error.ExpectedRange, range.min_col, range.max_col);
            } else if (std.mem.eql(u8, path, "--cols")) {
                range = try Range.parseColumns(args.next() orelse return error.ExpectedRange, range.min_row, range.max_row);
            } else if (std.mem.eql(u8, path, "--exclude")) {
                try exclusions.append(try Range.parse(args.next() orelse return error.ExpectedRange));
            } else {
                try std.io.getStdErr().writer().print("Unrecognized option: {s}\n", .{ path });
                std.os.exit(2);
            }
        } else {
            try data.append(try readJedec(path));
        }
    }

    var combined_diff = DeviceJed {
        .raw = std.StaticBitSet(DeviceJed.len).initEmpty(),
    };

    if (data.items.len > 1) {
        var first = data.items[0];
        for (data.items[1..]) |d| {
            combined_diff.raw.setUnion(first.diff(d).raw);
        }
    }

    for (exclusions.items) |r| {
        var row: u32 = r.min_row;
        while (row <= r.max_row) : (row += 1) {
            var col: u32 = r.min_col;
            while (col <= r.max_col) : (col += 1) {
                combined_diff.set(row, col, 0);
            }
        }
    }

    {
        var row: u32 = 0;
        while (row < range.min_row) : (row += 1) {
            var col: u32 = 0;
            while (col < DeviceJed.width) : (col += 1) {
                combined_diff.set(row, col, 0);
            }
        }
        row = range.max_row + 1;
        while (row < DeviceJed.rows) : (row += 1) {
            var col: u32 = 0;
            while (col < DeviceJed.width) : (col += 1) {
                combined_diff.set(row, col, 0);
            }
        }
    }

    {
        var col: u32 = 0;
        while (col < range.min_col) : (col += 1) {
            var row: u32 = range.min_row;
            while (row < range.max_row) : (row += 1) {
                combined_diff.set(row, col, 0);
            }
        }
        col = range.max_col + 1;
        while (col < DeviceJed.width) : (col += 1) {
            var row: u32 = range.min_row;
            while (row < range.max_row) : (row += 1) {
                combined_diff.set(row, col, 0);
            }
        }
    }

    var f = try std.fs.cwd().createFile(out_path, .{});
    defer f.close();

    var writer = f.writer();
    _ = try writer.write("fuse");
    while (args_copy.next()) |path| {
        if (path[0] == '-') {
            if (std.mem.eql(u8, path, "--rows")) {
                _ = args_copy.next();
            } else if (std.mem.eql(u8, path, "--cols")) {
                _ = args_copy.next();
            } else if (std.mem.eql(u8, path, "--exclude")) {
                _ = args_copy.next();
            }
        } else {
            try writer.print(",{s}", .{ path });
        }
    }
    _ = try writer.write("\n");


    var diff_iter = combined_diff.raw.iterator(.{});
    while (diff_iter.next()) |fuse| {
        try writer.print("{}:{}",.{ DeviceJed.getRow(@intCast(u32, fuse)), DeviceJed.getColumn(@intCast(u32, fuse)) });

        for (data.items) |d| {
            const v: u32 = if (d.raw.isSet(fuse)) 1 else 0;
            try writer.print(",{}", .{ v });
        }
        _ = try writer.write("\n");
    }

    //try combined_diff.writeHex(writer);
}
