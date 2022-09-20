const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx.zig");
const core = @import("core.zig");
const jedec = @import("jedec.zig");
const devices = @import("devices.zig");
const JedecData = jedec.JedecData;
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

pub fn main() void {
    helper.main();
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, mcref: core.MacrocellRef, pt3_ar: bool) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    try design.nodeAssignment(.{
        .signal = "out",
        .glb = mcref.glb,
        .mc = mcref.mc,
        .powerup_state = 0,
    });
    try design.addPT("in", "out.D");

    if (pt3_ar) {
        try design.addPT("as", "out.AR");
    } else {
        try design.addPT("gas", "out.AR");
    }

    // make sure "as" is configured as an input even when not used in the macrocell we're testing:
    const scratch_glb: u8 = if (mcref.glb == 0) 1 else 0;
    try design.nodeAssignment(.{
        .signal = "dum",
        .glb = scratch_glb,
        .mc = 0,
        .powerup_state = 0,
    });
    try design.addPT("in", "dum.D");
    try design.addPT("as", "dum.AR");

    // make sure "gas" is assigned to the shared init PT by using as such in another MC within the same GLB:
    const scratch_mc: u8 = if (mcref.mc == 0) 15 else mcref.mc - 1;
    try design.nodeAssignment(.{
        .signal = "gdum",
        .glb = mcref.glb,
        .mc = scratch_mc,
        .powerup_state = 0,
    });
    try design.addPT("in", "gdum.D");
    try design.addPT("gas", "gdum.AR");

    var results = try tc.runToolchain(design);
    try helper.logReport("pt3_reset_glb{}_mc{}_{}", .{ mcref.glb, mcref.mc, pt3_ar }, results);
    try results.checkTerm(false);
    return results;
}

var default_off: ?usize = null;
var default_on: ?usize = null;

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("pt3_async_reset_preset");

    var mc_iter = core.MacrocellIterator { .device = dev };
    while (mc_iter.next()) |mcref| {
        try tc.cleanTempDir();
        helper.resetTemp();

        const results_off = try runToolchain(ta, tc, dev, mcref, false);
        const results_on = try runToolchain(ta, tc, dev, mcref, true);

        var diff = try JedecData.initDiff(ta, results_off.jedec, results_on.jedec);

        // ignore differences in PTs and GLB routing
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

        var value_off: usize = 0;
        var value_on: usize = 0;

        var bit_value: usize = 1;
        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            try helper.writeFuseOptValue(writer, fuse, bit_value);

            if (results_off.jedec.isSet(fuse)) {
                value_off |= bit_value;
            }
            if (results_on.jedec.isSet(fuse)) {
                value_on |= bit_value;
            }

            bit_value *= 2;
        }

        if (diff.countSet() != 1) {
            try helper.err("Expected one pt3_reset fuse but found {}!", .{ diff.countSet() }, dev, .{ .mcref = mcref });
        }

        if (default_off) |def| {
            if (value_off != def) {
                try writer.expression("value");
                try writer.printRaw("{} shared_pt", .{ value_off });
                try writer.close();
            }
        } else {
            default_off = value_off;
        }

        if (default_on) |def| {
            if (value_on != def) {
                try writer.expression("value");
                try writer.printRaw("{} pt3", .{ value_on });
                try writer.close();
            }
        } else {
            default_on = value_on;
        }

        try writer.close();

        if (mcref.mc == 15) {
            try writer.close();
        }
    }

    if (default_off) |def| {
        try writer.expression("value");
        try writer.printRaw("{} shared_pt", .{ def });
        try writer.close();
    }

    if (default_on) |def| {
        try writer.expression("value");
        try writer.printRaw("{} pt3", .{ def });
        try writer.close();
    }

    try writer.done();

    _ = pa;
}
