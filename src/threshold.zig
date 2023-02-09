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
const MacrocellRef = common.MacrocellRef;

pub fn main() void {
    helper.main();
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
    var maybe_fallback_output_fuse_map: ?std.AutoHashMap(MacrocellRef, []const helper.FuseAndValue) = null;
    var fallback_output_fuse_data = try JedecData.initEmpty(pa, dev.jedec_dimensions);
    if (helper.getInputFile("threshold.sx")) |_| {
        const map = try helper.parseFusesForOutputPins(ta, pa, "threshold.sx", "input_threshold", null);
        var iter = map.iterator();
        while (iter.next()) |fuses| {
            for (fuses.value_ptr.*) |fuseAndValue| {
                fallback_output_fuse_data.put(fuseAndValue.fuse, 1);
            }
        }
        maybe_fallback_output_fuse_map = map;
    }

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
        if (diff_iter.next()) |fuse1| {
            if (diff_iter.next()) |fuse2| {
                const fuse1_is_macrocell = fallback_output_fuse_data.isSet(fuse1);
                const fuse2_is_macrocell = fallback_output_fuse_data.isSet(fuse2);

                if (fuse1_is_macrocell and !fuse2_is_macrocell) {
                    try writeFuse(fuse2, results_high.jedec, results_low.jedec, writer);
                    while (diff_iter.next()) |f| {
                        try helper.err("Expected one threshold fuse but found multiple!", .{}, dev, .{ .pin = pin.id });
                        try writeFuse(f, results_high.jedec, results_low.jedec, writer);
                    }
                } else if (fuse2_is_macrocell and !fuse1_is_macrocell) {
                    try writeFuse(fuse1, results_high.jedec, results_low.jedec, writer);
                    while (diff_iter.next()) |f| {
                        try helper.err("Expected one threshold fuse but found multiple!", .{}, dev, .{ .pin = pin.id });
                        try writeFuse(f, results_high.jedec, results_low.jedec, writer);
                    }
                } else {
                    try helper.err("Expected one threshold fuse but found multiple!", .{}, dev, .{ .pin = pin.id });
                    try writeFuse(fuse1, results_high.jedec, results_low.jedec, writer);
                    try writeFuse(fuse2, results_high.jedec, results_low.jedec, writer);

                    while (diff_iter.next()) |f| {
                        try writeFuse(f, results_high.jedec, results_low.jedec, writer);
                    }
                }
            } else {
                try writeFuse(fuse1, results_high.jedec, results_low.jedec, writer);
            }
        } else if (maybe_fallback_output_fuse_map) |fallback| {
            if (pin.mcRef()) |mcref| {
                if (fallback.get(mcref)) |fuses| {
                    for (fuses) |fuseAndValue| {
                        // workaround for fitter bug, see readme.md
                        try helper.writeFuse(writer, fuseAndValue.fuse);
                    }
                } else {
                    try helper.err("Expected one threshold fuse but found none!", .{}, dev, .{ .pin = pin.id });
                }
            } else {
                try helper.err("Expected one threshold fuse but found none!", .{}, dev, .{ .pin = pin.id });
            }
        } else {
            try helper.err("Expected one threshold fuse but found none!", .{}, dev, .{ .pin = pin.id });
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
