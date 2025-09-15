const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const Device_Info = @import("Device_Info.zig");
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JEDEC_Data = lc4k.JEDEC_Data;

pub const main = helper.main;

fn run_toolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, mcref: lc4k.MC_Ref, xor: bool) !toolchain.Fit_Results {
    var design = Design.init(ta, dev);

    try design.pin_assignment(.{
        .signal = "x0",
    });
    try design.pin_assignment(.{
        .signal = "x1",
    });
    try design.pin_assignment(.{
        .signal = "x2",
    });
    try design.pin_assignment(.{
        .signal = "x3",
    });
    try design.pin_assignment(.{
        .signal = "x4",
    });

    var mc: u8 = 0;
    while (mc < mcref.mc) : (mc += 1) {
        const signal_name = try std.fmt.allocPrint(ta, "dum{}", .{ mc });
        try design.node_assignment(.{
            .signal = signal_name,
            .glb = mcref.glb,
            .mc = mc,
        });
        try design.add_pt("x0", signal_name);
        try design.add_pt("x1", signal_name);
        try design.add_pt("x2", signal_name);
        try design.add_pt("x3", signal_name);
        try design.add_pt("x4", signal_name);
    }

    try design.node_assignment(.{
        .signal = "out",
        .glb = mcref.glb,
        .mc = mcref.mc,
    });
    try design.add_pt("x0", "out.D");
    if (!xor) {
        try design.add_pt("x1", "out.D");
    }

    var results = try tc.run_toolchain(design);
    try helper.log_results(dev.device, "pt0_xor_glb{}_mc{}_{}", .{ mcref.glb, mcref.mc, xor }, results);
    try results.check_term();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("pt0_xor");

    var default_disabled: ?u1 = null;
    var default_enabled: ?u1 = null;

    var mc_iter = helper.Macrocell_Iterator { .dev = dev };
    while (mc_iter.next()) |mcref| {
        try tc.clean_temp_dir();
        helper.reset_temp();

        const results_disabled = try run_toolchain(ta, tc, dev, mcref, false);
        const results_enabled = try run_toolchain(ta, tc, dev, mcref, true);

        var diff = try JEDEC_Data.init_diff(ta, results_disabled.jedec, results_enabled.jedec);

        diff.put_range(dev.get_routing_range(), 0);

        if (mcref.mc == 0) {
            try helper.write_glb(writer, mcref.glb);
        }

        try helper.write_mc(writer, mcref.mc);

        var diff_iter = diff.iterator(.{});
        if (diff_iter.next()) |fuse| {
            try helper.write_fuse(writer, fuse);

            const disabled_value = results_disabled.jedec.get(fuse);
            if (default_disabled) |def| {
                if (disabled_value != def) {
                    try helper.write_value(writer, disabled_value, "disabled");
                }
            } else {
                default_disabled = disabled_value;
            }

            const enabled_value = results_enabled.jedec.get(fuse);
            if (default_enabled) |def| {
                if (enabled_value != def) {
                    try helper.write_value(writer, enabled_value, "enabled");
                }
            } else {
                default_enabled = enabled_value;
            }

        } else {
            try helper.err("Expected one pt0_xor fuse but found none!", .{}, dev, .{ .mcref = mcref });
        }

        while (diff_iter.next()) |fuse| {
            try helper.err("Expected one pt0_xor fuse but found multiple: {}:{}", .{ fuse.row, fuse.col }, dev, .{ .mcref = mcref });
        }

        try writer.close();

        if (mcref.mc == 15) {
            try writer.close();
        }
    }

    if (default_disabled) |def| {
        try helper.write_value(writer, def, "disabled");
    }

    if (default_enabled) |def| {
        try helper.write_value(writer, def, "enabled");
    }

    try writer.done();

    _ = pa;
}
