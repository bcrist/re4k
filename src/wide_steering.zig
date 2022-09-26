const std = @import("std");
const TempAllocator = @import("temp_allocator");
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
const Fuse = jedec.Fuse;

pub fn main() void {
    helper.main(1);
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, mcref: core.MacrocellRef, pts: u8, report_mcref: core.MacrocellRef) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    try design.pinAssignment(.{ .signal = "x0" });
    try design.pinAssignment(.{ .signal = "x1" });
    try design.pinAssignment(.{ .signal = "x2" });
    try design.pinAssignment(.{ .signal = "x3" });
    try design.pinAssignment(.{ .signal = "x4" });
    try design.nodeAssignment(.{
        .signal = "out",
        .glb = mcref.glb,
        .mc = mcref.mc,
    });

    var signals_storage: [5][]const u8 = undefined;
    var signals: [][]const u8 = &signals_storage;

    var i: u8 = 0;
    while (i < pts) : (i += 1) {
        signals[0] = if ((i & 1) == 0)  "~x0" else "x0";
        signals[1] = if ((i & 2) == 0)  "~x1" else "x1";
        signals[2] = if ((i & 4) == 0)  "~x2" else "x2";
        signals[3] = if ((i & 8) == 0)  "~x3" else "x3";
        signals[4] = if ((i & 16) == 0) "~x4" else "x4";

        try design.addPT(signals, "out.D-");
    }

    var results = try tc.runToolchain(design);
    try helper.logReport("wide_steering_glb{}_mc{}_pts{}", .{ report_mcref.glb, report_mcref.mc, pts }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    //var mc_columns = try helper.parseMCOptionsColumns(ta, pa, null);
    //var orm_rows = try helper.parseORMRows(ta, pa, null);
    var cluster_steering = try helper.parseClusterSteeringRows(ta, pa, null);

    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("wide_steering");

    var default_narrow: ?u1 = null;
    var default_wide: ?u1 = null;

    var mc_iter = core.MacrocellIterator { .device = dev };
    while (mc_iter.next()) |mcref| {
        // note mcref is the macrocell that contains the wide steering switch we're testing.
        // when enabled, we'll be using mcref.mc + 4 as the primary output.
        // when not enabled, we'll do 5 pts into mcref.mc, 5 into mcref.mc + 4, and the +1/+2/-1 mcs surrounding it, if they exist

        try tc.cleanTempDir();
        helper.resetTemp();

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

        var wide_mcref = mcref;
        wide_mcref.mc = @truncate(u4, mcref.mc +% 4);

        var narrow_pts: u8 = 5;
        if (wide_mcref.mc > 0) narrow_pts += 5;
        if (wide_mcref.mc < 14) narrow_pts += 5;
        if (wide_mcref.mc < 15) narrow_pts += 5;

        const results_wide = try runToolchain(ta, tc, dev, wide_mcref, 25, mcref);
        const results_narrow = try runToolchain(ta, tc, dev, wide_mcref, narrow_pts, mcref);

        var diff = try JedecData.initDiff(ta, results_narrow.jedec, results_wide.jedec);

        diff.putRange(dev.getRoutingRange(), 0);

        var fuse_count: usize = 0;

        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            if (!cluster_steering.isSet(fuse.row)) {
                try helper.writeFuse(writer, fuse);

                const narrow_value = results_narrow.jedec.get(fuse);
                if (default_narrow) |def| {
                    if (narrow_value != def) {
                        try writer.expression("value");
                        try writer.printRaw("{} to_mc", .{ narrow_value });
                        try writer.close();
                    }
                } else {
                    default_narrow = narrow_value;
                }

                const wide_value = results_wide.jedec.get(fuse);
                if (default_wide) |def| {
                    if (wide_value != def) {
                        try writer.expression("value");
                        try writer.printRaw("{} to_mc_plus_four", .{ wide_value });
                        try writer.close();
                    }
                } else {
                    default_wide = wide_value;
                }

                fuse_count += 1;
            }
        }

        if (fuse_count != 1) {
            try helper.err("Expected one fuse for wide steering, but found {}!", .{ fuse_count }, dev, .{ .mcref = mcref });
        }

        try writer.close(); // mc

        if (mcref.mc == 15) {
            try writer.close(); // glb
        }
    }

    if (default_narrow) |def| {
        try writer.expression("value");
        try writer.printRaw("{} to_mc", .{ def });
        try writer.close();
    }

    if (default_wide) |def| {
        try writer.expression("value");
        try writer.printRaw("{} to_mc_plus_four", .{ def });
        try writer.close();
    }

    try writer.done();

    _ = pa;
}
