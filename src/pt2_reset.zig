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

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, mcref: core.MacrocellRef, pt_as: bool) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    try design.nodeAssignment(.{
        .signal = "out",
        .glb = mcref.glb,
        .mc = mcref.mc,
        .powerup_state = 0,
    });
    try design.addPT("in", "out.D");

    if (pt_as) {
        try design.addPT("as", "out.AP");
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
    try design.addPT("as", "dum.AP");

    var results = try tc.runToolchain(design);
    try helper.logReport("pt2_reset_glb{}_mc{}_{}", .{ mcref.glb, mcref.mc, pt_as }, results);
    try results.checkTerm();
    return results;
}

var default_off: ?usize = null;
var default_on: ?usize = null;

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("pt2_async_reset_preset");

    var mc_iter = core.MacrocellIterator { .device = dev };
    while (mc_iter.next()) |mcref| {
        try tc.cleanTempDir();
        helper.resetTemp();

        const results_off = try runToolchain(ta, tc, dev, mcref, false);
        const results_on = try runToolchain(ta, tc, dev, mcref, true);

        var diff = try helper.diff(ta, results_off.jedec, results_on.jedec);

        // ignore differences in PTs and GLB routing
        diff.setRange(0, 0, dev.getNumGlbInputs() * 2, dev.getJedecWidth(), 0);

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
        var diff_iter = diff.raw.iterator(.{});
        while (diff_iter.next()) |fuse| {
            const row = diff.getRow(@intCast(u32, fuse));
            const col = diff.getColumn(@intCast(u32, fuse));

            try writer.expression("fuse");
            try writer.printRaw("{}", .{ row });
            try writer.printRaw("{}", .{ col });

            if (bit_value != 1) {
                try writer.expression("value");
                try writer.printRaw("{}", .{ bit_value });
                try writer.close();
            }

            if (results_off.jedec.raw.isSet(fuse)) {
                value_off |= bit_value;
            }
            if (results_on.jedec.raw.isSet(fuse)) {
                value_on |= bit_value;
            }

            try writer.close();

            bit_value *= 2;
        }

        if (diff.raw.count() != 1) {
            try std.io.getStdErr().writer().print("Expected one pt2_reset fuses for device {s} glb {} mc {} but found {}!\n", .{ @tagName(dev), mcref.glb, mcref.mc, diff.raw.count() });
        }

        if (default_off) |def| {
            if (value_off != def) {
                try writer.expression("value");
                try writer.printRaw("{} disabled", .{ value_off });
                try writer.close();
            }
        } else {
            default_off = value_off;
        }

        if (default_on) |def| {
            if (value_on != def) {
                try writer.expression("value");
                try writer.printRaw("{} enabled", .{ value_on });
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
        try writer.printRaw("{} disabled", .{ def });
        try writer.close();
    }

    if (default_on) |def| {
        try writer.expression("value");
        try writer.printRaw("{} enabled", .{ def });
        try writer.close();
    }

    try writer.done();

    _ = pa;
}
