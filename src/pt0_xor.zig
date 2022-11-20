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

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, mcref: core.MacrocellRef, xor: bool) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    try design.pinAssignment(.{
        .signal = "x0",
    });
    try design.pinAssignment(.{
        .signal = "x1",
    });
    try design.pinAssignment(.{
        .signal = "x2",
    });
    try design.pinAssignment(.{
        .signal = "x3",
    });
    try design.pinAssignment(.{
        .signal = "x4",
    });

    var mc: u8 = 0;
    while (mc < mcref.mc) : (mc += 1) {
        var signal_name = try std.fmt.allocPrint(ta, "dum{}", .{ mc });
        try design.nodeAssignment(.{
            .signal = signal_name,
            .glb = mcref.glb,
            .mc = mc,
        });
        try design.addPT("x0", signal_name);
        try design.addPT("x1", signal_name);
        try design.addPT("x2", signal_name);
        try design.addPT("x3", signal_name);
        try design.addPT("x4", signal_name);
    }

    try design.nodeAssignment(.{
        .signal = "out",
        .glb = mcref.glb,
        .mc = mcref.mc,
    });
    try design.addPT("x0", "out.D");
    if (!xor) {
        try design.addPT("x1", "out.D");
    }

    var results = try tc.runToolchain(design);
    try helper.logReport("pt0_xor_glb{}_mc{}_{}", .{ mcref.glb, mcref.mc, xor }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("pt0_xor_sum");

    var default_disabled: ?u1 = null;
    var default_enabled: ?u1 = null;

    var mc_iter = core.MacrocellIterator { .device = dev };
    while (mc_iter.next()) |mcref| {
        try tc.cleanTempDir();
        helper.resetTemp();

        const results_disabled = try runToolchain(ta, tc, dev, mcref, false);
        const results_enabled = try runToolchain(ta, tc, dev, mcref, true);

        var diff = try JedecData.initDiff(ta, results_disabled.jedec, results_enabled.jedec);

        diff.putRange(dev.getRoutingRange(), 0);

        if (mcref.mc == 0) {
            try writer.expression("glb");
            try writer.printRaw("{}", .{ mcref.glb });
            try writer.expression("name");
            try writer.printRaw("{s}", .{ devices.getGlbName(mcref.glb) });
            try writer.close();

            writer.setCompact(false);
        }

        try writer.expression("mc");
        try writer.printRaw("{}", .{ mcref.mc });

        var diff_iter = diff.iterator(.{});
        if (diff_iter.next()) |fuse| {
            try helper.writeFuse(writer, fuse);

            const disabled_value = results_disabled.jedec.get(fuse);
            if (default_disabled) |def| {
                if (disabled_value != def) {
                    try writer.expression("value");
                    try writer.printRaw("{} disabled", .{ disabled_value });
                    try writer.close();
                }
            } else {
                default_disabled = disabled_value;
            }

            const enabled_value = results_enabled.jedec.get(fuse);
            if (default_enabled) |def| {
                if (enabled_value != def) {
                    try writer.expression("value");
                    try writer.printRaw("{} enabled", .{ enabled_value });
                    try writer.close();
                }
            } else {
                default_enabled = enabled_value;
            }

        } else {
            try helper.err("Expected one xor fuse but found none!", .{}, dev, .{ .mcref = mcref });
        }

        while (diff_iter.next()) |fuse| {
            try helper.err("Expected one xor fuse but found multiple: {}:{}", .{ fuse.row, fuse.col }, dev, .{ .mcref = mcref });
        }

        try writer.close();

        if (mcref.mc == 15) {
            try writer.close();
        }
    }

    if (default_disabled) |def| {
        try writer.expression("value");
        try writer.printRaw("{} disabled", .{ def });
        try writer.close();
    }

    if (default_enabled) |def| {
        try writer.expression("value");
        try writer.printRaw("{} enabled", .{ def });
        try writer.close();
    }

    try writer.done();

    _ = pa;
}
