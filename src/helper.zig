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
const GlbInputSignal = toolchain.GlbInputSignal;

var temp_alloc = TempAllocator {};

pub fn main(num_inputs: usize) void {
    run(num_inputs) catch |e| {
        std.io.getStdErr().writer().print("{}\n", .{ e }) catch {};
        std.os.exit(1);
    };
}

pub fn resetTemp() void {
    temp_alloc.reset();
}

pub const InputFileData = struct {
    contents: []const u8,
    filename: []const u8,
    device: DeviceType,
};

var input_files: std.StringHashMapUnmanaged(InputFileData) = .{};

pub fn getInputFile(filename: []const u8) ?InputFileData {
    return input_files.get(filename);
}

fn run(num_inputs: usize) !void {
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

    var i: usize = 0;
    while (i < num_inputs) : (i += 1) {
        const in_path = args.next() orelse return error.BadCommandLine;
        const in_dir_path = std.fs.path.dirname(in_path) orelse return error.InvalidOutputPath;
        const in_filename = std.fs.path.basename(in_path);
        const in_device_str = std.fs.path.basename(in_dir_path);
        const in_device = DeviceType.parse(in_device_str) orelse return error.InvalidDevice;

        var contents = try std.fs.cwd().readFileAlloc(pa, in_path, 100_000_000);

        try input_files.put(pa, in_filename, .{
            .contents = contents,
            .filename = in_filename,
            .device = in_device,
        });
    }

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

pub fn parseGRP(ta: std.mem.Allocator, pa: std.mem.Allocator, out_device: ?*DeviceType) !std.AutoHashMap(Fuse, GlbInputSignal) {
    const input_file = getInputFile("grp.sx") orelse return error.InvalidCommandLine;
    const device = input_file.device;

    var results = std.AutoHashMap(Fuse, GlbInputSignal).init(pa);
    try results.ensureTotalCapacity(@intCast(u32, device.getGIRange(0, 0).count() * 36 * device.getNumGlbs()));

    var pin_number_to_index = std.StringHashMap(u16).init(ta);
    defer pin_number_to_index.deinit();
    try pin_number_to_index.ensureTotalCapacity(@intCast(u32, device.getPins().len));
    for (device.getPins()) |pin_info| {
        try pin_number_to_index.put(pin_info.pin_number(), pin_info.pin_index());
    }

    var parser = try sx.Parser.init(input_file.contents, ta);
    defer parser.deinit();

    parseGRP0(&parser, device, &pin_number_to_index, &results) catch |e| switch (e) {
        error.SExpressionSyntaxError => {
            try parser.printParseErrorContext();
            return e;
        },
        else => return e,
    };

    if (out_device) |ptr| {
        ptr.* = device;
    }

    return results;
}

fn parseGRP0(parser: *sx.Parser, device: DeviceType, pin_number_to_index: *const std.StringHashMap(u16), results: *std.AutoHashMap(Fuse, GlbInputSignal)) !void {
    _ = try parser.requireAnyExpression(); // device name, we already know it
    try parser.requireExpression("global_routing_pool");

    var glb: u8 = 0;
    while (glb < device.getNumGlbs()) : (glb += 1) {
        try parser.requireExpression("glb");
        var parsed_glb = try parser.requireAnyInt(u8, 10);
        std.debug.assert(glb == parsed_glb);
        if (try parser.expression("name")) {
            try parser.ignoreRemainingExpression();
        }

        while (try parser.expression("gi")) {
            _ = try parser.requireAnyInt(usize, 10);

            while (try parser.expression("fuse")) {
                var row = try parser.requireAnyInt(u16, 10);
                var col = try parser.requireAnyInt(u16, 10);
                var fuse = Fuse.init(row, col);

                if (try parser.expression("pin")) {
                    var pin_number = try parser.requireAnyString();
                    var pin_index = pin_number_to_index.get(pin_number).?;
                    try results.put(fuse, .{
                        .pin = pin_index,
                    });
                    try parser.requireClose(); // pin
                } else if (try parser.expression("glb")) {
                    var fuse_glb = try parser.requireAnyInt(u8, 10);
                    if (try parser.expression("name")) {
                        try parser.ignoreRemainingExpression();
                    }
                    try parser.requireClose(); // glb

                    try parser.requireExpression("mc");
                    var fuse_mc = try parser.requireAnyInt(u8, 10);
                    try parser.requireClose(); // mc

                    try results.put(fuse, .{
                        .fb = .{
                            .glb = fuse_glb,
                            .mc = fuse_mc,
                        },
                    });
                } else if (try parser.expression("unused")) {
                    try parser.ignoreRemainingExpression();
                }
                try parser.requireClose(); // fuse
            }
            try parser.requireClose(); // gi
        }
        try parser.requireClose(); // glb
    }
    try parser.requireClose(); // global_routing_pool
    try parser.requireClose(); // device
    try parser.requireDone();
}
