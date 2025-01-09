const std = @import("std");
const Temp_Allocator = @import("Temp_Allocator");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const Device_Info = @import("Device_Info.zig");
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JEDEC_Data = lc4k.JEDEC_Data;
const Fuse = lc4k.Fuse;
const MC_Ref = lc4k.MC_Ref;

pub fn main() void {
    helper.main();
}

fn get_max_pts_without_wide_routing(mc: usize) u8 {
    return switch (mc) {
        0, 14 => 15,
        15 => 10,
        else => 20,
    };
}


fn run_toolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, mcref: MC_Ref, pts: u8) !toolchain.Fit_Results {
    var design = Design.init(ta, dev);

    try design.pin_assignment(.{ .signal = "x0" });
    try design.pin_assignment(.{ .signal = "x1" });
    try design.pin_assignment(.{ .signal = "x2" });
    try design.pin_assignment(.{ .signal = "x3" });
    try design.pin_assignment(.{ .signal = "x4" });
    try design.node_assignment(.{
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

        try design.add_pt(signals, "out.D-");
    }

    var results = try tc.run_toolchain(design);
    try helper.log_results(dev.device, "cluster_routing_glb{}_mc{}_pts{}", .{ mcref.glb, mcref.mc, pts }, results);
    try results.check_term();
    return results;
}

const Cluster_Routing_Key = struct {
    mc: u8,
    mode: lc4k.Cluster_Routing,
};
const Cluster_Routing_Value = struct {
    jedec: JEDEC_Data,
    mask: JEDEC_Data,
};
const ClusterRoutingMap = std.AutoHashMap(Cluster_Routing_Key, Cluster_Routing_Value);

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    var mc_columns = try helper.parse_mc_options_columns(ta, pa, null);
    var orm_rows = try helper.parse_orm_rows(ta, pa, null);

    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("cluster_routing");

    var glb_arena = try Temp_Allocator.init(0x100_00000);
    defer glb_arena.deinit();
    const ga = glb_arena.allocator();

    var default_values = std.EnumMap(lc4k.Cluster_Routing, usize) {};

    var glb: u8 = 0;
    while (glb < dev.num_glbs) : (glb += 1) {
        glb_arena.reset(.{});

        var routing_data = ClusterRoutingMap.init(ga);
        try routing_data.ensureTotalCapacity(80);

        try helper.write_glb(writer, glb);

        var mc: u8 = 0;
        while (mc < dev.num_mcs_per_glb) : (mc += 1) {
            var pts: u8 = 5;
            while (pts <= get_max_pts_without_wide_routing(mc)) : (pts += 5) {
                try tc.clean_temp_dir();
                helper.reset_temp();

                const results = try run_toolchain(ta, tc, dev, .{ .glb = glb, .mc = mc }, pts);

                var cluster_usage = try parse_cluster_usage(ta, glb, results.report, mc);
                if (cluster_usage.count() != pts / 5) {
                    try helper.err("Expected cluster usage of {} but found {}", .{ pts / 5, cluster_usage.count() }, dev, .{ .glb = glb, .mc = mc });
                }

                for (std.enums.values(lc4k.Cluster_Routing)) |mode| {
                    try check_routing_data(&routing_data, cluster_usage, results.jedec, mc, mode );
                }
            }
        }

        mc = 0;
        while (mc < 16) : (mc += 1) {
            try helper.write_mc(writer, mc);

            const column = mc_columns.get(.{ .glb = glb, .mc = mc }).?.min.col;

            var rows = std.StaticBitSet(100).initEmpty();
            var diff_base = routing_data.get(.{ .mc = mc, .mode = .self }).?.jedec;
            for (std.enums.values(lc4k.Cluster_Routing)) |mode| {
                if (routing_data.get(.{ .mc = mc, .mode = mode })) |data| {
                    var fuse_iter = mc_columns.get(.{ .glb = glb, .mc = mc }).?.iterator();
                    while (fuse_iter.next()) |fuse| {
                        if (!data.mask.is_set(fuse) and data.jedec.get(fuse) != diff_base.get(fuse) and !orm_rows.isSet(fuse.row)) {
                            rows.set(fuse.row);
                        }
                    }
                }
            }

            if (rows.count() != 2) {
                try helper.err("Expected 2 rows for cluster routing, but found {}!", .{ rows.count() }, dev, .{ .glb = glb, .mc = mc });
            }

            var values = std.EnumMap(lc4k.Cluster_Routing, usize) {};

            var bit_value: usize = 1;
            var row_iter = rows.iterator(.{});
            while (row_iter.next()) |row| {
                const fuse = Fuse.init(@intCast(row), column);
                try helper.write_fuse_opt_value(writer, fuse, bit_value);

                for (std.enums.values(lc4k.Cluster_Routing)) |mode| {
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
                writer.set_compact(false);
                val_iter = values.iterator();
                while (val_iter.next()) |entry| {
                    try helper.write_value(writer, entry.value.*, entry.key);
                }
            }

            try writer.close(); // mc
        }
        try writer.close(); // glb
    }

    var defaults_iter = default_values.iterator();
    while (defaults_iter.next()) |entry| {
        try helper.write_value(writer, entry.value.*, entry.key);
    }

    try writer.done();
}

fn check_routing_data(routing_data: *ClusterRoutingMap, cluster_usage: std.StaticBitSet(16), jed: JEDEC_Data, mc: i16, mode: lc4k.Cluster_Routing) !void {
    const cluster = switch (mode) {
        .self_minus_two => mc + 2,
        .self_minus_one => mc + 1,
        .self => mc,
        .self_plus_one => mc - 1,
    };
    if (cluster < 0 or cluster > 15) {
        return;
    }
    const key = Cluster_Routing_Key {
        .mc = @intCast(cluster),
        .mode = mode,
    };
    if (cluster_usage.isSet(@intCast(cluster))) {
        var result = try routing_data.getOrPut(key);
        if (result.found_existing) {
            result.value_ptr.mask.union_diff(result.value_ptr.jedec, jed);
        } else {
            result.value_ptr.* = .{
                .jedec = try jed.clone(routing_data.allocator, jed.extents),
                .mask = try JEDEC_Data.init_empty(routing_data.allocator, jed.extents),
            };
        }
    }
}

fn parse_cluster_usage(ta: std.mem.Allocator, glb: u8, report: []const u8, mc: u8) !std.StaticBitSet(16) {
    var cluster_usage = std.StaticBitSet(16).initEmpty();
    const header = try std.fmt.allocPrint(ta, "GLB_{s}_CLUSTER_TABLE", .{ helper.get_glb_name(glb) });
    if (helper.extract(report, header, "<Note>")) |raw| {
        var line_iter = std.mem.tokenizeAny(u8, raw, "\r\n");
        while (line_iter.next()) |line| {
            if (line[0] != 'M') {
                continue; // ignore remaining header/footer lines
            }

            const line_mc = try std.fmt.parseInt(u8, line[1..3], 10);
            if (line_mc == mc) {
                cluster_usage.setValue(0,  is_cluster_used(line[4]));
                cluster_usage.setValue(1,  is_cluster_used(line[5]));
                cluster_usage.setValue(2,  is_cluster_used(line[6]));
                cluster_usage.setValue(3,  is_cluster_used(line[7]));
                cluster_usage.setValue(4,  is_cluster_used(line[9]));
                cluster_usage.setValue(5,  is_cluster_used(line[10]));
                cluster_usage.setValue(6,  is_cluster_used(line[11]));
                cluster_usage.setValue(7,  is_cluster_used(line[12]));
                cluster_usage.setValue(8,  is_cluster_used(line[14]));
                cluster_usage.setValue(9,  is_cluster_used(line[15]));
                cluster_usage.setValue(10, is_cluster_used(line[16]));
                cluster_usage.setValue(11, is_cluster_used(line[17]));
                cluster_usage.setValue(12, is_cluster_used(line[19]));
                cluster_usage.setValue(13, is_cluster_used(line[20]));
                cluster_usage.setValue(14, is_cluster_used(line[21]));
                cluster_usage.setValue(15, is_cluster_used(line[22]));
            }
        }
    }
    return cluster_usage;
}

fn is_cluster_used(report_value: u8) bool {
    return switch (report_value) {
        '0'...'5' => true,
        else => false,
    };
}
