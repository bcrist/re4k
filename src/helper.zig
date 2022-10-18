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
const FuseRange = jedec.FuseRange;
const GlbInputSignal = toolchain.GlbInputSignal;
const MacrocellRef = core.MacrocellRef;

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
    temp_alloc = try TempAllocator.init(0x1000_00000);
    defer temp_alloc.deinit();

    var perm_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer perm_alloc.deinit();

    var ta = temp_alloc.allocator();
    var pa = perm_alloc.allocator();

    var args = try std.process.ArgIterator.initWithAllocator(pa);
    _ = args.next() orelse std.os.exit(255);

    const out_path = args.next() orelse return error.NeedOutputPath;
    const out_dir_path = std.fs.path.dirname(out_path) orelse return error.InvalidOutputPath;
    const out_filename = std.fs.path.basename(out_path);
    const device_str = std.fs.path.basename(out_dir_path);
    const device = DeviceType.parse(device_str) orelse return error.InvalidDevice;

    var out_dir = try std.fs.cwd().makeOpenPath(out_dir_path, .{});
    defer out_dir.close();

    var i: usize = 0;
    while (i < num_inputs) : (i += 1) {
        const in_path = args.next() orelse return error.NotEnoughInputFiles;
        const in_dir_path = std.fs.path.dirname(in_path) orelse return error.InvalidInputPath;
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
    mcref: ?MacrocellRef = null,
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

pub fn parseClusterUsage(ta: std.mem.Allocator, glb: u8, report: []const u8, mc: u8) !std.StaticBitSet(16) {
    var cluster_usage = std.StaticBitSet(16).initEmpty();
    const header = try std.fmt.allocPrint(ta, "GLB_{s}_CLUSTER_TABLE", .{ devices.getGlbName(glb) });
    if (extract(report, header, "<Note>")) |raw| {
        var line_iter = std.mem.tokenize(u8, raw, "\r\n");
        while (line_iter.next()) |line| {
            if (line[0] != 'M') {
                continue; // ignore remaining header/footer lines
            }

            var line_mc = try std.fmt.parseInt(u8, line[1..3], 10);
            if (line_mc == mc) {
                cluster_usage.setValue(0,  isClusterUsed(line[4]));
                cluster_usage.setValue(1,  isClusterUsed(line[5]));
                cluster_usage.setValue(2,  isClusterUsed(line[6]));
                cluster_usage.setValue(3,  isClusterUsed(line[7]));
                cluster_usage.setValue(4,  isClusterUsed(line[9]));
                cluster_usage.setValue(5,  isClusterUsed(line[10]));
                cluster_usage.setValue(6,  isClusterUsed(line[11]));
                cluster_usage.setValue(7,  isClusterUsed(line[12]));
                cluster_usage.setValue(8,  isClusterUsed(line[14]));
                cluster_usage.setValue(9,  isClusterUsed(line[15]));
                cluster_usage.setValue(10, isClusterUsed(line[16]));
                cluster_usage.setValue(11, isClusterUsed(line[17]));
                cluster_usage.setValue(12, isClusterUsed(line[19]));
                cluster_usage.setValue(13, isClusterUsed(line[20]));
                cluster_usage.setValue(14, isClusterUsed(line[21]));
                cluster_usage.setValue(15, isClusterUsed(line[22]));
            }
        }
    }
    return cluster_usage;
}

fn isClusterUsed(report_value: u8) bool {
    return switch (report_value) {
        '0'...'5' => true,
        else => false,
    };
}

pub fn parseGRP(ta: std.mem.Allocator, pa: std.mem.Allocator, out_device: ?*DeviceType) !std.AutoHashMap(Fuse, GlbInputSignal) {
    const input_file = getInputFile("grp.sx") orelse return error.MissingGRPInputFile;
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

pub fn parseMCOptionsColumns(ta: std.mem.Allocator, pa: std.mem.Allocator, out_device: ?*DeviceType) !std.AutoHashMap(MacrocellRef, FuseRange) {
    const input_file = getInputFile("invert.sx") orelse return error.MissingInvertInputFile;
    const device = input_file.device;

    var results = std.AutoHashMap(MacrocellRef, FuseRange).init(pa);
    try results.ensureTotalCapacity(device.getNumMcs());

    var parser = try sx.Parser.init(input_file.contents, ta);
    defer parser.deinit();

    parseMCOptionsColumns0(&parser, device, &results) catch |e| switch (e) {
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

fn parseMCOptionsColumns0(parser: *sx.Parser, device: DeviceType, results: *std.AutoHashMap(MacrocellRef, FuseRange)) !void {
    _ = try parser.requireAnyExpression(); // device name, we already know it
    try parser.requireExpression("invert_sum");

    var options_range = device.getOptionsRange();

    var glb: u8 = 0;
    while (glb < device.getNumGlbs()) : (glb += 1) {
        try parser.requireExpression("glb");
        var parsed_glb = try parser.requireAnyInt(u8, 10);
        std.debug.assert(glb == parsed_glb);
        if (try parser.expression("name")) {
            try parser.ignoreRemainingExpression();
        }

        while (try parser.expression("mc")) {
            var mc = try parser.requireAnyInt(u8, 10);

            try parser.requireExpression("fuse");
            _ = try parser.requireAnyInt(u16, 10);
            var col = try parser.requireAnyInt(u16, 10);

            var col_range = FuseRange.between(Fuse.init(0, col), Fuse.init(device.getJedecHeight() - 1, col));
            var opt_range = col_range.intersection(options_range);
            try results.put(.{ .glb = glb, .mc = mc }, opt_range);

            try parser.requireClose(); // fuse
            try parser.requireClose(); // mc
        }
        try parser.requireClose(); // glb
    }
    while (try parser.expression("value")) {
        try parser.ignoreRemainingExpression();
    }
    try parser.requireClose(); // invert_sum
    try parser.requireClose(); // device
    try parser.requireDone();
}

pub fn parseORMRows(ta: std.mem.Allocator, pa: std.mem.Allocator, out_device: ?*DeviceType) !std.DynamicBitSet {
    const input_file = getInputFile("orm.sx") orelse return error.MissingORMInputFile;
    const device = input_file.device;

    var results = try std.DynamicBitSet.initEmpty(pa, device.getJedecHeight());

    var parser = try sx.Parser.init(input_file.contents, ta);
    defer parser.deinit();

    parseORMRows0(&parser, &results) catch |e| switch (e) {
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

fn parseORMRows0(parser: *sx.Parser, results: *std.DynamicBitSet) !void {
    _ = try parser.requireAnyExpression(); // device name, we already know it
    try parser.requireExpression("output_routing_mux");

    while (try parser.expression("pin")) {
        _ = try parser.requireAnyString();

        while (try parser.expression("fuse")) {
            var row = try parser.requireAnyInt(u16, 10);
            _ = try parser.requireAnyInt(u16, 10);

            if (try parser.expression("value")) {
                try parser.ignoreRemainingExpression();
            }

            results.set(row);

            try parser.requireClose(); // fuse
        }
        try parser.requireClose(); // pin
    }
    while (try parser.expression("value")) {
        try parser.ignoreRemainingExpression();
    }
    try parser.requireClose(); // invert_sum
    try parser.requireClose(); // device
    try parser.requireDone();
}

pub fn parseClusterSteeringRows(ta: std.mem.Allocator, pa: std.mem.Allocator, out_device: ?*DeviceType) !std.DynamicBitSet {
    const input_file = getInputFile("cluster_steering.sx") orelse return error.MissingClusterSteeringInputFile;
    const device = input_file.device;

    var results = try std.DynamicBitSet.initEmpty(pa, device.getJedecHeight());

    var parser = try sx.Parser.init(input_file.contents, ta);
    defer parser.deinit();

    parseClusterSteeringRows0(&parser, &results) catch |e| switch (e) {
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

fn parseClusterSteeringRows0(parser: *sx.Parser, results: *std.DynamicBitSet) !void {
    _ = try parser.requireAnyExpression(); // device name, we already know it
    try parser.requireExpression("cluster_steering");

    while (try parser.expression("glb")) {
        _ = try parser.requireAnyInt(u16, 10);

        while (try parser.expression("mc")) {
            _ = try parser.requireAnyInt(u16, 10);

            while (try parser.expression("fuse")) {
                var row = try parser.requireAnyInt(u16, 10);
                _ = try parser.requireAnyInt(u16, 10);

                if (try parser.expression("value")) {
                    try parser.ignoreRemainingExpression();
                }

                results.set(row);

                try parser.requireClose(); // fuse
            }

            try parser.requireClose(); // mc
        }
        try parser.requireClose(); // glb
    }
    while (try parser.expression("value")) {
        try parser.ignoreRemainingExpression();
    }
    try parser.requireClose(); // cluster_steering
    try parser.requireClose(); // device
    try parser.requireDone();
}
