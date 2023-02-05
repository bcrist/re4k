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

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, mcref: common.MacrocellRef, xor: bool) !toolchain.FitResults {
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
    try helper.logResults(dev.device, "pt0_xor_glb{}_mc{}_{}", .{ mcref.glb, mcref.mc, xor }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev.device));
    try writer.expressionExpanded("pt0_xor");

    var default_disabled: ?u1 = null;
    var default_enabled: ?u1 = null;

    var mc_iter = helper.MacrocellIterator { .dev = dev };
    while (mc_iter.next()) |mcref| {
        try tc.cleanTempDir();
        helper.resetTemp();

        const results_disabled = try runToolchain(ta, tc, dev, mcref, false);
        const results_enabled = try runToolchain(ta, tc, dev, mcref, true);

        var diff = try JedecData.initDiff(ta, results_disabled.jedec, results_enabled.jedec);

        diff.putRange(dev.getRoutingRange(), 0);

        if (mcref.mc == 0) {
            try helper.writeGlb(writer, mcref.glb);
        }

        try helper.writeMc(writer, mcref.mc);

        var diff_iter = diff.iterator(.{});
        if (diff_iter.next()) |fuse| {
            try helper.writeFuse(writer, fuse);

            const disabled_value = results_disabled.jedec.get(fuse);
            if (default_disabled) |def| {
                if (disabled_value != def) {
                    try helper.writeValue(writer, disabled_value, "disabled");
                }
            } else {
                default_disabled = disabled_value;
            }

            const enabled_value = results_enabled.jedec.get(fuse);
            if (default_enabled) |def| {
                if (enabled_value != def) {
                    try helper.writeValue(writer, enabled_value, "enabled");
                }
            } else {
                default_enabled = enabled_value;
            }

        } else {
            try helper.err("Expected one pt0_xor fuse but found none!", .{}, dev, .{ .mcref = mcref });
        }

        while (diff_iter.next()) |fuse| {
            try helper.err("Expected one pt0_xor fuse but found multiple: {}:{}", .{ fuse.row, fuse.col }, dev, .{ .mcref = mcref });
        }

        try writer.close();

        if (mcref.mc == 15) {
            try writer.close();
        }
    }

    if (default_disabled) |def| {
        try helper.writeValue(writer, def, "disabled");
    }

    if (default_enabled) |def| {
        try helper.writeValue(writer, def, "enabled");
    }

    try writer.done();

    _ = pa;
}
