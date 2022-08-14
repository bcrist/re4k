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

    var mode = args.next() orelse std.os.exit(2);
    _ = mode;

    var data = std.ArrayList(DeviceJed).init(temp_alloc.allocator());

    var args_copy = args;

    while (args.next()) |path| {
        try data.append(try readJedec(path));
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

    var f = try std.fs.cwd().createFile(out_path, .{});
    defer f.close();

    var writer = f.writer();
    _ = try writer.write("fuse");
    while (args_copy.next()) |path| {
        try writer.print(",{s}", .{ path });
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
