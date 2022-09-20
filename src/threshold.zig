const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx.zig");
const core = @import("core.zig");
const jedec = @import("jedec.zig");
const devices = @import("devices.zig");
const JedecData = jedec.JedecData;
const Fuse = jedec.Fuse;
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

pub fn main() void {
    helper.main();
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, pin_index: u16, iostd: core.LogicLevels) !toolchain.FitResults {
    var design = Design.init(ta, dev);
    try design.pinAssignment(.{
        .signal = "in",
        .pin_index = pin_index,
        .iostd = iostd,
    });
    try design.addPT("in", "out");

    var results = try tc.runToolchain(design);
    try helper.logReport("threshold_pin_{s}", .{ dev.getPins()[pin_index].pin_number() }, results);
    try results.checkTerm(false);
    return results;
}

var default_high: ?u1 = null;
var default_low: ?u1 = null;

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("input_threshold");

    var pin_iter = devices.pins.InputIterator { .pins = dev.getPins() };
    while (pin_iter.next()) |pin_info| {
        const pin_index = pin_info.pin_index();
        const pin_number = pin_info.pin_number();

        try tc.cleanTempDir();
        helper.resetTemp();

        const results_high = try runToolchain(ta, tc, dev, pin_index, .LVCMOS33);
        const results_low = try runToolchain(ta, tc, dev, pin_index, .LVCMOS15);

        const diff = try JedecData.initDiff(ta, results_high.jedec, results_low.jedec);

        try writer.expression("pin");
        try writer.printRaw("{s}", .{ pin_number });

        var diff_iter = diff.iterator(.{});
        if (diff_iter.next()) |fuse| {
            try writeFuse(fuse, results_high.jedec, results_low.jedec, writer);
        } else {
            try helper.err("Expected one threshold fuse but found none!", .{}, dev, .{ .pin_index = pin_index });
        }

        if (diff_iter.next()) |fuse| {
            try helper.err("Expected one threshold fuse but found multiple!", .{}, dev, .{ .pin_index = pin_index });
            try writeFuse(fuse, results_high.jedec, results_low.jedec, writer);

            while (diff_iter.next()) |f| {
                try writeFuse(f, results_high.jedec, results_low.jedec, writer);
            }
        }

        try writer.close();
    }

    if (default_high) |def| {
        try writer.expression("value");
        try writer.printRaw("{} high", .{ def });
        try writer.close();
    }

    if (default_low) |def| {
        try writer.expression("value");
        try writer.printRaw("{} low", .{ def });
        try writer.close();
    }

    try writer.done();

    _ = pa;
}

fn writeFuse(fuse: Fuse, results_high: JedecData, results_low: JedecData, writer: anytype) !void {
    try helper.writeFuse(writer, fuse);

    const high_value = results_high.get(fuse);
    if (default_high) |def| {
        if (high_value != def) {
            try writer.expression("value");
            try writer.printRaw("{} high", .{ high_value });
            try writer.close();
        }
    } else {
        default_high = high_value;
    }

    const low_value = results_low.get(fuse);
    if (default_low) |def| {
        if (low_value != def) {
            try writer.expression("value");
            try writer.printRaw("{} low", .{ low_value });
            try writer.close();
        }
    } else {
        default_low = low_value;
    }
}
