const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const jedec = @import("jedec");
const common = @import("common");
const device_info = @import("device_info.zig");
const DeviceInfo = device_info.DeviceInfo;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JedecData = jedec.JedecData;

pub fn main() void {
    helper.main(0);
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, pin: common.PinInfo, slew: common.SlewRate) !toolchain.FitResults {
    var design = Design.init(ta, dev);
    try design.pinAssignment(.{
        .signal = "out",
        .pin = pin.id,
        .slew_rate = slew,
    });
    try design.addPT("in", "out");

    var results = try tc.runToolchain(design);
    try helper.logResults("slew_pin_{s}", .{ pin.id }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev.device));
    try writer.expressionExpanded("slew_rate");

    var default_slow: ?u1 = null;
    var default_fast: ?u1 = null;

    var pin_iter = helper.OutputIterator { .pins = dev.all_pins };
    while (pin_iter.next()) |pin| {
        try tc.cleanTempDir();
        helper.resetTemp();

        const results_slow = try runToolchain(ta, tc, dev, pin, .slow);
        const results_fast = try runToolchain(ta, tc, dev, pin, .fast);

        const diff = try JedecData.initDiff(ta, results_slow.jedec, results_fast.jedec);

        try helper.writePin(writer, pin);

        var diff_iter = diff.iterator(.{});
        if (diff_iter.next()) |fuse| {
            try helper.writeFuse(writer, fuse);

            const slow_value = results_slow.jedec.get(fuse);
            if (default_slow) |def| {
                if (slow_value != def) {
                    try helper.writeValue(writer, slow_value, "slow");
                }
            } else {
                default_slow = slow_value;
            }

            const fast_value = results_fast.jedec.get(fuse);
            if (default_fast) |def| {
                if (fast_value != def) {
                    try helper.writeValue(writer, fast_value, "fast");
                }
            } else {
                default_fast = fast_value;
            }

        } else {
            try helper.err("Expected one slew fuse but found none!", .{}, dev, .{ .pin = pin.id });
            return error.Think;
        }

        if (diff_iter.next()) |_| {
            try helper.err("Expected one slew fuse but found multiple!", .{}, dev, .{ .pin = pin.id });
            return error.Think;
        }

        try writer.close();
    }

    if (default_slow) |def| {
        try helper.writeValue(writer, def, "slow");
    }

    if (default_fast) |def| {
        try helper.writeValue(writer, def, "fast");
    }

    try writer.done();

    _ = pa;
}
