const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const common = @import("common");
const jedec = @import("jedec");
const device_info = @import("device_info.zig");
const JedecData = jedec.JedecData;
const Fuse = jedec.Fuse;
const DeviceInfo = device_info.DeviceInfo;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const LogicLevels = toolchain.LogicLevels;

pub fn main() void {
    helper.main(0);
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, pin: common.PinInfo, iostd: LogicLevels) !toolchain.FitResults {
    var design = Design.init(ta, dev);
    try design.pinAssignment(.{
        .signal = "in",
        .pin = pin.id,
        .iostd = iostd,
    });
    try design.addPT("in", "out");

    var results = try tc.runToolchain(design);
    try helper.logResults(dev.device, "threshold_pin_{s}", .{ pin.id }, results);
    try results.checkTerm();
    return results;
}

var default_high: ?u1 = null;
var default_low: ?u1 = null;

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev.device));
    try writer.expressionExpanded("input_threshold");

    var pin_iter = helper.InputIterator { .pins = dev.all_pins };
    while (pin_iter.next()) |pin| {
        try tc.cleanTempDir();
        helper.resetTemp();

        const results_high = try runToolchain(ta, tc, dev, pin, .LVCMOS33);
        const results_low = try runToolchain(ta, tc, dev, pin, .LVCMOS15);

        const diff = try JedecData.initDiff(ta, results_high.jedec, results_low.jedec);

        try helper.writePin(writer, pin);

        var diff_iter = diff.iterator(.{});
        if (diff_iter.next()) |fuse| {
            if (dev.device != .LC4064ZC_csBGA56 or fuse.row != 99 or fuse.col != 159 or !std.mem.eql(u8, pin.id, "E1")) {
                // workaround for fitter bug, see readme.md
                try writeFuse(fuse, results_high.jedec, results_low.jedec, writer);
            }
        } else if (dev.device == .LC4064ZC_csBGA56 and std.mem.eql(u8, pin.id, "F8")) {
            // workaround for fitter bug, see readme.md
            try helper.writeFuse(writer, Fuse.init(99, 159));
        } else {
            try helper.err("Expected one threshold fuse but found none!", .{}, dev, .{ .pin = pin.id });
        }

        if (dev.device == .LC4064ZC_csBGA56 and std.mem.eql(u8, pin.id, "E1")) {
            // workaround for fitter bug, see readme.md
            _ = diff_iter.next();
        }

        if (diff_iter.next()) |fuse| {
            try helper.err("Expected one threshold fuse but found multiple!", .{}, dev, .{ .pin = pin.id });
            try writeFuse(fuse, results_high.jedec, results_low.jedec, writer);

            while (diff_iter.next()) |f| {
                try writeFuse(f, results_high.jedec, results_low.jedec, writer);
            }
        }

        try writer.close();
    }

    if (default_high) |def| {
        try helper.writeValue(writer, def, "high");
    }

    if (default_low) |def| {
        try helper.writeValue(writer, def, "low");
    }

    try writer.done();

    _ = pa;
}

fn writeFuse(fuse: Fuse, results_high: JedecData, results_low: JedecData, writer: anytype) !void {
    try helper.writeFuse(writer, fuse);

    const high_value = results_high.get(fuse);
    if (default_high) |def| {
        if (high_value != def) {
            try helper.writeValue(writer, high_value, "high");
        }
    } else {
        default_high = high_value;
    }

    const low_value = results_low.get(fuse);
    if (default_low) |def| {
        if (low_value != def) {
            try helper.writeValue(writer, low_value, "low");
        }
    } else {
        default_low = low_value;
    }
}
