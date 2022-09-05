const root = @import("root");
const std = @import("std");
const sx = @import("sx.zig");
const toolchain = @import("toolchain.zig");
const TempAllocator = @import("temp_allocator");
const DeviceType = @import("device.zig").DeviceType;
const Toolchain = toolchain.Toolchain;

var temp_alloc = TempAllocator {};

pub fn main() void {
    run() catch |err| {
        std.io.getStdErr().writer().print("{}\n", .{ err }) catch {};
        std.os.exit(1);
    };
}

pub fn resetTemp() void {
    //std.debug.print("Temp usage: {}\n", .{ temp_alloc.highWaterUsage() });
    temp_alloc.reset();
}

fn run() !void {
    temp_alloc = try TempAllocator.init(0x100_00000);
    defer temp_alloc.reset();
    defer temp_alloc.deinit();

    var perm_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer perm_alloc.deinit();

    var ta = temp_alloc.allocator();
    var pa = perm_alloc.allocator();

    var args = try std.process.ArgIterator.initWithAllocator(ta);
    _ = args.next() orelse std.os.exit(255);

    const out_path = args.next() orelse return error.BadCommandLine;
    const out_dir_path = std.fs.path.dirname(out_path) orelse return error.InvalidOutputPath;
    const out_filename = std.fs.path.basename(out_path);
    const device_str = std.fs.path.basename(out_dir_path);
    const device = DeviceType.parse(device_str) orelse return error.InvalidDevice;

    var keep = false;
    if (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--keep")) {
            keep = true;
        }
    }

    var out_dir = try std.fs.cwd().makeOpenPath(out_dir_path, .{});
    defer out_dir.close();

    var f = try out_dir.createFile(out_filename, .{});
    defer f.close();

    var sx_writer = sx.writer(pa, f.writer());
    defer sx_writer.deinit();

    var tc = try Toolchain.init(ta);
    defer tc.deinit(keep);

    try root.run(ta, pa, &tc, device, &sx_writer);
}
