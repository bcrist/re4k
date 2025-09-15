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

fn run_toolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, mcref: lc4k.MC_Ref, func: lc4k.Macrocell_Function) !toolchain.Fit_Results {
    var design = Design.init(ta, dev);

    try design.node_assignment(.{
        .signal = "out",
        .glb = mcref.glb,
        .mc = mcref.mc,
    });

    switch (func) {
        .combinational => {
            try design.add_pt("in", "out");
        },
        .latch => {
            try design.add_pt("in", "out.D");
            try design.add_pt("clk", "out.LH");
        },
        .d_ff => {
            try design.add_pt("in", "out.D");
            try design.add_pt("clk", "out.C");
        },
        .t_ff => {
            try design.add_pt("in", "out.T");
            try design.add_pt("clk", "out.C");
        },
    }

    var results = try tc.run_toolchain(design);
    try helper.log_results(dev.device, "mc_func_glb{}_mc{}_{s}", .{ mcref.glb, mcref.mc, @tagName(func) }, results);
    try results.check_term();
    return results;
}

var defaults = std.EnumMap(lc4k.Macrocell_Function, usize) {};

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("macrocell_function");

    var mc_iter = helper.Macrocell_Iterator { .dev = dev };
    while (mc_iter.next()) |mcref| {
        try tc.clean_temp_dir();
        helper.reset_temp();

        var data = std.EnumMap(lc4k.Macrocell_Function, JEDEC_Data) {};
        for (std.enums.values(lc4k.Macrocell_Function)) |reg_type| {
            const results = try run_toolchain(ta, tc, dev, mcref, reg_type);
            data.put(reg_type, results.jedec);
        }

        var diff = try JEDEC_Data.init_empty(ta, dev.jedec_dimensions);
        for (&[_]lc4k.Macrocell_Function { .d_ff, .t_ff }) |reg_type| {
            diff.union_diff(data.get(reg_type).?, data.get(.latch).?);
        }

        // ignore differences in PTs and GLB routing
        diff.put_range(dev.get_routing_range(), 0);

        if (mcref.mc == 0) {
            try helper.write_glb(writer, mcref.glb);
        }

        try helper.write_mc(writer, mcref.mc);

        var values = std.EnumMap(lc4k.Macrocell_Function, usize) {};
        var bit_value: usize = 1;
        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            try helper.write_fuse_opt_value(writer, fuse, bit_value);

            for (std.enums.values(lc4k.Macrocell_Function)) |reg_type| {
                if (data.get(reg_type).?.is_set(fuse)) {
                    values.put(reg_type, (values.get(reg_type) orelse 0) + bit_value);
                }
            }

            bit_value *= 2;
        }

        if (diff.count_set() != 2) {
            try helper.err("Expected two macrocell function fuses but found {}!", .{ diff.count_set() }, dev, .{ .mcref = mcref });
        }

        for (std.enums.values(lc4k.Macrocell_Function)) |reg_type| {
            const value = values.get(reg_type) orelse 0;
            if (defaults.get(reg_type)) |default| {
                if (value != default) {
                    try helper.write_value(writer, value, reg_type);
                }
            } else {
                defaults.put(reg_type, value);
            }
        }

        try writer.close();

        if (mcref.mc == 15) {
            try writer.close();
        }
    }

    for (std.enums.values(lc4k.Macrocell_Function)) |reg_type| {
        if (defaults.get(reg_type)) |default| {
            try helper.write_value(writer, default, reg_type);
        }
    }

    try writer.done();

    _ = pa;
}
