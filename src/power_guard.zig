const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const core = @import("core.zig");
const jedec = @import("jedec.zig");
const devices = @import("devices.zig");
const JedecData = jedec.JedecData;
const Fuse = jedec.Fuse;
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

pub fn main() void {
    helper.main(0);
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, pin_index: u16, pg_enabled: bool) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    try design.nodeAssignment(.{
        .signal = "pg_enable",
    });
    try design.addPT("pg_enable_pin", "pg_enable");

    if (pg_enabled) {
        try design.pinAssignment(.{
            .signal = "in",
            .pin_index = pin_index,
            .power_guard_signal = "pg_enable",
        });
    } else {
        try design.pinAssignment(.{
            .signal = "in",
            .pin_index = pin_index,
        });
    }

    var glb: u8 = 0;
    while (glb < dev.getNumGlbs()) : (glb += 1) {
        var iter = devices.pins.InputIterator {
            .pins = dev.getPins(),
            .single_glb = glb,
            .exclude_pin = pin_index,
        };

        const signal_name = try std.fmt.allocPrint(ta, "temp{}", .{ glb });
        try design.pinAssignment(.{
            .signal = signal_name,
            .pin_index = iter.next().?.pin_index(),
            .power_guard_signal = "pg_enable",
        });

        if (glb == 0) {
            try design.pinAssignment(.{
                .signal = "pg_enable_pin",
                .pin_index = iter.next().?.pin_index(),
            });
        }
    }

    var results = try tc.runToolchain(design);
    try helper.logResults("power_guard_pin_{s}_{}", .{ dev.getPins()[pin_index].pin_number(), pg_enabled }, results);
    try results.checkTerm();
    return results;
}

var default_enabled: ?u1 = null;
var default_disabled: ?u1 = null;

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("power_guard");

    var pin_iter = devices.pins.InputIterator { .pins = dev.getPins() };
    while (pin_iter.next()) |pin_info| {
        const pin_index = pin_info.pin_index();
        const pin_number = pin_info.pin_number();

        try tc.cleanTempDir();
        helper.resetTemp();

        const results_enabled = try runToolchain(ta, tc, dev, pin_index, true);
        const results_disabled = try runToolchain(ta, tc, dev, pin_index, false);

        const diff = try JedecData.initDiff(ta, results_enabled.jedec, results_disabled.jedec);

        try writer.expression("pin");
        try writer.printRaw("{s}", .{ pin_number });

        var diff_iter = diff.iterator(.{});
        if (diff_iter.next()) |fuse| {
            try writeFuse(fuse, results_enabled.jedec, results_disabled.jedec, writer);
        } else if (pin_index == 88 and dev == .LC4128ZE_TQFP100) {
            // The report generated looks correct for this bit, but it doesn't actually set any bit in the jed.
            // In the other packages, CLK0's PGDF bit is 87:98, and that fuse is suspiciously missing
            // for this device, so we're going to assume this is just a bug in the fitter.
            try helper.writeFuse(writer, Fuse.init(87, 98));
        } else {
            try helper.err("Expected one power guard fuse but found none!", .{}, dev, .{ .pin_index = pin_index });
        }

        if (diff_iter.next()) |fuse| {
            try helper.err("Expected one power guard fuse but found multiple!", .{}, dev, .{ .pin_index = pin_index });
            try writeFuse(fuse, results_enabled.jedec, results_disabled.jedec, writer);

            while (diff_iter.next()) |f| {
                try writeFuse(f, results_enabled.jedec, results_disabled.jedec, writer);
            }
        }

        try writer.close();
    }

    if (default_enabled) |def| {
        try writer.expression("value");
        try writer.printRaw("{} enabled", .{ def });
        try writer.close();
    }

    if (default_disabled) |def| {
        try writer.expression("value");
        try writer.printRaw("{} disabled", .{ def });
        try writer.close();
    }

    try writer.done();

    _ = pa;
}

fn writeFuse(fuse: Fuse, results_enabled: JedecData, results_disabled: JedecData, writer: anytype) !void {
    try helper.writeFuse(writer, fuse);

    const enabled_value = results_enabled.get(fuse);
    if (default_enabled) |def| {
        if (enabled_value != def) {
            try writer.expression("value");
            try writer.printRaw("{} enabled", .{ enabled_value });
            try writer.close();
        }
    } else {
        default_enabled = enabled_value;
    }

    const disabled_value = results_disabled.get(fuse);
    if (default_disabled) |def| {
        if (disabled_value != def) {
            try writer.expression("value");
            try writer.printRaw("{} disabled", .{ disabled_value });
            try writer.close();
        }
    } else {
        default_disabled = disabled_value;
    }
}
