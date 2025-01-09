const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const Device_Info = @import("Device_Info.zig");
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JEDEC_Data = lc4k.JEDEC_Data;

pub fn main() void {
    helper.main();
}

fn run_toolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, mcref: lc4k.MC_Ref, invert: bool) !toolchain.Fit_Results {
    var design = Design.init(ta, dev);

    try design.pin_assignment(.{
        .signal = "in",
    });
    try design.node_assignment(.{
        .signal = "out",
        .glb = mcref.glb,
        .mc = mcref.mc,
    });
    if (invert) {
        try design.add_pt("in", "out.D-");
    } else {
        try design.add_pt("in", "out.D");
    }

    var results = try tc.run_toolchain(design);
    try helper.log_results(dev.device, "invert_glb{}_mc{}_{}", .{ mcref.glb, mcref.mc, invert }, results);
    try results.check_term();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("invert");

    var default_normal: ?u1 = null;
    var default_invert: ?u1 = null;

    var mc_iter = helper.Macrocell_Iterator { .dev = dev };
    while (mc_iter.next()) |mcref| {
        try tc.clean_temp_dir();
        helper.reset_temp();

        const results_normal = try run_toolchain(ta, tc, dev, mcref, false);
        const results_invert = try run_toolchain(ta, tc, dev, mcref, true);

        const diff = try JEDEC_Data.init_diff(ta, results_normal.jedec, results_invert.jedec);

        if (mcref.mc == 0) {
            try helper.write_glb(writer, mcref.glb);
        }

        try helper.write_mc(writer, mcref.mc);

        var diff_iter = diff.iterator(.{});
        if (diff_iter.next()) |fuse| {
            try helper.write_fuse(writer, fuse);

            const normal_value = results_normal.jedec.get(fuse);
            if (default_normal) |def| {
                if (normal_value != def) {
                    try helper.write_value(writer, normal_value, "disabled");
                }
            } else {
                default_normal = normal_value;
            }

            const invert_value = results_invert.jedec.get(fuse);
            if (default_invert) |def| {
                if (invert_value != def) {
                    try helper.write_value(writer, invert_value, "enabled");
                }
            } else {
                default_invert = invert_value;
            }

        } else {
            try helper.err("Expected one invert fuse but found none!", .{}, dev, .{ .mcref = mcref });
            return error.Think;
        }

        if (diff_iter.next()) |_| {
            try helper.err("Expected one invert fuse but found multiple!", .{}, dev, .{ .mcref = mcref });
            return error.Think;
        }

        try writer.close();

        if (mcref.mc == 15) {
            try writer.close();
        }
    }

    if (default_normal) |def| {
        try helper.write_value(writer, def, "disabled");
    }

    if (default_invert) |def| {
        try helper.write_value(writer, def, "enabled");
    }

    try writer.done();

    _ = pa;
}
