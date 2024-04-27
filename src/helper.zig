const root = @import("root");
const std = @import("std");
const Temp_Allocator = @import("Temp_Allocator");
const sx = @import("sx");
const lc4k = @import("lc4k");
const toolchain = @import("toolchain.zig");
const device_info = @import("device_info.zig");
const DeviceType = lc4k.DeviceType;
const DeviceInfo = device_info.DeviceInfo;
const Toolchain = toolchain.Toolchain;
const Fuse = lc4k.jedec.Fuse;
const FuseRange = lc4k.jedec.FuseRange;
const GlbInputSignal = toolchain.GlbInputSignal;
const GlbIndex = lc4k.GlbIndex;
const MacrocellRef = lc4k.MacrocellRef;
const MacrocellIndex = lc4k.MacrocellIndex;
const PinInfo = lc4k.PinInfo;
const getGlbName = lc4k.getGlbName;

var temp_alloc = Temp_Allocator {};

pub fn main() void {
    run() catch unreachable; //catch |e| {
    //     std.io.getStdErr().writer().print("{}\n", .{ e }) catch {};
    //     std.os.exit(1);
    // };
}

pub fn resetTemp() void {
    temp_alloc.reset(.{});
}

pub const InputFileData = struct {
    contents: []const u8,
    filename: []const u8,
    device_type: DeviceType,
    accessed: bool = false,
};

var input_files: std.StringHashMapUnmanaged(InputFileData) = .{};

pub fn getInputFile(filename: []const u8) ?InputFileData {
    if (input_files.getPtr(filename)) |data| {
        data.accessed = true;
        return data.*;
    }
    return null;
}

var slow_mode = false;

fn run() !void {
    temp_alloc = try Temp_Allocator.init(0x1000_00000);
    defer temp_alloc.deinit();

    var perm_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer perm_alloc.deinit();

    const ta = temp_alloc.allocator();
    const pa = perm_alloc.allocator();

    var args = try std.process.ArgIterator.initWithAllocator(pa);
    _ = args.next() orelse std.process.exit(255);

    const out_path = args.next() orelse return error.NeedOutputPath;
    const out_dir_path = std.fs.path.dirname(out_path) orelse return error.InvalidOutputPath;
    const out_filename = std.fs.path.basename(out_path);
    const device_str = std.fs.path.basename(out_dir_path);
    const device_type = DeviceType.parse(device_str) orelse return error.InvalidDevice;

    var out_dir = try std.fs.cwd().makeOpenPath(out_dir_path, .{});
    defer out_dir.close();

    var keep = false;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--keep")) {
            keep = true;
        } else if (std.mem.eql(u8, arg, "--reports")) {
            report_dir = &out_dir;
        } else if (std.mem.eql(u8, arg, "--jeds")) {
            jed_dir = &out_dir;
        } else if (std.mem.eql(u8, arg, "--slow")) {
            slow_mode = true;
        } else {
            const in_dir_path = std.fs.path.dirname(arg) orelse return error.InvalidInputPath;
            const in_filename = std.fs.path.basename(arg);
            const in_device_str = std.fs.path.basename(in_dir_path);
            const in_device_type = DeviceType.parse(in_device_str) orelse return error.InvalidDevice;

            const contents = try std.fs.cwd().readFileAlloc(pa, arg, 100_000_000);
            try input_files.put(pa, in_filename, .{
                .contents = contents,
                .filename = in_filename,
                .device_type = in_device_type,
            });
        }
    }

    var atf = try out_dir.atomicFile(out_filename, .{});
    defer atf.deinit();

    const writer = atf.file.writer();
    var sx_writer = sx.writer(pa, writer.any());
    defer sx_writer.deinit();

    var tc = try Toolchain.init(ta);
    defer tc.deinit(keep);

    const dev = DeviceInfo.init(device_type);
    try root.run(ta, pa, &tc, &dev, &sx_writer);

    var input_file_iter = input_files.iterator();
    while (input_file_iter.next()) |entry| {
        if (!entry.value_ptr.accessed) {
            try err("Unnecessary input file: {s}", .{ entry.key_ptr.* }, &dev, .{});
        }
    }

    try atf.finish();
}

var report_dir: ?*std.fs.Dir = null;
var jed_dir: ?*std.fs.Dir = null;

pub fn logResults(device_type: DeviceType, comptime name_fmt: []const u8, name_args: anytype, results: toolchain.FitResults) !void {
    if (report_dir) |dir| {
        const filename = try std.fmt.allocPrint(temp_alloc.allocator(), name_fmt ++ ".rpt", name_args);
        var f = try dir.createFile(filename, .{});
        defer f.close();

        try f.writer().writeAll(results.report);
    }
    if (jed_dir) |dir| {
        const filename = try std.fmt.allocPrint(temp_alloc.allocator(), name_fmt ++ ".jed", name_args);
        var f = try dir.createFile(filename, .{});
        defer f.close();

        const jed = lc4k.jedec.JedecFile {
            .data = results.jedec,
        };

        try lc4k.jed_file.write(device_type, temp_alloc.allocator(), jed, f.writer(), .{ .one_char = '.' });
    }
    if (slow_mode) {
        try std.io.getStdOut().writer().writeAll("Press enter to continue...\n");
        while ('\n' != std.io.getStdIn().reader().readByte() catch '\n') {}
    }
}

pub const ErrorContext = struct {
    mcref: ?MacrocellRef = null,
    glb: ?u8 = null,
    mc: ?u8 = null,
    pin: ?[]const u8 = null,
};
pub fn err(comptime fmt: []const u8, args: anytype, dev: *const DeviceInfo, context: ErrorContext) !void {
    const stderr = std.io.getStdErr().writer();

    if (context.mcref) |mcref| {
        try stderr.print("{s} glb{} ({s}) mc{}: ", .{ @tagName(dev.device), mcref.glb, getGlbName(mcref.glb), mcref.mc });
    } else if (context.glb) |glb| {
        if (context.mc) |mc| {
            try stderr.print("{s} glb{} ({s}) mc{}: ", .{ @tagName(dev.device), glb, getGlbName(glb), mc });
        } else {
            try stderr.print("{s} glb{} ({s}): ", .{ @tagName(dev.device), glb, getGlbName(glb) });
        }
    } else if (context.pin) |id| {
        try stderr.print("{s} pin {s}: ", .{ @tagName(dev.device), id });
    } else {
        try stderr.print("{s}: ", .{ @tagName(dev.device) });
    }

    try stderr.print(fmt ++ "\n", args);
}

pub const MacrocellIterator = struct {
    dev: *const DeviceInfo,
    _last: ?MacrocellRef = null,

    pub fn next(self: *MacrocellIterator) ?MacrocellRef {
        if (self._last) |*ref| {
            if (ref.mc + 1 < self.dev.num_mcs_per_glb) {
                ref.mc += 1;
                return ref.*;
            } else if (ref.glb + 1 < self.dev.num_glbs) {
                ref.glb += 1;
                ref.mc = 0;
                return ref.*;
            } else {
                return null;
            }
        } else {
            const ref = MacrocellRef {
                .glb = 0,
                .mc = 0,
            };
            self._last = ref;
            return ref;
        }
    }
};

pub const InputIterator = struct {
    pins: []const PinInfo,
    next_index: usize = 0,
    single_glb: ?u8 = null,
    exclude_glb: ?u8 = null,
    exclude_clocks: bool = false,
    exclude_oes: bool = false,
    exclude_pin: ?[]const u8 = null,

    pub fn next(self: *InputIterator) ?PinInfo {
        const len = self.pins.len;
        var i = self.next_index;
        while (i < len) : (i += 1) {
            const pin = self.pins[i];
            if (self.exclude_pin) |exclude| {
                if (std.mem.eql(u8, exclude, pin.id)) continue;
            }

            switch (pin.func) {
                .input, .clock, .io, .io_oe0, .io_oe1 => {
                    if (self.exclude_oes and (pin.func == .io_oe0 or pin.func == .io_oe1)) continue;
                    if (self.exclude_clocks and pin.func == .clock) continue;
                    if (self.single_glb) |glb| {
                        if (pin.glb.? != glb) continue;
                    }
                    if (self.exclude_glb) |glb| {
                        if (pin.glb.? == glb) continue;
                    }

                    self.next_index = i + 1;
                    return pin;
                },
                else => {},
            }
        }
        return null;
    }
};

pub const OutputIterator = struct {
    pins: []const PinInfo,
    next_index: u16 = 0,
    single_glb: ?u8 = null,
    exclude_glb: ?u8 = null,
    exclude_pin: ?[]const u8 = null,
    exclude_oes: bool = false,

    pub fn next(self: *OutputIterator) ?PinInfo {
        const len = self.pins.len;
        var i = self.next_index;
        while (i < len) : (i += 1) {
            const pin = self.pins[i];
            if (self.exclude_pin) |exclude| {
                if (std.mem.eql(u8, exclude, pin.id)) continue;
            }
            switch (pin.func) {
                .io, .io_oe0, .io_oe1 => {
                    if (self.exclude_oes and (pin.func == .io_oe0 or pin.func == .io_oe1)) continue;
                    if (self.single_glb) |glb| {
                        if (pin.glb.? != glb) continue;
                    }
                    if (self.exclude_glb) |glb| {
                        if (pin.glb.? == glb) continue;
                    }
                    self.next_index = i + 1;
                    return pin;
                },
                else => {},
            }
        }
        return null;
    }
};

pub fn extract(src: []const u8, prefix: []const u8, suffix: []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, src, prefix)) |prefix_start| {
        const remaining = src[prefix_start + prefix.len..];
        if (std.mem.indexOf(u8, remaining, suffix)) |suffix_start| {
            return remaining[0..suffix_start];
        }
    }
    return null;
}

pub fn writeGlb(writer: *sx.Writer, glb: GlbIndex) !void {
    try writer.expression("glb");
    try writer.int(glb, 10);
    try writer.expression("name");
    try writer.string(getGlbName(glb));
    try writer.close();
    writer.set_compact(false);
}

pub fn writeMc(writer: *sx.Writer, mc: MacrocellIndex) !void {
    try writer.expression("mc");
    try writer.int(mc, 10);
}

pub fn writePin(writer: *sx.Writer, pin_info: PinInfo) !void {
    try writer.expression("pin");
    try writer.string(pin_info.id);
    switch (pin_info.func) {
        .input => {
            try writer.expression("info");
            try writer.string("input");
            try writer.close();
            try writeGlb(writer, pin_info.glb.?);
            writer.set_compact(true);
            try writer.close();
        },
        .io, .io_oe0, .io_oe1 => |mc| {
            try writeGlb(writer, pin_info.glb.?);
            writer.set_compact(true);
            try writer.close();
            try writeMc(writer, mc);
            try writer.close();
            if (pin_info.func == .io_oe0) {
                try writer.expression("oe");
                try writer.int(0, 10);
                try writer.close();
            } else if (pin_info.func == .io_oe1) {
                try writer.expression("oe");
                try writer.int(1, 10);
                try writer.close();
            }
        },
        .clock => |clk_index| {
            try writer.expression("clk");
            try writer.int(clk_index, 10);
            try writer.close();
            try writeGlb(writer, pin_info.glb.?);
            writer.set_compact(true);
            try writer.close();
        },
        else => {
            try writer.expression("info");
            try writer.string(@tagName(pin_info.func));
            try writer.close();
        },
    }
}

pub fn writeValue(writer: *sx.Writer, value: usize, desc: anytype) !void {
    try writer.expression("value");
    try writer.int(value, 10);
    switch (@typeInfo(@TypeOf(desc))) {
        .Enum, .EnumLiteral => try writer.string(@tagName(desc)),
        .Pointer => try writer.string(desc),
        else => unreachable,
    }
    try writer.close();
}

pub fn writeFuse(writer: *sx.Writer, fuse: Fuse) !void {
    try writer.expression("fuse");
    try writer.int(fuse.row, 10);
    try writer.int(fuse.col, 10);
    try writer.close();
}

pub fn writeFuseValue(writer: *sx.Writer, fuse: Fuse, value: usize) !void {
    try writer.expression("fuse");
    try writer.int(fuse.row, 10);
    try writer.int(fuse.col, 10);
    try writer.expression("value");
    try writer.int(value, 10);
    try writer.close();
    try writer.close();
}

pub fn writeFuseOptValue(writer: *sx.Writer, fuse: Fuse, value: usize) !void {
    try writer.expression("fuse");
    try writer.int(fuse.row, 10);
    try writer.int(fuse.col, 10);
    if (value != 1) {
        try writer.expression("value");
        try writer.int(value, 10);
        try writer.close();
    }
    try writer.close();
}

pub fn parseGRP(ta: std.mem.Allocator, pa: std.mem.Allocator, out_device: ?*DeviceInfo) !std.AutoHashMap(Fuse, GlbInputSignal) {
    const input_file = getInputFile("grp.sx") orelse return error.MissingGRPInputFile;
    const dev = DeviceInfo.init(input_file.device_type);

    var results = std.AutoHashMap(Fuse, GlbInputSignal).init(pa);
    try results.ensureTotalCapacity(@intCast(dev.getGIRange(0, 0).count() * 36 * dev.num_glbs));

    var pin_number_to_info = std.StringHashMap(PinInfo).init(ta);
    defer pin_number_to_info.deinit();

    try pin_number_to_info.ensureTotalCapacity(@intCast(dev.all_pins.len));
    for (dev.all_pins) |pin| {
        try pin_number_to_info.put(pin.id, pin);
    }

    var stream = std.io.fixedBufferStream(input_file.contents);
    const reader = stream.reader();
    var parser = sx.reader(ta, reader.any());
    defer parser.deinit();

    parseGRP0(ta, &parser, &dev, &pin_number_to_info, &results) catch |e| switch (e) {
        error.SExpressionSyntaxError => {
            var ctx = try parser.token_context();
            try ctx.print_for_string(input_file.contents, std.io.getStdErr().writer(), 120);
            return e;
        },
        else => return e,
    };

    if (out_device) |ptr| {
        ptr.* = dev;
    }

    return results;
}

fn parseGRP0(
    ta: std.mem.Allocator,
    parser: *sx.Reader,
    dev: *const DeviceInfo,
    pin_number_to_info: *const std.StringHashMap(PinInfo),
    results: *std.AutoHashMap(Fuse, GlbInputSignal)
) !void {
    _ = try parser.require_any_expression(); // device name, we already know it
    try parser.require_expression("global_routing_pool");

    var temp = std.ArrayList(u8).init(ta);

    var glb: u8 = 0;
    while (glb < dev.num_glbs) : (glb += 1) {
        const parsed_glb = try requireGlb(parser);
        std.debug.assert(glb == parsed_glb);

        while (try parser.expression("gi")) {
            _ = try parser.require_any_int(usize, 10);

            while (try parser.expression("fuse")) {
                const row = try parser.require_any_int(u16, 10);
                const col = try parser.require_any_int(u16, 10);
                const fuse = Fuse.init(row, col);

                if (try parsePin(parser, &temp)) {
                    if (pin_number_to_info.get(temp.items)) |pin| {
                        try results.put(fuse, .{
                            .pin = pin.id,
                        });
                    } else {
                        try std.io.getStdErr().writer().print("Failed to lookup pin number: {s}\n", .{ temp.items });
                    }
                    try parser.require_close(); // pin
                } else if (try parseGlb(parser)) |fuse_glb| {
                    try parser.require_close(); // glb

                    try parser.require_expression("mc");
                    const fuse_mc = try parser.require_any_int(u8, 10);
                    try parser.require_close(); // mc

                    try results.put(fuse, .{
                        .fb = .{
                            .glb = fuse_glb,
                            .mc = fuse_mc,
                        },
                    });
                } else if (try parser.expression("unused")) {
                    try parser.ignore_remaining_expression();
                }
                try parser.require_close(); // fuse
            }
            try parser.require_close(); // gi
        }
        try parser.require_close(); // glb
    }
    try parser.require_close(); // global_routing_pool
    try parser.require_close(); // device
    try parser.require_done();
}

pub fn parseGlb(parser: *sx.Reader) !?lc4k.GlbIndex {
    if (try parser.expression("glb")) {
        const parsed_glb = try parser.require_any_int(u8, 10);
        if (try parser.expression("name")) {
            try parser.ignore_remaining_expression();
        }
        return parsed_glb;
    } else {
        return null;
    }
}
pub fn requireGlb(parser: *sx.Reader) !lc4k.GlbIndex {
    try parser.require_expression("glb");
    const parsed_glb = try parser.require_any_int(u8, 10);
    if (try parser.expression("name")) {
        try parser.ignore_remaining_expression();
    }
    return parsed_glb;
}

pub const FuseAndValue = struct {
    fuse: Fuse,
    value: usize,
};

pub fn parseFuseAndValue(parser: *sx.Reader) !?FuseAndValue {
    if (try parser.expression("fuse")) {
        const row = try parser.require_any_int(u16, 10);
        const col = try parser.require_any_int(u16, 10);

        var value: usize = 1;
        if (try parser.expression("value")) {
            value = try parser.require_any_int(usize, 10);
            try parser.require_close();
        }

        try parser.require_close(); // fuse

        return FuseAndValue {
            .fuse = Fuse.init(row, col),
            .value = value,
        };
    } else return null;
}

pub fn parseFusesAndValues(parser: *sx.Reader, alloc: std.mem.Allocator) ![]FuseAndValue {
    var temp: [32]FuseAndValue = undefined;
    var num_fuses: usize = 0;

    while (try parseFuseAndValue(parser)) |fuse_and_value| {
        if (num_fuses >= temp.len) return error.TooManyFuses;

        temp[num_fuses] = fuse_and_value;
        num_fuses += 1;
    }

    var slice: []FuseAndValue = &temp;
    slice.len = num_fuses;
    return alloc.dupe(FuseAndValue, slice);
}

pub fn parseFusesForOutputPins(ta: std.mem.Allocator, pa: std.mem.Allocator, input_filename: []const u8, section_name: []const u8, out_device: ?*DeviceInfo) !std.AutoHashMap(MacrocellRef, []const FuseAndValue) {
    const input_file = getInputFile(input_filename) orelse return error.MissingInvertInputFile;
    const dev = DeviceInfo.init(input_file.device_type);

    var results = std.AutoHashMap(MacrocellRef, []const FuseAndValue).init(pa);

    var stream = std.io.fixedBufferStream(input_file.contents);
    const reader = stream.reader();
    var parser = sx.reader(ta, reader.any());
    defer parser.deinit();

    parseFusesForOutputPins0(&parser, section_name, &results) catch |e| switch (e) {
        error.SExpressionSyntaxError => {
            var ctx = try parser.token_context();
            try ctx.print_for_string(input_file.contents, std.io.getStdErr().writer(), 120);
            return e;
        },
        else => return e,
    };

    if (out_device) |ptr| {
        ptr.* = dev;
    }

    return results;
}

fn parseFusesForOutputPins0(parser: *sx.Reader, section_name: []const u8, results: *std.AutoHashMap(MacrocellRef, []const FuseAndValue)) !void {
    _ = try parser.require_any_expression(); // device name, we already know it
    try parser.require_expression(section_name);

    while (try parser.expression("pin")) {
        var maybe_mcref: ?MacrocellRef = null;

        _ = try parser.require_any_string();

        if (try parser.expression("info")) {
            try parser.ignore_remaining_expression();
        }

        if (try parser.expression("clk")) {
            try parser.ignore_remaining_expression();
        }

        if (try parseGlb(parser)) |glb| {
            try parser.require_close();

            if (try parser.expression("mc")) {
                const mc = try parser.require_any_int(lc4k.MacrocellIndex, 10);
                try parser.require_close();

                maybe_mcref = MacrocellRef.init(glb, mc);
            }
        }

        if (try parser.expression("oe")) {
            try parser.ignore_remaining_expression();
        }

        const data = try parseFusesAndValues(parser, results.allocator);
        if (data.len == 0) {
            results.allocator.free(data);
        } else if (maybe_mcref) |mcref| {
            try results.put(mcref, data);
        } else {
            results.allocator.free(data);
        }

        try parser.require_close(); // pin
    }
    while (try parser.expression("value")) {
        try parser.ignore_remaining_expression();
    }
    try parser.require_close(); // section
    try parser.require_close(); // device
    try parser.require_done();
}

pub fn parseFusesForMacrocells(ta: std.mem.Allocator, pa: std.mem.Allocator, input_filename: []const u8, section_name: []const u8, out_device: ?*DeviceInfo) !std.AutoHashMap(MacrocellRef, []const FuseAndValue) {
    const input_file = getInputFile(input_filename) orelse return error.MissingInvertInputFile;
    const dev = DeviceInfo.init(input_file.device_type);

    var results = std.AutoHashMap(MacrocellRef, []const FuseAndValue).init(pa);

    var stream = std.io.fixedBufferStream(input_file.contents);
    var parser = sx.reader(ta, stream.reader());
    defer parser.deinit();

    parseFusesForMacrocells0(&parser, section_name, &results) catch |e| switch (e) {
        error.SExpressionSyntaxError => {
            var ctx = try parser.token_context();
            try ctx.print_for_string(input_file.contents, std.io.getStdErr().writer(), 120);
            return e;
        },
        else => return e,
    };

    if (out_device) |ptr| {
        ptr.* = dev;
    }

    return results;
}

fn parseFusesForMacrocells0(parser: *sx.Reader, section_name: []const u8, results: *std.AutoHashMap(MacrocellRef, []const FuseAndValue)) !void {
    _ = try parser.require_any_expression(); // device name, we already know it
    try parser.require_expression(section_name);

    while (try parseGlb(parser)) |glb| {
        if (try parser.expression("mc")) {
            const mc = try parser.require_any_int(lc4k.MacrocellIndex, 10);
            const mcref = MacrocellRef.init(glb, mc);

            const data = try parseFusesAndValues(parser, results.allocator);
            if (data.len == 0) {
                results.allocator.free(data);
            } else try results.put(mcref, data);

            try parser.require_close(); // mc
        }
        try parser.require_close(); // glb
    }
    while (try parser.expression("value")) {
        try parser.ignore_remaining_expression();
    }
    try parser.require_close(); // section
    try parser.require_close(); // device
    try parser.require_done();
}

pub fn parseMCOptionsColumns(ta: std.mem.Allocator, pa: std.mem.Allocator, out_device: ?*DeviceInfo) !std.AutoHashMap(MacrocellRef, FuseRange) {
    const input_file = getInputFile("invert.sx") orelse return error.MissingInvertInputFile;
    const dev = DeviceInfo.init(input_file.device_type);

    var results = std.AutoHashMap(MacrocellRef, FuseRange).init(pa);
    try results.ensureTotalCapacity(@intCast(dev.num_mcs));

    var stream = std.io.fixedBufferStream(input_file.contents);
    const reader = stream.reader();
    var parser = sx.reader(ta, reader.any());
    defer parser.deinit();

    parseMCOptionsColumns0(&parser, &dev, &results) catch |e| switch (e) {
        error.SExpressionSyntaxError => {
            var ctx = try parser.token_context();
            try ctx.print_for_string(input_file.contents, std.io.getStdErr().writer(), 120);
            return e;
        },
        else => return e,
    };

    if (out_device) |ptr| {
        ptr.* = dev;
    }

    return results;
}

fn parseMCOptionsColumns0(parser: *sx.Reader, dev: *const DeviceInfo, results: *std.AutoHashMap(MacrocellRef, FuseRange)) !void {
    _ = try parser.require_any_expression(); // device name, we already know it
    try parser.require_expression("invert");

    const options_range = dev.getOptionsRange();

    var glb: u8 = 0;
    while (glb < dev.num_glbs) : (glb += 1) {
        const parsed_glb = try requireGlb(parser);
        std.debug.assert(glb == parsed_glb);

        while (try parser.expression("mc")) {
            const mc = try parser.require_any_int(MacrocellIndex, 10);

            try parser.require_expression("fuse");
            _ = try parser.require_any_int(usize, 10);
            const col = try parser.require_any_int(usize, 10);

            var col_range = dev.getColumnRange(col, col);
            const opt_range = col_range.intersection(options_range);
            try results.put(.{ .glb = glb, .mc = mc }, opt_range);

            try parser.require_close(); // fuse
            try parser.require_close(); // mc
        }
        try parser.require_close(); // glb
    }
    while (try parser.expression("value")) {
        try parser.ignore_remaining_expression();
    }
    try parser.require_close(); // invert_sum
    try parser.require_close(); // device
    try parser.require_done();
}

pub fn parseORMRows(ta: std.mem.Allocator, pa: std.mem.Allocator, out_device: ?*DeviceInfo) !std.DynamicBitSet {
    const input_file = getInputFile("output_routing.sx") orelse return error.MissingORMInputFile;
    const dev = DeviceInfo.init(input_file.device_type);

    var results = try std.DynamicBitSet.initEmpty(pa, dev.jedec_dimensions.height());

    var stream = std.io.fixedBufferStream(input_file.contents);
    const reader = stream.reader();
    var parser = sx.reader(ta, reader.any());
    defer parser.deinit();

    parseORMRows0(&parser, &results) catch |e| switch (e) {
        error.SExpressionSyntaxError => {
            var ctx = try parser.token_context();
            try ctx.print_for_string(input_file.contents, std.io.getStdErr().writer(), 120);
            return e;
        },
        else => return e,
    };

    if (out_device) |ptr| {
        ptr.* = dev;
    }

    return results;
}

fn parseORMRows0(parser: *sx.Reader, results: *std.DynamicBitSet) !void {
    _ = try parser.require_any_expression(); // device name, we already know it
    try parser.require_expression("output_routing");

    while (try parsePin(parser, null)) {
        while (try parser.expression("fuse")) {
            const row = try parser.require_any_int(u16, 10);
            _ = try parser.require_any_int(u16, 10);

            if (try parser.expression("value")) {
                try parser.ignore_remaining_expression();
            }

            results.set(row);

            try parser.require_close(); // fuse
        }
        try parser.require_close(); // pin
    }
    while (try parser.expression("value")) {
        try parser.ignore_remaining_expression();
    }
    try parser.require_close(); // invert_sum
    try parser.require_close(); // device
    try parser.require_done();
}

pub fn parsePin(parser: *sx.Reader, out: ?*std.ArrayList(u8)) !bool {
    if (try parser.expression("pin")) {
        const pin_id = try parser.require_any_string();
        if (out) |o| {
            o.clearRetainingCapacity();
            try o.appendSlice(pin_id);
        }

        if (try parser.expression("info")) {
            try parser.ignore_remaining_expression();
        }

        if (try parser.expression("clk")) {
            try parser.ignore_remaining_expression();
        }

        if (try parser.expression("glb")) {
            try parser.ignore_remaining_expression();
        }

        if (try parser.expression("mc")) {
            try parser.ignore_remaining_expression();
        }

        if (try parser.expression("oe")) {
            try parser.ignore_remaining_expression();
        }

        return true;
    } else {
        return false;
    }
}

pub fn parseSharedPTClockPolarityFuses(ta: std.mem.Allocator, pa: std.mem.Allocator, dev: *const DeviceInfo) ![]Fuse {
    const input_file = getInputFile("shared_pt_clk_polarity.sx") orelse return error.MissingSharedPtClkPolarityInputFile;
    if (input_file.device_type != dev.device) return error.InputFileDeviceMismatch;

    const results = try pa.alloc(Fuse, dev.num_glbs);

    var stream = std.io.fixedBufferStream(input_file.contents);
    const reader = stream.reader();
    var parser = sx.reader(ta, reader.any());
    defer parser.deinit();

    parseSharedPTClockPolarityFuses0(&parser, results) catch |e| switch (e) {
        error.SExpressionSyntaxError => {
            var ctx = try parser.token_context();
            try ctx.print_for_string(input_file.contents, std.io.getStdErr().writer(), 120);
            return e;
        },
        else => return e,
    };

    return results;
}

fn parseSharedPTClockPolarityFuses0(parser: *sx.Reader, results: []Fuse) !void {
    _ = try parser.require_any_expression(); // device name, we already know it
    try parser.require_expression("shared_pt_clk_polarity");

    while (try parseGlb(parser)) |glb| {
        try parser.require_expression("fuse");
        const row = try parser.require_any_int(u16, 10);
        const col = try parser.require_any_int(u16, 10);
        results[glb] = Fuse.init(row, col);
        try parser.require_close(); // fuse

        try parser.require_close(); // glb
    }
    while (try parser.expression("value")) {
        try parser.ignore_remaining_expression();
    }
    try parser.require_close(); // shared_pt_clk_polarity
    try parser.require_close(); // device
    try parser.require_done();
}
