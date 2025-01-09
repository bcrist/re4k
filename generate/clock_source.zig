const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const Device_Info = @import("Device_Info.zig");
const JEDEC_Data = lc4k.JEDEC_Data;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

const ClockSource = enum {
    bclk0,
    bclk1,
    bclk2,
    bclk3,
    pt,
    inv_pt,
    shared_pt,
    gnd,
};

pub fn main() void {
    helper.main();
}

fn run_toolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, mcref: lc4k.MC_Ref, src: ClockSource) !toolchain.Fit_Results {
    var design = Design.init(ta, dev);

    const clocks = dev.clock_pins;

    const clk0: []const u8 = "clk0";
    try design.pin_assignment(.{
        .signal = clk0,
        .pin = clocks[0].id,
    });

    var clk1: []const u8 = "clk1";
    const clk2: []const u8 = "clk2";
    var clk3: []const u8 = "clk3";
    if (clocks.len >= 4) {
        try design.pin_assignment(.{
            .signal = clk1,
            .pin = clocks[1].id,
        });
        try design.pin_assignment(.{
            .signal = clk2,
            .pin = clocks[2].id,
        });
        try design.pin_assignment(.{
            .signal = clk3,
            .pin = clocks[3].id,
        });
    } else {
        try design.pin_assignment(.{
            .signal = clk2,
            .pin = clocks[1].id,
        });
        clk1 = "~clk0";
        clk3 = "~clk2";
    }

    try design.node_assignment(.{
        .signal = "out",
        .glb = mcref.glb,
        .mc = mcref.mc,
    });
    try design.add_pt("in", "out.D");

    const scratch_glb: u8 = if (mcref.glb == 0) 1 else 0;
    try design.node_assignment(.{
        .signal = "sck",
        .glb = scratch_glb,
        .mc = 3,
    });
    try design.add_pt(.{}, "sck");

    try design.node_assignment(.{
        .signal = "dum1",
        .glb = mcref.glb,
    });
    try design.add_pt(.{}, "dum1.D");
    try design.add_pt("sck", "dum1.C");

    try design.node_assignment(.{
        .signal = "dum2",
        .glb = mcref.glb,
    });
    try design.add_pt(.{}, "dum2.D");
    try design.add_pt("sck", "dum2.C");

    switch (src) {
        .bclk0 => {
            try design.add_pt(clk0, "out.C");
        },
        .bclk1 => {
            try design.add_pt(clk1, "out.C");
        },
        .bclk2 => {
            try design.add_pt(clk2, "out.C");
        },
        .bclk3 => {
            try design.add_pt(clk3, "out.C");
        },
        .shared_pt => {
            try design.add_pt("sck", "out.C");
        },
        .pt, .inv_pt => {
            try design.node_assignment(.{
                .signal = "a",
                .glb = scratch_glb,
                .mc = 4,
            });
            try design.node_assignment(.{
                .signal = "b",
                .glb = scratch_glb,
                .mc = 5,
            });
            try design.add_pt(.{}, .{ "a", "b" });
            const out_clk = if (src == .pt) "out.C" else "out.C-";
            try design.add_pt(.{ "a", "b" }, out_clk);
        },
        .gnd => {
            try design.add_output("out.C");
        },
    }

    var results = try tc.run_toolchain(design);
    try helper.log_results(dev.device, "clk_mux_glb{}_mc{}_{s}", .{ mcref.glb, mcref.mc, @tagName(src) }, results);
    try results.check_term();
    return results;
}

var defaults = std.EnumMap(ClockSource, usize) {};

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("clock_source");

    var mc_iter = helper.Macrocell_Iterator { .dev = dev };
    while (mc_iter.next()) |mcref| {
        try tc.clean_temp_dir();
        helper.reset_temp();

        var data = std.EnumMap(ClockSource, JEDEC_Data) {};
        var values = std.EnumMap(ClockSource, usize) {};

        var diff = try JEDEC_Data.init_empty(ta, dev.jedec_dimensions);

        for (std.enums.values(ClockSource)) |src| {
            const results = try run_toolchain(ta, tc, dev, mcref, src);
            data.put(src, results.jedec);
        }

        for (&[_]ClockSource { .bclk0, .bclk2, .shared_pt }) |src| {
            diff.union_diff(data.get(src).?, data.get(.gnd).?);
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

            for (std.enums.values(ClockSource)) |src| {
                if (data.get(src).?.is_set(fuse)) {
                    values.put(src, (values.get(src) orelse 0) + bit_value);
                }
            }

            bit_value *= 2;
        }

        if (diff.count_set() != 3) {
            try helper.err("Expected three clock_source fuses but found {}!", .{ diff.count_set() }, dev, .{ .mcref = mcref });
        }

        for (std.enums.values(ClockSource)) |src| {
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

    for (std.enums.values(ClockSource)) |src| {
        if (defaults.get(src)) |default| {
            try helper.write_value(writer, default, src);
        }
    }

    try writer.done();

    _ = pa;
}
