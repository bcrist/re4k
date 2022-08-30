const std = @import("std");
const jedec = @import("jedec.zig");

var temp_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);

// TODO handle other device layouts
const DeviceJed = jedec.JedecData;

fn readJedec(filename: []const u8) !jedec.JedecData {
    var f = try std.fs.cwd().openFile(filename, .{});
    defer f.close();
    var raw = try f.readToEndAlloc(temp_alloc.allocator(), 0x100000000);
    return try DeviceJed.parse(temp_alloc.allocator(), 172, null, filename, raw);
}

fn parseAndAddRange(jed: *DeviceJed, str: []const u8) !void {
    var range_it = std.mem.split(u8, str, "-");
    var first = range_it.next() orelse return error.InvalidRange;

    var first_iter = std.mem.split(u8, first, ":");
    var min_row = try std.fmt.parseUnsigned(u32, first_iter.next() orelse return error.InvalidFuse, 10);
    var min_col: u32 = undefined;
    if (first_iter.next()) |col| {
        min_col = try std.fmt.parseUnsigned(u32, col, 10);
    } else {
        min_col = jed.getColumn(min_row);
        min_row = jed.getRow(min_row);
    }

    var second = range_it.next() orelse return error.InvalidRange;
    var second_iter = std.mem.split(u8, second, ":");
    var max_row = try std.fmt.parseUnsigned(u32, second_iter.next() orelse return error.InvalidFuse, 10);
    var max_col: u32 = undefined;
    if (second_iter.next()) |col| {
        max_col = try std.fmt.parseUnsigned(u32, col, 10);
    } else {
        max_col = jed.getColumn(max_row);
        max_row = jed.getRow(max_row);
    }

    var row: u32 = min_row;
    while (row <= max_row) : (row += 1) {
        var col: u32 = min_col;
        while (col <= max_col) : (col += 1) {
            jed.set(row, col, 1);
        }
    }
}

pub fn main() !void {
    var args = try std.process.ArgIterator.initWithAllocator(temp_alloc.allocator());
    _ = args.next() orelse std.os.exit(255);
    var out_path = args.next() orelse std.os.exit(1);

    var data = std.ArrayList(DeviceJed).init(temp_alloc.allocator());
    var paths = std.ArrayList([]const u8).init(temp_alloc.allocator());

    var has_include = false;

    var included = try DeviceJed.initFull(temp_alloc.allocator(), 172, 100);
    var excluded = try DeviceJed.initEmpty(temp_alloc.allocator(), 172, 100);

    while (args.next()) |path| {
        if (path[0] == '-') {
            if (std.mem.eql(u8, path, "--include")) {
                if (!has_include) {
                    included.raw.toggleAll();
                    has_include = true;
                }
                try parseAndAddRange(&included, args.next() orelse return error.ExpectedRange);
            } else if (std.mem.eql(u8, path, "--exclude")) {
                try parseAndAddRange(&excluded, args.next() orelse return error.ExpectedRange);
            } else {
                try std.io.getStdErr().writer().print("Unrecognized option: {s}\n", .{ path });
                std.os.exit(2);
            }
        } else {
            try data.append(try readJedec(path));
            try paths.append(path);
        }
    }

    var combined_diff = try DeviceJed.initEmpty(temp_alloc.allocator(), 172, 100);

    if (data.items.len > 1) {
        var first = data.items[0];
        for (data.items[1..]) |d| {
            combined_diff.raw.setUnion((try first.xor(d)).raw);
        }
    } else if (data.items.len == 1) {
        // just print bits that are cleared
        combined_diff = data.items[0];
        combined_diff.raw.toggleAll();
    }

    excluded.raw.toggleAll();
    combined_diff.raw.setIntersection(excluded.raw);

    combined_diff.raw.setIntersection(included.raw);

    if (std.mem.eql(u8, out_path, "stdout")) {
        try write(std.io.getStdOut().writer(), paths, combined_diff, data);
    } else {
        var f = try std.fs.cwd().createFile(out_path, .{});
        defer f.close();
        try write(f.writer(), paths, combined_diff, data);
    }
}

fn write(writer: anytype, headers: std.ArrayList([]const u8), combined_diff: DeviceJed, data: std.ArrayList(DeviceJed)) !void {
    try writer.writeAll("fuse");
    for (headers.items) |h| {
        try writer.print(",{s}", .{ h });
    }
    try writer.writeAll("\n");

    var diff_iter = combined_diff.raw.iterator(.{});
    while (diff_iter.next()) |fuse| {
        try writer.print("{}:{}",.{ combined_diff.getRow(@intCast(u32, fuse)), combined_diff.getColumn(@intCast(u32, fuse)) });

        for (data.items) |d| {
            const v: u32 = if (d.raw.isSet(fuse)) 1 else 0;
            try writer.print(",{}", .{ v });
        }
        try writer.writeAll("\n");
    }
}