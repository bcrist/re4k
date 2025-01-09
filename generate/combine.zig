const root = @import("root");
const std = @import("std");
const lc4k = @import("lc4k");
const sx = @import("sx");
const toolchain = @import("toolchain.zig");
const Device_Info = @import("Device_Info.zig");
const Temp_Allocator = @import("Temp_Allocator");
const Toolchain = toolchain.Toolchain;
const Fuse = lc4k.Fuse;
const FuseRange = lc4k.Fuse_Range;
const JEDEC_Data = lc4k.JEDEC_Data;
const GLB_Input_Signal = toolchain.GLB_Input_Signal;
const MC_Ref = lc4k.MC_Ref;

pub fn main() void {
    run() catch unreachable; //catch |e| {
    //     std.io.getStdErr().writer().print("{}\n", .{ e }) catch {};
    //     std.os.exit(1);
    // };
}

fn run() !void {
    var perm_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer perm_alloc.deinit();

    const pa = perm_alloc.allocator();

    var args = try std.process.ArgIterator.initWithAllocator(pa);
    _ = args.next() orelse std.process.exit(255);

    const out_path = args.next() orelse return error.NeedOutputPath;
    const out_dir_path = std.fs.path.dirname(out_path) orelse return error.InvalidOutputPath;
    const out_filename = std.fs.path.basename(out_path);
    const device_str = out_filename[0..out_filename.len - std.fs.path.extension(out_filename).len];
    const device_type = lc4k.Device_Type.parse(device_str) orelse return error.InvalidDevice;

    var out_dir = try std.fs.cwd().makeOpenPath(out_dir_path, .{});
    defer out_dir.close();

    var atf = try out_dir.atomicFile(out_filename, .{});
    defer atf.deinit();

    const writer = atf.file.writer();

    var sx_writer = sx.writer(pa, writer.any());
    defer sx_writer.deinit();

    try sx_writer.expression_expanded(@tagName(device_type));

    var fuses = try JEDEC_Data.init_empty(pa, Device_Info.init(device_type).jedec_dimensions);

    while (args.next()) |in_path| {
        const in_dir_path = std.fs.path.dirname(in_path) orelse return error.InvalidInputPath;
        const in_device_str = std.fs.path.basename(in_dir_path);
        const in_device_type = lc4k.Device_Type.parse(in_device_str) orelse return error.InvalidDevice;
        if (in_device_type != device_type) return error.WrongDevice;

        var f = try std.fs.cwd().openFile(in_path, .{});
        defer f.close();

        const reader = f.reader();

        var parser = sx.reader(pa, reader.any());
        defer parser.deinit();

        if (try parser.expression(@tagName(device_type))) {
            var depth: i64 = 0;
            while (!try parser.done()) {
                sx_writer.set_compact(try parser.is_compact());
                if (try parser.expression("fuse")) {
                    try sx_writer.expression("fuse");
                    depth += 1;
                    if (try parser.any_int(u16, 10)) |row| {
                        try sx_writer.int(row, 10);
                        if (try parser.any_int(u16, 10)) |col| {
                            try sx_writer.int(col, 10);

                            const fuse = Fuse.init(row, col);

                            if (fuses.is_set(fuse)) {
                                const stderr = std.io.getStdErr().writer();
                                try stderr.print("Fuse {}:{} overbooked!\n", .{ row, col });
                            }
                            fuses.put(fuse, 1);
                        }
                    }
                } else if (try parser.close()) {
                    if (depth == 0) break else {
                        try sx_writer.close();
                        depth -= 1;
                    }
                } else if (try parser.open()) {
                    try sx_writer.open();
                    depth += 1;
                } else if (try parser.any_string()) |str| {
                    try sx_writer.string(str);
                } else unreachable;
            }
            while (depth > 0) {
                try sx_writer.close();
            }
        } else return error.InvalidInputFile;
    }

    try sx_writer.done();

    try atf.finish();
}
