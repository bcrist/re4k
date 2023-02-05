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

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, mcref: common.MacrocellRef, invert: bool) !toolchain.FitResults {
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
    try helper.logResults(dev.device, "invert_glb{}_mc{}_{}", .{ mcref.glb, mcref.mc, invert }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev.device));
    try writer.expressionExpanded("invert");

    var default_normal: ?u1 = null;
    var default_invert: ?u1 = null;

    var mc_iter = helper.MacrocellIterator { .dev = dev };
    while (mc_iter.next()) |mcref| {
        try tc.cleanTempDir();
        helper.resetTemp();

        const results_normal = try runToolchain(ta, tc, dev, mcref, false);
        const results_invert = try runToolchain(ta, tc, dev, mcref, true);

        const diff = try JedecData.initDiff(ta, results_normal.jedec, results_invert.jedec);

        if (mcref.mc == 0) {
            try helper.writeGlb(writer, mcref.glb);
        }

        try helper.writeMc(writer, mcref.mc);

        var diff_iter = diff.iterator(.{});
        if (diff_iter.next()) |fuse| {
            try helper.writeFuse(writer, fuse);

            const normal_value = results_normal.jedec.get(fuse);
            if (default_normal) |def| {
                if (normal_value != def) {
                    try helper.writeValue(writer, normal_value, "disabled");
                }
            } else {
                default_normal = normal_value;
            }

            const invert_value = results_invert.jedec.get(fuse);
            if (default_invert) |def| {
                if (invert_value != def) {
                    try helper.writeValue(writer, invert_value, "enabled");
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
        try helper.writeValue(writer, def, "disabled");
    }

    if (default_invert) |def| {
        try helper.writeValue(writer, def, "enabled");
    }

    try writer.done();

    _ = pa;
}
