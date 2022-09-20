const root = @import("root");
const std = @import("std");
const core = @import("core.zig");
const sx = @import("sx.zig");
const jedec = @import("jedec.zig");
const toolchain = @import("toolchain.zig");
const devices = @import("devices.zig");
const TempAllocator = @import("temp_allocator");
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Fuse = jedec.Fuse;

var temp_alloc = TempAllocator {};

pub fn main() void {
    run() catch |e| {
        std.io.getStdErr().writer().print("{}\n", .{ e }) catch {};
        std.os.exit(1);
    };
}

pub fn resetTemp() void {
    temp_alloc.reset();
}

fn run() !void {
    temp_alloc = try TempAllocator.init(0x100_00000);
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

    var out_dir = try std.fs.cwd().makeOpenPath(out_dir_path, .{});
    defer out_dir.close();

    var keep = false;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--keep")) {
            keep = true;
        } else if (std.mem.eql(u8, arg, "--reports")) {
            report_dir = &out_dir;
        } else {
            return error.InvalidCommandLine;
        }
    }

    var f = try out_dir.createFile(out_filename, .{});
    defer f.close();

    var sx_writer = sx.writer(pa, f.writer());
    defer sx_writer.deinit();

    var tc = try Toolchain.init(ta);
    defer tc.deinit(keep);

    try root.run(ta, pa, &tc, device, &sx_writer);
}

var report_dir: ?*std.fs.Dir = null;

pub fn logReport(comptime name_fmt: []const u8, name_args: anytype, results: toolchain.FitResults) !void {
    if (report_dir) |dir| {
        const filename = try std.fmt.allocPrint(temp_alloc.allocator(), name_fmt ++ ".rpt", name_args);
        var f = try dir.createFile(filename, .{});
        defer f.close();

        try f.writer().writeAll(results.report);
    }
}

pub const ErrorContext = struct {
    mcref: ?core.MacrocellRef = null,
    glb: ?u8 = null,
    mc: ?u8 = null,
    pin_index: ?u16 = null,
};
pub fn err(comptime fmt: []const u8, args: anytype, device: DeviceType, context: ErrorContext) !void {
    const stderr = std.io.getStdErr().writer();

    if (context.mcref) |mcref| {
        try stderr.print("{s} glb{} ({s}) mc{}: ", .{ @tagName(device), mcref.glb, devices.getGlbName(mcref.glb), mcref.mc });
    } else if (context.glb) |glb| {
        if (context.mc) |mc| {
            try stderr.print("{s} glb{} ({s}) mc{}: ", .{ @tagName(device), glb, devices.getGlbName(glb), mc });
        } else {
            try stderr.print("{s} glb{} ({s}): ", .{ @tagName(device), glb, devices.getGlbName(glb) });
        }
    } else if (context.pin_index) |pin_index| {
        try stderr.print("{s} pin {s}: ", .{ @tagName(device), device.getPins()[pin_index].pin_number() });
    } else {
        try stderr.print("{s}: ", .{ @tagName(device) });
    }

    try stderr.print(fmt ++ "\n", args);
}

pub fn extract(src: []const u8, prefix: []const u8, suffix: []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, src, prefix)) |prefix_start| {
        const remaining = src[prefix_start + prefix.len..];
        if (std.mem.indexOf(u8, remaining, suffix)) |suffix_start| {
            return remaining[0..suffix_start];
        }
    }
    return null;
}

pub fn writeFuse(writer: anytype, fuse: Fuse) !void {
    try writer.expression("fuse");
    try writer.printRaw("{}", .{ fuse.row });
    try writer.printRaw("{}", .{ fuse.col });
    try writer.close();
}

pub fn writeFuseValue(writer: anytype, fuse: Fuse, value: usize) !void {
    try writer.expression("fuse");
    try writer.printRaw("{}", .{ fuse.row });
    try writer.printRaw("{}", .{ fuse.col });
    try writer.expression("value");
    try writer.printRaw("{}", .{ value });
    try writer.close();
    try writer.close();
}

pub fn writeFuseOptValue(writer: anytype, fuse: Fuse, value: usize) !void {
    try writer.expression("fuse");
    try writer.printRaw("{}", .{ fuse.row });
    try writer.printRaw("{}", .{ fuse.col });
    if (value != 1) {
        try writer.expression("value");
        try writer.printRaw("{}", .{ value });
        try writer.close();
    }
    try writer.close();
}

// pub const GISet = std.StaticBitSet(36);

// pub const GlbInputSetUnmanaged = struct {
//     raw: std.StaticBitSet(16*16*2+10)
// }