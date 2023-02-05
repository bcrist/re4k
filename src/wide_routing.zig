const std = @import("std");
const TempAllocator = @import("temp_allocator");
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
const Fuse = jedec.Fuse;

pub fn main() void {
    helper.main(1);
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, mcref: common.MacrocellRef, pts: u8, report_mcref: common.MacrocellRef) !toolchain.FitResults {
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
    try helper.logResults(dev.device, "wide_routing_glb{}_mc{}_pts{}", .{ report_mcref.glb, report_mcref.mc, pts }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer(std.fs.File.Writer)) !void {
    //var mc_columns = try helper.parseMCOptionsColumns(ta, pa, null);
    //var orm_rows = try helper.parseORMRows(ta, pa, null);
    var cluster_routing = try parseClusterRoutingRows(ta, pa, null);

    try writer.expressionExpanded(@tagName(dev.device));
    try writer.expressionExpanded("wide_routing");

    var default_narrow: ?u1 = null;
    var default_wide: ?u1 = null;

    var mc_iter = helper.MacrocellIterator { .dev = dev };
    while (mc_iter.next()) |mcref| {
        // note mcref is the macrocell that contains the wide routing switch we're testing.
        // when enabled, we'll be using mcref.mc + 4 as the primary output.
        // when not enabled, we'll do 5 pts into mcref.mc, 5 into mcref.mc + 4, and the +1/+2/-1 mcs surrounding it, if they exist

        try tc.cleanTempDir();
        helper.resetTemp();

        if (mcref.mc == 0) {
            try helper.writeGlb(writer, mcref.glb);
        }

        try helper.writeMc(writer, mcref.mc);

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
            if (!cluster_routing.isSet(fuse.row)) {
                try helper.writeFuse(writer, fuse);

                const narrow_value = results_narrow.jedec.get(fuse);
                if (default_narrow) |def| {
                    if (narrow_value != def) {
                        try helper.writeValue(writer, narrow_value, "to_mc");
                    }
                } else {
                    default_narrow = narrow_value;
                }

                const wide_value = results_wide.jedec.get(fuse);
                if (default_wide) |def| {
                    if (wide_value != def) {
                        try helper.writeValue(writer, wide_value, "to_mc_plus_4");
                    }
                } else {
                    default_wide = wide_value;
                }

                fuse_count += 1;
            }
        }

        if (fuse_count != 1) {
            try helper.err("Expected one fuse for wide routing, but found {}!", .{ fuse_count }, dev, .{ .mcref = mcref });
        }

        try writer.close(); // mc

        if (mcref.mc == 15) {
            try writer.close(); // glb
        }
    }

    if (default_narrow) |def| {
        try helper.writeValue(writer, def, "to_mc");
    }

    if (default_wide) |def| {
        try helper.writeValue(writer, def, "to_mc_plus_4");
    }

    try writer.done();
}


fn parseClusterRoutingRows(ta: std.mem.Allocator, pa: std.mem.Allocator, out_device: ?*DeviceInfo) !std.DynamicBitSet {
    const input_file = helper.getInputFile("cluster_routing.sx") orelse return error.MissingClusterRoutingInputFile;
    const dev = DeviceInfo.init(input_file.device_type);

    var results = try std.DynamicBitSet.initEmpty(pa, dev.jedec_dimensions.height());

    var stream = std.io.fixedBufferStream(input_file.contents);
    var parser = sx.reader(ta, stream.reader());
    defer parser.deinit();

    parseClusterRoutingRows0(&parser, &results) catch |e| switch (e) {
        error.SExpressionSyntaxError => {
            var ctx = try parser.getNextTokenContext();
            try ctx.printForString(input_file.contents, std.io.getStdErr().writer(), 120);
            return e;
        },
        else => return e,
    };

    if (out_device) |ptr| {
        ptr.* = dev;
    }

    return results;
}

fn parseClusterRoutingRows0(parser: *sx.Reader(std.io.FixedBufferStream([]const u8).Reader), results: *std.DynamicBitSet) !void {
    _ = try parser.requireAnyExpression(); // device name, we already know it
    try parser.requireExpression("cluster_routing");

    while (try helper.parseGlb(parser)) |_| {
        while (try parser.expression("mc")) {
            _ = try parser.requireAnyInt(u16, 10);

            while (try parser.expression("fuse")) {
                var row = try parser.requireAnyInt(u16, 10);
                _ = try parser.requireAnyInt(u16, 10);

                if (try parser.expression("value")) {
                    try parser.ignoreRemainingExpression();
                }

                results.set(row);

                try parser.requireClose(); // fuse
            }

            try parser.requireClose(); // mc
        }
        try parser.requireClose(); // glb
    }
    while (try parser.expression("value")) {
        try parser.ignoreRemainingExpression();
    }
    try parser.requireClose(); // cluster_routing
    try parser.requireClose(); // device
    try parser.requireDone();
}