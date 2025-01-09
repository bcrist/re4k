const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const Device_Info = @import("Device_Info.zig");
const Fuse = lc4k.Fuse;
const JEDEC_Data = lc4k.JEDEC_Data;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

pub fn main() void {
    helper.main();
}

fn run_toolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, mcref: lc4k.MC_Ref, init_state: u1) !toolchain.Fit_Results {
    var design = Design.init(ta, dev);
    try design.node_assignment(.{
        .signal = "out",
        .glb = mcref.glb,
        .mc = mcref.mc,
        .init_state = init_state,
    });
    try design.add_pt("in", "out.D");

    var results = try tc.run_toolchain(design);
    try helper.log_results(dev.device, "init_state_glb{}_mc{}_{}", .{ mcref.glb, mcref.mc, init_state }, results);
    try results.check_term();
    return results;
}

var default_set: ?u1 = null;
var default_reset: ?u1 = null;

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("init_state");

    var mc_iter = helper.Macrocell_Iterator { .dev = dev };
    while (mc_iter.next()) |mcref| {
        try tc.clean_temp_dir();
        helper.reset_temp();

        const results_reset = try run_toolchain(ta, tc, dev, mcref, 0);
        const results_set = try run_toolchain(ta, tc, dev, mcref, 1);

        const diff = try JEDEC_Data.init_diff(ta, results_reset.jedec, results_set.jedec);

        if (mcref.mc == 0) {
            try helper.write_glb(writer, mcref.glb);
        }

        try helper.write_mc(writer, mcref.mc);

        var diff_iter = diff.iterator(.{});
        if (diff_iter.next()) |fuse| {
            try writeFuse(fuse, results_reset.jedec, results_set.jedec, writer);
        } else {
            try helper.err("Expected one init state fuse but found none!", .{}, dev, .{ .mcref = mcref });
        }

        if (diff_iter.next()) |fuse| {
            try helper.err("Expected one init state fuse but found multiple!", .{}, dev, .{ .mcref = mcref });
            try writeFuse(fuse, results_reset.jedec, results_set.jedec, writer);

            while (diff_iter.next()) |f| {
                try writeFuse(f, results_reset.jedec, results_set.jedec, writer);
            }
        }

        try writer.close();

        if (mcref.mc == 15) {
            try writer.close();
        }
    }

    if (default_reset) |def| {
        try helper.write_value(writer, def, "reset");
    }

    if (default_set) |def| {
        try helper.write_value(writer, def, "set");
    }

    try writer.done();

    _ = pa;
}

fn writeFuse(fuse: Fuse, results_reset: JEDEC_Data, results_set: JEDEC_Data, writer: *sx.Writer) !void {
    try helper.write_fuse(writer, fuse);

    const value_reset = results_reset.get(fuse);
    if (default_reset) |def| {
        if (value_reset != def) {
            try helper.write_value(writer, value_reset, "reset");
        }
    } else {
        default_reset = value_reset;
    }

    const value_set = results_set.get(fuse);
    if (default_set) |def| {
        if (value_set != def) {
            try helper.write_value(writer, value_set, "set");
        }
    } else {
        default_set = value_set;
    }
}
