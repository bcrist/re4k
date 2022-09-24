const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx.zig");
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

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, mcref: core.MacrocellRef, invert: bool) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    try design.pinAssignment(.{
        .signal = "in",
    });
    try design.nodeAssignment(.{
        .signal = "out",
        .glb = mcref.glb,
        .mc = mcref.mc,
    });
    if (invert) {
        try design.addPT("in", "out.D-");
    } else {
        try design.addPT("in", "out.D");
    }

    var results = try tc.runToolchain(design);
    try helper.logReport("invert_glb{}_mc{}_{}", .{ mcref.glb, mcref.mc, invert }, results);
    try results.checkTerm(true);
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("invert_sum");

    var default_normal: ?u1 = null;
    var default_invert: ?u1 = null;

    var mc_iter = core.MacrocellIterator { .device = dev };
    while (mc_iter.next()) |mcref| {
        try tc.cleanTempDir();
        helper.resetTemp();

        const results_normal = try runToolchain(ta, tc, dev, mcref, false);
        const results_invert = try runToolchain(ta, tc, dev, mcref, true);

        const diff = try JedecData.initDiff(ta, results_normal.jedec, results_invert.jedec);

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

            const normal_value = results_normal.jedec.get(fuse);
            if (default_normal) |def| {
                if (normal_value != def) {
                    try writer.expression("value");
                    try writer.printRaw("{} non-inverted", .{ normal_value });
                    try writer.close();
                }
            } else {
                default_normal = normal_value;
            }

            const invert_value = results_invert.jedec.get(fuse);
            if (default_invert) |def| {
                if (invert_value != def) {
                    try writer.expression("value");
                    try writer.printRaw("{} inverted", .{ invert_value });
                    try writer.close();
                }
            } else {
                default_invert = invert_value;
            }

        } else {
            try helper.err("Expected one invert fuse but found none!", .{}, dev, .{ .mcref = mcref });
            return error.Think;
        }

        if (diff_iter.next()) |_| {
            try helper.err("Expected one invert fuse but found multiple!", .{}, dev, .{ .mcref = mcref });
            return error.Think;
        }

        try writer.close();

        if (mcref.mc == 15) {
            try writer.close();
        }
    }

    if (default_normal) |def| {
        try writer.expression("value");
        try writer.printRaw("{} non-inverted", .{ def });
        try writer.close();
    }

    if (default_invert) |def| {
        try writer.expression("value");
        try writer.printRaw("{} inverted", .{ def });
        try writer.close();
    }

    try writer.done();

    _ = pa;
}
