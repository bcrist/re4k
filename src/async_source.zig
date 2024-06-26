const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const jedec = lc4k.jedec;
const device_info = @import("device_info.zig");
const JedecData = jedec.JedecData;
const DeviceInfo = device_info.DeviceInfo;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

pub fn main() void {
    helper.main();
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, mcref: lc4k.MacrocellRef, pt2_as: bool) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    try design.nodeAssignment(.{
        .signal = "out",
        .glb = mcref.glb,
        .mc = mcref.mc,
        .init_state = 0,
    });
    try design.addPT("in", "out.D");

    if (pt2_as) {
        try design.addPT("as", "out.AP");
    }

    // make sure "as" is configured as an input even when not used in the macrocell we're testing:
    const scratch_glb: u8 = if (mcref.glb == 0) 1 else 0;
    try design.nodeAssignment(.{
        .signal = "dum",
        .glb = scratch_glb,
        .mc = 0,
        .init_state = 0,
    });
    try design.addPT("in", "dum.D");
    try design.addPT("as", "dum.AP");

    var results = try tc.runToolchain(design);
    try helper.logResults(dev.device, "pt2_reset_glb{}_mc{}_{}", .{ mcref.glb, mcref.mc, pt2_as }, results);
    try results.checkTerm();
    return results;
}

var default_off: ?usize = null;
var default_on: ?usize = null;

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer) !void {
    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("async_source");

    var mc_iter = helper.MacrocellIterator { .dev = dev };
    while (mc_iter.next()) |mcref| {
        try tc.cleanTempDir();
        helper.resetTemp();

        const results_off = try runToolchain(ta, tc, dev, mcref, false);
        const results_on = try runToolchain(ta, tc, dev, mcref, true);

        var diff = try JedecData.initDiff(ta, results_off.jedec, results_on.jedec);

        // ignore differences in PTs and GLB routing
        diff.putRange(dev.getRoutingRange(), 0);

        if (mcref.mc == 0) {
            try helper.writeGlb(writer, mcref.glb);
        }

        try helper.writeMc(writer, mcref.mc);

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
            try helper.err("Expected one async_source fuses but found {}!", .{ diff.countSet() }, dev, .{ .mcref = mcref });
        }

        if (default_off) |def| {
            if (value_off != def) {
                try helper.writeValue(writer, value_off, "disabled");
            }
        } else {
            default_off = value_off;
        }

        if (default_on) |def| {
            if (value_on != def) {
                try helper.writeValue(writer, value_on, "pt2");
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
        try helper.writeValue(writer, def, "disabled");
    }

    if (default_on) |def| {
        try helper.writeValue(writer, def, "pt2");
    }

    try writer.done();

    _ = pa;
}
