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

pub fn main() !void {
    var args = try std.process.ArgIterator.initWithAllocator(temp_alloc.allocator());
    _ = args.next() orelse std.os.exit(255);
    var out_path = args.next() orelse std.os.exit(1);

    var data = std.ArrayList(DeviceJed).init(temp_alloc.allocator());

    var args_copy = args;

    var min_row: u32 = 0;
    var max_row: u32 = DeviceJed.rows-1;
    var min_col: u32 = 0;
    var max_col: u32 = DeviceJed.width-1;

    while (args.next()) |path| {
        if (path[0] == '-') {
            if (std.mem.eql(u8, path, "--rows")) {
                var range_it = std.mem.split(u8, args.next() orelse return error.ExpectedRange, "-");
                min_row = try std.fmt.parseUnsigned(u32, range_it.next() orelse return error.InvalidRange, 10);
                max_row = try std.fmt.parseUnsigned(u32, range_it.next() orelse return error.InvalidRange, 10);
            } else if (std.mem.eql(u8, path, "--cols")) {
                var range_it = std.mem.split(u8, args.next() orelse return error.ExpectedRange, "-");
                min_col = try std.fmt.parseUnsigned(u32, range_it.next() orelse return error.InvalidRange, 10);
                max_col = try std.fmt.parseUnsigned(u32, range_it.next() orelse return error.InvalidRange, 10);
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

    {
        var row: u32 = 0;
        while (row < min_row) : (row += 1) {
            var col: u32 = 0;
            while (col < DeviceJed.width) : (col += 1) {
                combined_diff.set(row, col, 0);
            }
        }
        row = max_row + 1;
        while (row < DeviceJed.rows) : (row += 1) {
            var col: u32 = 0;
            while (col < DeviceJed.width) : (col += 1) {
                combined_diff.set(row, col, 0);
            }
        }
    }

    {
        var col: u32 = 0;
        while (col < min_col) : (col += 1) {
            var row: u32 = min_row;
            while (row < max_row) : (row += 1) {
                combined_diff.set(row, col, 0);
            }
        }
        col = max_col + 1;
        while (col < DeviceJed.width) : (col += 1) {
            var row: u32 = min_row;
            while (row < max_row) : (row += 1) {
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
            }
        } else {
            try writer.print(",{s}", .{ path });
        }
    }
    _ = try writer.write("\n");


    var diff_iter = combined_diff.raw.iterator(.{});
    while (diff_iter.next()) |fuse| {
        try writer.print("{}:{}",.{ DeviceJed.getRow(fuse), DeviceJed.getColumn(fuse) });

        for (data.items) |d| {
            const v: u32 = if (d.raw.isSet(fuse)) 1 else 0;
            try writer.print(",{}", .{ v });
        }
        _ = try writer.write("\n");
    }

    //try combined_diff.writeHex(writer);
}
