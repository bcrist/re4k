const root = @import("root");
const std = @import("std");
const lc4k = @import("lc4k");
const sx = @import("sx");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const Device_Info = @import("Device_Info.zig");
const Temp_Allocator = @import("Temp_Allocator");
const Toolchain = toolchain.Toolchain;
const Fuse = lc4k.Fuse;
const FuseRange = lc4k.Fuse_Range;
const JEDEC_Data = lc4k.JEDEC_Data;
const GLB_Input_Signal = toolchain.GLB_Input_Signal;
const MC_Ref = lc4k.MC_Ref;

pub fn main(init: std.process.Init) !void {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [64]u8 = undefined;

    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buf);
    var stderr_writer = std.Io.File.stdout().writer(init.io, &stderr_buf);

    helper.stdout = &stdout_writer.interface;
    helper.stderr = &stderr_writer.interface;

    defer helper.stdout.flush() catch {};
    defer helper.stderr.flush() catch {};

    try run(init.io, init.minimal.args);
}


fn run(io: std.Io, args: std.process.Args) !void {
    var perm_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer perm_alloc.deinit();

    const pa = perm_alloc.allocator();

    var args_iter = try args.iterateAllocator(pa);
    _ = args_iter.next() orelse std.process.exit(255);

    const out_path = args_iter.next() orelse return error.NeedOutputPath;
    const out_dir_path = std.Io.Dir.path.dirname(out_path) orelse return error.InvalidOutputPath;
    const out_filename = std.Io.Dir.path.basename(out_path);
    const device_str = out_filename[0..out_filename.len - std.Io.Dir.path.extension(out_filename).len];
    const device_type = lc4k.Device_Type.parse(device_str) orelse return error.InvalidDevice;

    var out_dir = try std.Io.Dir.cwd().createDirPathOpen(io, out_dir_path, .{});
    defer out_dir.close(io);

    var atf = try out_dir.createFileAtomic(io, out_filename, .{
        .make_path = true,
        .replace = true,
    });
    defer atf.deinit(io);

    var sx_buf: [4096]u8 = undefined;
    var atf_writer = atf.file.writer(io, &sx_buf);

    var sx_writer = sx.writer(pa, &atf_writer.interface);
    defer sx_writer.deinit();

    try sx_writer.expression_expanded(@tagName(device_type));

    var fuses = try JEDEC_Data.init_empty(pa, Device_Info.init(device_type).jedec_dimensions);

    while (args_iter.next()) |in_path| {
        const in_dir_path = std.Io.Dir.path.dirname(in_path) orelse return error.InvalidInputPath;
        const in_device_str = std.Io.Dir.path.basename(in_dir_path);
        const in_device_type = lc4k.Device_Type.parse(in_device_str) orelse return error.InvalidDevice;
        if (in_device_type != device_type) return error.WrongDevice;

        var f = try std.Io.Dir.cwd().openFile(io, in_path, .{});
        defer f.close(io);

        var buf: [4096]u8 = undefined;
        var reader = f.reader(io, &buf);

        var parser = sx.reader(pa, &reader.interface);
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
                                try helper.stderr.print("Fuse {}:{} overbooked!\n", .{ row, col });
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

    try atf_writer.interface.flush();
    try atf.replace(io);
}
