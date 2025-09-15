const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const Device_Info = @import("Device_Info.zig");
const JEDEC_Data = lc4k.JEDEC_Data;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

pub const main = helper.main;

fn run_toolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, mcref: lc4k.MC_Ref, pt3_ar: bool) !toolchain.Fit_Results {
    var design = Design.init(ta, dev);

    try design.node_assignment(.{
        .signal = "out",
        .glb = mcref.glb,
        .mc = mcref.mc,
        .init_state = 0,
    });
    try design.add_pt("in", "out.D");

    if (pt3_ar) {
        try design.add_pt("as", "out.AR");
    } else {
        try design.add_pt("gas", "out.AR");
    }

    // make sure "as" is configured as an input even when not used in the macrocell we're testing:
    const scratch_glb: u8 = if (mcref.glb == 0) 1 else 0;
    try design.node_assignment(.{
        .signal = "dum",
        .glb = scratch_glb,
        .mc = 0,
        .init_state = 0,
    });
    try design.add_pt("in", "dum.D");
    try design.add_pt("as", "dum.AR");

    // make sure "gas" is assigned to the shared init PT by using as such in another MC within the same GLB:
    const scratch_mc: u8 = if (mcref.mc == 0) 15 else mcref.mc - 1;
    try design.node_assignment(.{
        .signal = "gdum",
        .glb = mcref.glb,
        .mc = scratch_mc,
        .init_state = 0,
    });
    try design.add_pt("in", "gdum.D");
    try design.add_pt("gas", "gdum.AR");

    var results = try tc.run_toolchain(design);
    try helper.log_results(dev.device, "pt3_reset_glb{}_mc{}_{}", .{ mcref.glb, mcref.mc, pt3_ar }, results);
    try results.check_term();
    return results;
}

var default_off: ?usize = null;
var default_on: ?usize = null;

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("init_source");

    var mc_iter = helper.Macrocell_Iterator { .dev = dev };
    while (mc_iter.next()) |mcref| {
        try tc.clean_temp_dir();
        helper.reset_temp();

        const results_off = try run_toolchain(ta, tc, dev, mcref, false);
        const results_on = try run_toolchain(ta, tc, dev, mcref, true);

        var diff = try JEDEC_Data.init_diff(ta, results_off.jedec, results_on.jedec);

        // ignore differences in PTs and GLB routing
        diff.put_range(dev.get_routing_range(), 0);

        if (mcref.mc == 0) {
            try helper.write_glb(writer, mcref.glb);
        }

        try helper.write_mc(writer, mcref.mc);

        var value_off: usize = 0;
        var value_on: usize = 0;

        var bit_value: usize = 1;
        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            try helper.write_fuse_opt_value(writer, fuse, bit_value);

            if (results_off.jedec.is_set(fuse)) {
                value_off |= bit_value;
            }
            if (results_on.jedec.is_set(fuse)) {
                value_on |= bit_value;
            }

            bit_value *= 2;
        }

        if (diff.count_set() != 1) {
            try helper.err("Expected one init_source fuse but found {}!", .{ diff.count_set() }, dev, .{ .mcref = mcref });
        }

        if (default_off) |def| {
            if (value_off != def) {
                try helper.write_value(writer, value_off, "shared_pt");
            }
        } else {
            default_off = value_off;
        }

        if (default_on) |def| {
            if (value_on != def) {
                try helper.write_value(writer, value_on, "pt3");
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
        try helper.write_value(writer, def, "shared_pt");
    }

    if (default_on) |def| {
        try helper.write_value(writer, def, "pt3");
    }

    try writer.done();

    _ = pa;
}
