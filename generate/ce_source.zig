const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const Device_Info = @import("Device_Info.zig");
const JEDEC_Data = lc4k.JEDEC_Data;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

const CE_Source = enum {
    always,
    shared_pt,
    inv_pt,
    pt,
};

pub fn main() void {
    helper.main();
}

fn run_toolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, mcref: lc4k.MC_Ref, src: CE_Source) !toolchain.Fit_Results {
    var design = Design.init(ta, dev);
    const scratch_base: u8 = if (mcref.mc < 8) 8 else 1;

    try design.node_assignment(.{
        .signal = "out",
        .glb = mcref.glb,
        .mc = mcref.mc,
    });
    try design.node_assignment(.{
        .signal = "ceo",
        .glb = mcref.glb,
    });
    try design.node_assignment(.{
        .signal = "out2",
        .glb = mcref.glb,
        .mc = scratch_base,
    });
    try design.node_assignment(.{
        .signal = "out3",
        .glb = mcref.glb,
        .mc = scratch_base + 1,
    });
    try design.node_assignment(.{
        .signal = "out4",
        .glb = mcref.glb,
        .mc = scratch_base + 2,
    });

    try design.add_pt(.{ "ce0", "ce1" }, "ceo");

    try design.add_pt("in", "out.D");
    try design.add_pt("in2", "out2.D");
    try design.add_pt("in3", "out3.D");
    try design.add_pt("in4", "out4.D");

    try design.add_pt("clk", .{ "out.C", "out2.C", "out3.C", "out4.C" });
    try design.add_pt("gce", .{ "out2.CE", "out3.CE", "out4.CE" });

    switch (src) {
        .always => {},
        .shared_pt => {
            try design.add_pt("gce", "out.CE");
        },
        .pt => {
            try design.add_pt(.{ "ce0", "ce1" }, "out.CE");
        },
        .inv_pt => {
            try design.add_pt(.{ "ce0", "ce1" }, "out.CE-");
        },
    }

    var results = try tc.run_toolchain(design);
    try helper.log_results(dev.device, "ce_mux_glb{}_mc{}_{s}", .{ mcref.glb, mcref.mc, @tagName(src) }, results);
    try results.check_term();
    return results;
}

var defaults = std.EnumMap(CE_Source, usize) {};

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("clock_enable_source");

    var mc_iter = helper.Macrocell_Iterator { .dev = dev };
    while (mc_iter.next()) |mcref| {
        try tc.clean_temp_dir();
        helper.reset_temp();

        var data = std.EnumMap(CE_Source, JEDEC_Data) {};
        var values = std.EnumMap(CE_Source, usize) {};

        var diff = try JEDEC_Data.init_empty(ta, dev.jedec_dimensions);

        for (std.enums.values(CE_Source)) |src| {
            const results = try run_toolchain(ta, tc, dev, mcref, src);
            data.put(src, results.jedec);

            if (src != .always) {
                diff.union_diff(results.jedec, data.get(.always).?);
            }
        }

        // ignore differences in PTs and GLB routing
        diff.put_range(dev.get_routing_range(), 0);

        if (mcref.mc == 0) {
            try helper.write_glb(writer, mcref.glb);
        }

        try helper.write_mc(writer, mcref.mc);

        var bit_value: usize = 1;
        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            try helper.write_fuse_opt_value(writer, fuse, bit_value);

            for (std.enums.values(CE_Source)) |src| {
                if (data.get(src).?.is_set(fuse)) {
                    values.put(src, (values.get(src) orelse 0) + bit_value);
                }
            }

            bit_value *= 2;
        }

        if (diff.count_set() != 2) {
            try helper.err("Expected two clock_enable_source fuses but found {}!", .{ diff.count_set() }, dev, .{ .mcref = mcref });
        }

        for (std.enums.values(CE_Source)) |src| {
            const value = values.get(src) orelse 0;
            if (defaults.get(src)) |default| {
                if (value != default) {
                    try helper.write_value(writer, value, src);
                }
            } else {
                defaults.put(src, value);
            }
        }

        try writer.close();

        if (mcref.mc == 15) {
            try writer.close();
        }
    }

    for (std.enums.values(CE_Source)) |src| {
        if (defaults.get(src)) |default| {
            try helper.write_value(writer, default, src);
        }
    }

    try writer.done();

    _ = pa;
}
