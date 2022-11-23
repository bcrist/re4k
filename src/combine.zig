const root = @import("root");
const std = @import("std");
const core = @import("core.zig");
const sx = @import("sx");
const jedec = @import("jedec.zig");
const toolchain = @import("toolchain.zig");
const devices = @import("devices.zig");
const TempAllocator = @import("temp_allocator");
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Fuse = jedec.Fuse;
const FuseRange = jedec.FuseRange;
const JedecData = jedec.JedecData;
const GlbInputSignal = toolchain.GlbInputSignal;
const MacrocellRef = core.MacrocellRef;

pub fn main() void {
    run() catch unreachable; //catch |e| {
    //     std.io.getStdErr().writer().print("{}\n", .{ e }) catch {};
    //     std.os.exit(1);
    // };
}

fn run() !void {
    var perm_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer perm_alloc.deinit();

    var pa = perm_alloc.allocator();

    var args = try std.process.ArgIterator.initWithAllocator(pa);
    _ = args.next() orelse std.os.exit(255);

    const out_path = args.next() orelse return error.NeedOutputPath;
    const out_dir_path = std.fs.path.dirname(out_path) orelse return error.InvalidOutputPath;
    const out_filename = std.fs.path.basename(out_path);
    const device_str = out_filename[0..out_filename.len - std.fs.path.extension(out_filename).len];
    const device = DeviceType.parse(device_str) orelse return error.InvalidDevice;

    var out_dir = try std.fs.cwd().makeOpenPath(out_dir_path, .{});
    defer out_dir.close();

    var atf = try out_dir.atomicFile(out_filename, .{});
    defer atf.deinit();

    var writer = sx.writer(pa, atf.file.writer());
    defer writer.deinit();

    try writer.expressionExpanded(@tagName(device));

    var fuses = try device.initJedecZeroes(pa);

    while (args.next()) |in_path| {
        const in_dir_path = std.fs.path.dirname(in_path) orelse return error.InvalidInputPath;
        const in_device_str = std.fs.path.basename(in_dir_path);
        const in_device = DeviceType.parse(in_device_str) orelse return error.InvalidDevice;
        if (in_device != device) return error.WrongDevice;

        var f = try std.fs.cwd().openFile(in_path, .{});
        defer f.close();

        var reader = sx.reader(pa, f.reader());
        defer reader.deinit();

        if (try reader.expression(@tagName(device))) {
            var depth: i64 = 0;
            while (!try reader.done()) {
                writer.setCompact(try reader.isCompact());
                if (try reader.expression("fuse")) {
                    try writer.expression("fuse");
                    depth += 1;
                    if (try reader.anyInt(u16, 10)) |row| {
                        try writer.int(row, 10);
                        if (try reader.anyInt(u16, 10)) |col| {
                            try writer.int(col, 10);

                            const fuse = Fuse.init(row, col);

                            if (fuses.isSet(fuse)) {
                                const stderr = std.io.getStdErr().writer();
                                try stderr.print("Fuse {}:{} overbooked!\n", .{ row, col });
                            }
                            fuses.put(fuse, 1);
                        }
                    }
                } else if (try reader.close()) {
                    if (depth == 0) break else {
                        try writer.close();
                        depth -= 1;
                    }
                } else if (try reader.open()) {
                    try writer.open();
                    depth += 1;
                } else if (try reader.anyString()) |str| {
                    try writer.string(str);
                } else unreachable;
            }
            while (depth > 0) {
                try writer.close();
            }
        } else return error.InvalidInputFile;
    }

    try writer.done();

    try atf.finish();
}
