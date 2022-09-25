const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx.zig");
const core = @import("core.zig");
const jedec = @import("jedec.zig");
const devices = @import("devices.zig");

const Fuse = jedec.Fuse;
const JedecData = jedec.JedecData;
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

pub fn main() void {
    helper.main(0);
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, mcref: core.MacrocellRef, powerup_state: u1) !toolchain.FitResults {
    var design = Design.init(ta, dev);
    try design.nodeAssignment(.{
        .signal = "out",
        .glb = mcref.glb,
        .mc = mcref.mc,
        .powerup_state = powerup_state,
    });
    try design.addPT("in", "out.D");

    var results = try tc.runToolchain(design);
    try helper.logReport("powerup_state_glb{}_mc{}_{}", .{ mcref.glb, mcref.mc, powerup_state }, results);
    try results.checkTerm();
    return results;
}

var default_set: ?u1 = null;
var default_reset: ?u1 = null;

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("powerup_state");

    var mc_iter = core.MacrocellIterator { .device = dev };
    while (mc_iter.next()) |mcref| {
        try tc.cleanTempDir();
        helper.resetTemp();

        const results_reset = try runToolchain(ta, tc, dev, mcref, 0);
        const results_set = try runToolchain(ta, tc, dev, mcref, 1);

        const diff = try JedecData.initDiff(ta, results_reset.jedec, results_set.jedec);

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
            try writeFuse(fuse, results_reset.jedec, results_set.jedec, writer);
        } else {
            try helper.err("Expected one powerup state fuse but found none!", .{}, dev, .{ .mcref = mcref });
        }

        if (diff_iter.next()) |fuse| {
            try helper.err("Expected one powerup state fuse but found multiple!", .{}, dev, .{ .mcref = mcref });
            try writeFuse(fuse, results_reset.jedec, results_set.jedec, writer);

            while (diff_iter.next()) |f| {
                try writeFuse(f, results_reset.jedec, results_set.jedec, writer);
            }
        }

        try writer.close();

        if (mcref.mc == 15) {
            try writer.close();
        }
    }

    if (default_reset) |def| {
        try writer.expression("value");
        try writer.printRaw("{} reset", .{ def });
        try writer.close();
    }

    if (default_set) |def| {
        try writer.expression("value");
        try writer.printRaw("{} set", .{ def });
        try writer.close();
    }

    try writer.done();

    _ = pa;
}

fn writeFuse(fuse: Fuse, results_reset: JedecData, results_set: JedecData, writer: anytype) !void {
    try helper.writeFuse(writer, fuse);

    const value_reset = results_reset.get(fuse);
    if (default_reset) |def| {
        if (value_reset != def) {
            try writer.expression("value");
            try writer.printRaw("{} reset", .{ value_reset });
            try writer.close();
        }
    } else {
        default_reset = value_reset;
    }

    const value_set = results_set.get(fuse);
    if (default_set) |def| {
        if (value_set != def) {
            try writer.expression("value");
            try writer.printRaw("{} low", .{ value_set });
            try writer.close();
        }
    } else {
        default_set = value_set;
    }
}
