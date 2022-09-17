const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx.zig");
const core = @import("core.zig");
const jedec = @import("jedec.zig");
const devices = @import("devices/devices.zig");
const JedecData = jedec.JedecData;
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

pub fn main() void {
    helper.main();
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

        var diff = try results_reset.jedec.clone(ta);
        try diff.xor(results_set.jedec);

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

        var diff_iter = diff.raw.iterator(.{});
        if (diff_iter.next()) |fuse| {
            try writeFuse(fuse, results_reset.jedec, results_set.jedec, diff, writer);
        } else {
            try std.io.getStdErr().writer().print("Expected one powerup state fuse for device {} glb {} mc {} but found none!\n", .{ dev, mcref.glb, mcref.mc });
        }

        if (diff_iter.next()) |fuse| {
            try std.io.getStdErr().writer().print("Expected one powerup state fuse for device {} glb {} mc {} but found multiple!\n", .{ dev, mcref.glb, mcref.mc });
            try writeFuse(fuse, results_reset.jedec, results_set.jedec, diff, writer);

            while (diff_iter.next()) |f| {
                try writeFuse(f, results_reset.jedec, results_set.jedec, diff, writer);
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

fn writeFuse(fuse: usize, results_reset: JedecData, results_set: JedecData, diff: JedecData, writer: anytype) !void {
    const row = diff.getRow(@intCast(u32, fuse));
    const col = diff.getColumn(@intCast(u32, fuse));

    try writer.expression("fuse");
    try writer.printRaw("{}", .{ row });
    try writer.printRaw("{}", .{ col });

    const value_reset = results_reset.get(row, col);
    if (default_reset) |def| {
        if (value_reset != def) {
            try writer.expression("value");
            try writer.printRaw("{} reset", .{ value_reset });
            try writer.close();
        }
    } else {
        default_reset = value_reset;
    }

    const value_set = results_set.get(row, col);
    if (default_set) |def| {
        if (value_set != def) {
            try writer.expression("value");
            try writer.printRaw("{} low", .{ value_set });
            try writer.close();
        }
    } else {
        default_set = value_set;
    }

    try writer.close();
}
