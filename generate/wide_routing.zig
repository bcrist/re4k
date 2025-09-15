const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const Device_Info = @import("Device_Info.zig");
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JEDEC_Data = lc4k.JEDEC_Data;
const Fuse = lc4k.Fuse;

pub const main = helper.main;

fn run_toolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, mcref: lc4k.MC_Ref, pts: u8, report_mcref: lc4k.MC_Ref) !toolchain.Fit_Results {
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
    try helper.log_results(dev.device, "wide_routing_glb{}_mc{}_pts{}", .{ report_mcref.glb, report_mcref.mc, pts }, results);
    try results.check_term();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    //var mc_columns = try helper.parseMCOptionsColumns(ta, pa, null);
    //var orm_rows = try helper.parseORMRows(ta, pa, null);
    var cluster_routing = try parseClusterRoutingRows(ta, pa, null);

    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("wide_routing");

    var default_narrow: ?u1 = null;
    var default_wide: ?u1 = null;

    var mc_iter = helper.Macrocell_Iterator { .dev = dev };
    while (mc_iter.next()) |mcref| {
        // note mcref is the macrocell that contains the wide routing switch we're testing.
        // when enabled, we'll be using mcref.mc + 4 as the primary output.
        // when not enabled, we'll do 5 pts into mcref.mc, 5 into mcref.mc + 4, and the +1/+2/-1 mcs surrounding it, if they exist

        try tc.clean_temp_dir();
        helper.reset_temp();

        if (mcref.mc == 0) {
            try helper.write_glb(writer, mcref.glb);
        }

        try helper.write_mc(writer, mcref.mc);

        var wide_mcref = mcref;
        wide_mcref.mc = @as(u4, @truncate(mcref.mc +% 4));

        var narrow_pts: u8 = 5;
        if (wide_mcref.mc > 0) narrow_pts += 5;
        if (wide_mcref.mc < 14) narrow_pts += 5;
        if (wide_mcref.mc < 15) narrow_pts += 5;

        const results_wide = try run_toolchain(ta, tc, dev, wide_mcref, 25, mcref);
        const results_narrow = try run_toolchain(ta, tc, dev, wide_mcref, narrow_pts, mcref);

        var diff = try JEDEC_Data.init_diff(ta, results_narrow.jedec, results_wide.jedec);

        diff.put_range(dev.get_routing_range(), 0);

        var fuse_count: usize = 0;

        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            if (!cluster_routing.isSet(fuse.row)) {
                try helper.write_fuse(writer, fuse);

                const narrow_value = results_narrow.jedec.get(fuse);
                if (default_narrow) |def| {
                    if (narrow_value != def) {
                        try helper.write_value(writer, narrow_value, @tagName(lc4k.Wide_Routing.self));
                    }
                } else {
                    default_narrow = narrow_value;
                }

                const wide_value = results_wide.jedec.get(fuse);
                if (default_wide) |def| {
                    if (wide_value != def) {
                        try helper.write_value(writer, wide_value, @tagName(lc4k.Wide_Routing.self_plus_four));
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
        try helper.write_value(writer, def, @tagName(lc4k.Wide_Routing.self));
    }

    if (default_wide) |def| {
        try helper.write_value(writer, def, @tagName(lc4k.Wide_Routing.self_plus_four));
    }

    try writer.done();
}


fn parseClusterRoutingRows(ta: std.mem.Allocator, pa: std.mem.Allocator, out_device: ?*Device_Info) !std.DynamicBitSet {
    const input_file = helper.get_input_file("cluster_routing.sx") orelse return error.MissingClusterRoutingInputFile;
    const dev = Device_Info.init(input_file.device_type);

    var results = try std.DynamicBitSet.initEmpty(pa, dev.jedec_dimensions.height());

    var reader = std.io.Reader.fixed(input_file.contents);
    var parser = sx.reader(ta, &reader);
    defer parser.deinit();

    parseClusterRoutingRows0(&parser, &results) catch |e| switch (e) {
        error.SExpressionSyntaxError => {
            var ctx = try parser.token_context();
            try ctx.print_for_string(input_file.contents, helper.stderr, 120);
            return e;
        },
        else => return e,
    };

    if (out_device) |ptr| {
        ptr.* = dev;
    }

    return results;
}

fn parseClusterRoutingRows0(parser: *sx.Reader, results: *std.DynamicBitSet) !void {
    _ = try parser.require_any_expression(); // device name, we already know it
    try parser.require_expression("cluster_routing");

    while (try helper.parse_glb(parser)) |_| {
        while (try parser.expression("mc")) {
            _ = try parser.require_any_int(u16, 10);

            while (try parser.expression("fuse")) {
                const row = try parser.require_any_int(u16, 10);
                _ = try parser.require_any_int(u16, 10);

                if (try parser.expression("value")) {
                    try parser.ignore_remaining_expression();
                }

                results.set(row);

                try parser.require_close(); // fuse
            }

            try parser.require_close(); // mc
        }
        try parser.require_close(); // glb
    }
    while (try parser.expression("value")) {
        try parser.ignore_remaining_expression();
    }
    try parser.require_close(); // cluster_routing
    try parser.require_close(); // device
    try parser.require_done();
}