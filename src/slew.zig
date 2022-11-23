const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const jedec = @import("jedec.zig");
const core = @import("core.zig");
const devices = @import("devices.zig");
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JedecData = jedec.JedecData;

pub fn main() void {
    helper.main(0);
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, pin_index: u16, slew: core.SlewRate) !toolchain.FitResults {
    var design = Design.init(ta, dev);
    try design.pinAssignment(.{
        .signal = "out",
        .pin_index = pin_index,
        .slew_rate = slew,
    });
    try design.addPT("in", "out");

    var results = try tc.runToolchain(design);
    try helper.logResults("slew_pin_{s}", .{ dev.getPins()[pin_index].pin_number() }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("slew_rate");

    var default_slow: ?u1 = null;
    var default_fast: ?u1 = null;

    var pin_iter = devices.pins.OutputIterator { .pins = dev.getPins() };
    while (pin_iter.next()) |io| {
        try tc.cleanTempDir();
        helper.resetTemp();

        const results_slow = try runToolchain(ta, tc, dev, io.pin_index, .slow);
        const results_fast = try runToolchain(ta, tc, dev, io.pin_index, .fast);

        const diff = try JedecData.initDiff(ta, results_slow.jedec, results_fast.jedec);

        try helper.writePin(writer, io);

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
            try helper.err("Expected one slew fuse but found none!", .{}, dev, .{ .pin_index = io.pin_index });
            return error.Think;
        }

        if (diff_iter.next()) |_| {
            try helper.err("Expected one slew fuse but found multiple!", .{}, dev, .{ .pin_index = io.pin_index });
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
