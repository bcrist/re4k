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
    helper.main(2);
}

fn getMaxPTsWithoutWideSteering(mc: usize) u8 {
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
    try helper.logReport("cluster_steering_glb{}_mc{}_pts{}", .{ mcref.glb, mcref.mc, pts }, results);
    try results.checkTerm();
    return results;
}

const ClusterSteeringMode = enum {
    to_mc_minus_two,
    to_mc,
    to_mc_plus_one,
    to_mc_minus_one,
};

const ClusterSteeringKey = struct {
    mc: u8,
    mode: ClusterSteeringMode,
};
const ClusterSteeringValue = struct {
    jedec: JedecData,
    mask: JedecData,
};
const ClusterSteeringMap = std.AutoHashMap(ClusterSteeringKey, ClusterSteeringValue);


pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    var mc_columns = try helper.parseMCOptionsColumns(ta, pa, null);
    var orm_rows = try helper.parseORMRows(ta, pa, null);

    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("cluster_steering");

    var glb_arena = try TempAllocator.init(0x100_00000);
    //var glb_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer glb_arena.deinit();
    var ga = glb_arena.allocator();

    var default_values = std.EnumMap(ClusterSteeringMode, usize) {};

    var glb: u8 = 0;
    while (glb < dev.getNumGlbs()) : (glb += 1) {
        glb_arena.reset();
        //glb_arena.deinit();
        //glb_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

        var steering_data = ClusterSteeringMap.init(ga);
        try steering_data.ensureTotalCapacity(80);

        try writer.expression("glb");
        try writer.printRaw("{}", .{ glb });
        writer.setCompact(false);

        var mc: u8 = 0;
        while (mc < 16) : (mc += 1) {
            var pts: u8 = 5;
            while (pts <= getMaxPTsWithoutWideSteering(mc)) : (pts += 5) {
                try tc.cleanTempDir();
                helper.resetTemp();

                const results = try runToolchain(ta, tc, dev, .{ .glb = glb, .mc = mc }, pts);

                var cluster_usage = try helper.parseClusterUsage(ta, glb, results.report, mc);
                if (cluster_usage.count() != pts / 5) {
                    try helper.err("Expected cluster usage of {} but found {}", .{ pts / 5, cluster_usage.count() }, dev, .{ .glb = glb, .mc = mc });
                }

                for (std.enums.values(ClusterSteeringMode)) |mode| {
                    try checkSteeringData(&steering_data, cluster_usage, results.jedec, mc, mode );
                }
            }
        }

        mc = 0;
        while (mc < 16) : (mc += 1) {
            try writer.expression("mc");
            try writer.printRaw("{}", .{ mc });

            var column = mc_columns.get(.{ .glb = glb, .mc = mc }).?.min.col;

            var rows = std.StaticBitSet(100).initEmpty();
            var diff_base = steering_data.get(.{ .mc = mc, .mode = .to_mc }).?.jedec;
            for (std.enums.values(ClusterSteeringMode)) |mode| {
                if (steering_data.get(.{ .mc = mc, .mode = mode })) |data| {
                    var fuse_iter = mc_columns.get(.{ .glb = glb, .mc = mc }).?.iterator();
                    while (fuse_iter.next()) |fuse| {
                        if (!data.mask.isSet(fuse) and data.jedec.get(fuse) != diff_base.get(fuse) and !orm_rows.isSet(fuse.row)) {
                            rows.set(fuse.row);
                        }
                    }
                }
            }

            if (rows.count() != 2) {
                try helper.err("Expected 2 rows for cluster steering, but found {}!", .{ rows.count() }, dev, .{ .glb = glb, .mc = mc });
            }

            var values = std.EnumMap(ClusterSteeringMode, usize) {};

            var bit_value: usize = 1;
            var row_iter = rows.iterator(.{});
            while (row_iter.next()) |row| {
                var fuse = Fuse.init(@intCast(u16, row), column);
                try helper.writeFuseOptValue(writer, fuse, bit_value);

                for (std.enums.values(ClusterSteeringMode)) |mode| {
                    if (steering_data.get(.{ .mc = mc, .mode = mode })) |data| {
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
                    try writer.expression("value");
                    try writer.printRaw("{} {s}", .{ entry.value.*, @tagName(entry.key) });
                    try writer.close(); // value
                }
            }

            try writer.close(); // mc
        }
        try writer.close(); // glb
    }

    var defaults_iter = default_values.iterator();
    while (defaults_iter.next()) |entry| {
        try writer.expression("value");
        try writer.printRaw("{} {s}", .{ entry.value.*, @tagName(entry.key) });
        try writer.close(); // value
    }

    try writer.done();

    _ = pa;
}

fn checkSteeringData(steering_data: *ClusterSteeringMap, cluster_usage: std.StaticBitSet(16), jed: JedecData, mc: i16, mode: ClusterSteeringMode) !void {
    var cluster = switch (mode) {
        .to_mc_minus_two => mc + 2,
        .to_mc_minus_one => mc + 1,
        .to_mc => mc,
        .to_mc_plus_one => mc - 1,
    };
    if (cluster < 0 or cluster > 15) {
        return;
    }
    var key = ClusterSteeringKey {
        .mc = @intCast(u8, cluster),
        .mode = mode,
    };
    if (cluster_usage.isSet(@intCast(usize, cluster))) {
        var result = try steering_data.getOrPut(key);
        if (result.found_existing) {
            result.value_ptr.mask.unionDiff(result.value_ptr.jedec, jed);
        } else {
            result.value_ptr.* = .{
                .jedec = try jed.clone(steering_data.allocator),
                .mask = try JedecData.initEmpty(steering_data.allocator, jed.width, jed.height),
            };
        }
    }
}
