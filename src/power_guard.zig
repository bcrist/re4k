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
const InputIterator = helper.InputIterator;

pub fn main() void {
    helper.main(0);
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, pin: common.PinInfo, pg_enabled: bool) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    try design.nodeAssignment(.{
        .signal = "pg_enable",
    });
    try design.addPT("pg_enable_pin", "pg_enable");

    if (pg_enabled) {
        try design.pinAssignment(.{
            .signal = "in",
            .pin = pin.id,
            .power_guard_signal = "pg_enable",
        });
    } else {
        try design.pinAssignment(.{
            .signal = "in",
            .pin = pin.id,
        });
    }

    var glb: u8 = 0;
    while (glb < dev.num_glbs) : (glb += 1) {
        var iter = InputIterator {
            .pins = dev.all_pins,
            .single_glb = glb,
            .exclude_pin = pin.id,
        };

        const signal_name = try std.fmt.allocPrint(ta, "temp{}", .{ glb });
        try design.pinAssignment(.{
            .signal = signal_name,
            .pin = iter.next().?.id,
            .power_guard_signal = "pg_enable",
        });

        if (glb == 0) {
            try design.pinAssignment(.{
                .signal = "pg_enable_pin",
                .pin = iter.next().?.id,
            });
        }
    }

    var results = try tc.runToolchain(design);
    try helper.logResults("power_guard_pin_{s}_{}", .{ pin.id, pg_enabled }, results);
    try results.checkTerm();
    return results;
}

var default_enabled: ?u1 = null;
var default_disabled: ?u1 = null;

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev.device));
    try writer.expressionExpanded("power_guard");

    var pin_iter = InputIterator { .pins = dev.all_pins };
    while (pin_iter.next()) |pin| {
        try tc.cleanTempDir();
        helper.resetTemp();

        const results_enabled = try runToolchain(ta, tc, dev, pin, true);
        const results_disabled = try runToolchain(ta, tc, dev, pin, false);

        const diff = try JedecData.initDiff(ta, results_enabled.jedec, results_disabled.jedec);

        try helper.writePin(writer, pin);

        var diff_iter = diff.iterator(.{});
        if (diff_iter.next()) |fuse| {
            try writeFuse(fuse, results_enabled.jedec, results_disabled.jedec, writer);
        } else if (dev.device == .LC4128ZE_TQFP100 and std.mem.eql(u8, pin.id, "89")) {
            // The report generated looks correct for this bit, but it doesn't actually set any bit in the jed.
            // In the other packages, CLK0's PGDF bit is 87:98, and that fuse is suspiciously missing
            // for this device, so we're going to assume this is just a bug in the fitter.
            try helper.writeFuse(writer, Fuse.init(87, 98));
        } else {
            try helper.err("Expected one power guard fuse but found none!", .{}, dev, .{ .pin = pin.id });
        }

        if (diff_iter.next()) |fuse| {
            try helper.err("Expected one power guard fuse but found multiple!", .{}, dev, .{ .pin = pin.id });
            try writeFuse(fuse, results_enabled.jedec, results_disabled.jedec, writer);

            while (diff_iter.next()) |f| {
                try writeFuse(f, results_enabled.jedec, results_disabled.jedec, writer);
            }
        }

        try writer.close();
    }

    if (default_enabled) |def| {
        try helper.writeValue(writer, def, "enabled");
    }

    if (default_disabled) |def| {
        try helper.writeValue(writer, def, "disabled");
    }

    try writer.done();

    _ = pa;
}

fn writeFuse(fuse: Fuse, results_enabled: JedecData, results_disabled: JedecData, writer: anytype) !void {
    try helper.writeFuse(writer, fuse);

    const enabled_value = results_enabled.get(fuse);
    if (default_enabled) |def| {
        if (enabled_value != def) {
            try helper.writeValue(writer, enabled_value, "enabled");
        }
    } else {
        default_enabled = enabled_value;
    }

    const disabled_value = results_disabled.get(fuse);
    if (default_disabled) |def| {
        if (disabled_value != def) {
            try helper.writeValue(writer, disabled_value, "disabled");
        }
    } else {
        default_disabled = disabled_value;
    }
}
