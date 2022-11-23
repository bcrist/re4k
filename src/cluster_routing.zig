const std = @import("std");
const TempAllocator = @import("temp_allocator");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const jedec = @import("jedec.zig");
const core = @import("core.zig");
const devices = @import("devices.zig");
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JedecData = jedec.JedecData;
const Fuse = jedec.Fuse;

pub fn main() void {
    helper.main(2);
}

fn getMaxPTsWithoutWideRouting(mc: usize) u8 {
    return switch (mc) {
        0, 14 => 15,
        15 => 10,
        else => 20,
    };
}


fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, mcref: core.MacrocellRef, pts: u8) !toolchain.FitResults {
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
    try helper.logResults("cluster_routing_glb{}_mc{}_pts{}", .{ mcref.glb, mcref.mc, pts }, results);
    try results.checkTerm();
    return results;
}

const ClusterRoutingMode = enum {
    to_mc_minus_two,
    to_mc,
    to_mc_plus_one,
    to_mc_minus_one,
};

const ClusterRoutingKey = struct {
    mc: u8,
    mode: ClusterRoutingMode,
};
const ClusterRoutingValue = struct {
    jedec: JedecData,
    mask: JedecData,
};
const ClusterRoutingMap = std.AutoHashMap(ClusterRoutingKey, ClusterRoutingValue);

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    var mc_columns = try helper.parseMCOptionsColumns(ta, pa, null);
    var orm_rows = try helper.parseORMRows(ta, pa, null);

    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("cluster_routing");

    var glb_arena = try TempAllocator.init(0x100_00000);
    defer glb_arena.deinit();
    var ga = glb_arena.allocator();

    var default_values = std.EnumMap(ClusterRoutingMode, usize) {};

    var glb: u8 = 0;
    while (glb < dev.getNumGlbs()) : (glb += 1) {
        glb_arena.reset();

        var routing_data = ClusterRoutingMap.init(ga);
        try routing_data.ensureTotalCapacity(80);

        try helper.writeGlb(writer, glb);

        var mc: u8 = 0;
        while (mc < 16) : (mc += 1) {
            var pts: u8 = 5;
            while (pts <= getMaxPTsWithoutWideRouting(mc)) : (pts += 5) {
                try tc.cleanTempDir();
                helper.resetTemp();

                const results = try runToolchain(ta, tc, dev, .{ .glb = glb, .mc = mc }, pts);

                var cluster_usage = try parseClusterUsage(ta, glb, results.report, mc);
                if (cluster_usage.count() != pts / 5) {
                    try helper.err("Expected cluster usage of {} but found {}", .{ pts / 5, cluster_usage.count() }, dev, .{ .glb = glb, .mc = mc });
                }

                for (std.enums.values(ClusterRoutingMode)) |mode| {
                    try checkRoutingData(&routing_data, cluster_usage, results.jedec, mc, mode );
                }
            }
        }

        mc = 0;
        while (mc < 16) : (mc += 1) {
            try helper.writeMc(writer, mc);

            var column = mc_columns.get(.{ .glb = glb, .mc = mc }).?.min.col;

            var rows = std.StaticBitSet(100).initEmpty();
            var diff_base = routing_data.get(.{ .mc = mc, .mode = .to_mc }).?.jedec;
            for (std.enums.values(ClusterRoutingMode)) |mode| {
                if (routing_data.get(.{ .mc = mc, .mode = mode })) |data| {
                    var fuse_iter = mc_columns.get(.{ .glb = glb, .mc = mc }).?.iterator();
                    while (fuse_iter.next()) |fuse| {
                        if (!data.mask.isSet(fuse) and data.jedec.get(fuse) != diff_base.get(fuse) and !orm_rows.isSet(fuse.row)) {
                            rows.set(fuse.row);
                        }
                    }
                }
            }

            if (rows.count() != 2) {
                try helper.err("Expected 2 rows for cluster routing, but found {}!", .{ rows.count() }, dev, .{ .glb = glb, .mc = mc });
            }

            var values = std.EnumMap(ClusterRoutingMode, usize) {};

            var bit_value: usize = 1;
            var row_iter = rows.iterator(.{});
            while (row_iter.next()) |row| {
                var fuse = Fuse.init(@intCast(u16, row), column);
                try helper.writeFuseOptValue(writer, fuse, bit_value);

                for (std.enums.values(ClusterRoutingMode)) |mode| {
                    if (routing_data.get(.{ .mc = mc, .mode = mode })) |data| {
                        var val = values.get(mode) orelse 0;
                        val += data.jedec.get(fuse) * bit_value;
                        values.put(mode, val);
                    }
                }

                bit_value *= 2;
            }

            var all_defaults = true;
            var val_iter = values.iterator();
            while (val_iter.next()) |entry| {
                if (default_values.get(entry.key)) |default| {
                    if (default != entry.value.*) {
                        all_defaults = false;
                        break;
                    }
                } else {
                    default_values.put(entry.key, entry.value.*);
                }
            }

            if (!all_defaults) {
                writer.setCompact(false);
                val_iter = values.iterator();
                while (val_iter.next()) |entry| {
                    try helper.writeValue(writer, entry.value.*, entry.key);
                }
            }

            try writer.close(); // mc
        }
        try writer.close(); // glb
    }

    var defaults_iter = default_values.iterator();
    while (defaults_iter.next()) |entry| {
        try helper.writeValue(writer, entry.value.*, entry.key);
    }

    try writer.done();
}

fn checkRoutingData(routing_data: *ClusterRoutingMap, cluster_usage: std.StaticBitSet(16), jed: JedecData, mc: i16, mode: ClusterRoutingMode) !void {
    var cluster = switch (mode) {
        .to_mc_minus_two => mc + 2,
        .to_mc_minus_one => mc + 1,
        .to_mc => mc,
        .to_mc_plus_one => mc - 1,
    };
    if (cluster < 0 or cluster > 15) {
        return;
    }
    var key = ClusterRoutingKey {
        .mc = @intCast(u8, cluster),
        .mode = mode,
    };
    if (cluster_usage.isSet(@intCast(usize, cluster))) {
        var result = try routing_data.getOrPut(key);
        if (result.found_existing) {
            result.value_ptr.mask.unionDiff(result.value_ptr.jedec, jed);
        } else {
            result.value_ptr.* = .{
                .jedec = try jed.clone(routing_data.allocator),
                .mask = try JedecData.initEmpty(routing_data.allocator, jed.width, jed.height),
            };
        }
    }
}

fn parseClusterUsage(ta: std.mem.Allocator, glb: u8, report: []const u8, mc: u8) !std.StaticBitSet(16) {
    var cluster_usage = std.StaticBitSet(16).initEmpty();
    const header = try std.fmt.allocPrint(ta, "GLB_{s}_CLUSTER_TABLE", .{ devices.getGlbName(glb) });
    if (helper.extract(report, header, "<Note>")) |raw| {
        var line_iter = std.mem.tokenize(u8, raw, "\r\n");
        while (line_iter.next()) |line| {
            if (line[0] != 'M') {
                continue; // ignore remaining header/footer lines
            }

            var line_mc = try std.fmt.parseInt(u8, line[1..3], 10);
            if (line_mc == mc) {
                cluster_usage.setValue(0,  isClusterUsed(line[4]));
                cluster_usage.setValue(1,  isClusterUsed(line[5]));
                cluster_usage.setValue(2,  isClusterUsed(line[6]));
                cluster_usage.setValue(3,  isClusterUsed(line[7]));
                cluster_usage.setValue(4,  isClusterUsed(line[9]));
                cluster_usage.setValue(5,  isClusterUsed(line[10]));
                cluster_usage.setValue(6,  isClusterUsed(line[11]));
                cluster_usage.setValue(7,  isClusterUsed(line[12]));
                cluster_usage.setValue(8,  isClusterUsed(line[14]));
                cluster_usage.setValue(9,  isClusterUsed(line[15]));
                cluster_usage.setValue(10, isClusterUsed(line[16]));
                cluster_usage.setValue(11, isClusterUsed(line[17]));
                cluster_usage.setValue(12, isClusterUsed(line[19]));
                cluster_usage.setValue(13, isClusterUsed(line[20]));
                cluster_usage.setValue(14, isClusterUsed(line[21]));
                cluster_usage.setValue(15, isClusterUsed(line[22]));
            }
        }
    }
    return cluster_usage;
}

fn isClusterUsed(report_value: u8) bool {
    return switch (report_value) {
        '0'...'5' => true,
        else => false,
    };
}
