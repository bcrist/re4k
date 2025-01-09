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

const BCLK_Mode = enum {
    both_non_inverted,
    second_complemented,
    first_complemented,
    both_inverted,
};

fn run_toolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, glb: u8, mode01: BCLK_Mode, mode23: BCLK_Mode) !toolchain.Fit_Results {
    var design = Design.init(ta, dev);

    const clocks = dev.clock_pins;

    try design.pin_assignment(.{
        .signal = "clk0",
        .pin = clocks[0].id,
    });
    try design.pin_assignment(.{
        .signal = "clk1",
        .pin = clocks[1].id,
    });
    try design.pin_assignment(.{
        .signal = "clk2",
        .pin = clocks[2].id,
    });
    try design.pin_assignment(.{
        .signal = "clk3",
        .pin = clocks[3].id,
    });

    try design.node_assignment(.{
        .signal = "out1",
        .glb = glb,
        .mc = 0,
    });
    try design.node_assignment(.{
        .signal = "out2",
        .glb = glb,
        .mc = 1,
    });
    try design.node_assignment(.{
        .signal = "out3",
        .glb = glb,
        .mc = 2,
    });
    try design.node_assignment(.{
        .signal = "out4",
        .glb = glb,
        .mc = 3,
    });

    try design.add_pt(.{}, .{ "out1.D", "out2.D", "out3.D", "out4.D" });

    switch (mode01) {
        .both_non_inverted => {
            try design.add_pt("clk0", "out1.C");
            try design.add_pt("clk1", "out2.C");
        },
        .second_complemented => {
            try design.add_pt("~clk1", "out1.C");
            try design.add_pt("clk1", "out2.C");
        },
        .first_complemented => {
            try design.add_pt("clk0", "out1.C");
            try design.add_pt("~clk0", "out2.C");
        },
        .both_inverted => {
            try design.add_pt("~clk1", "out1.C");
            try design.add_pt("~clk0", "out2.C");
        },
    }

    switch (mode23) {
        .both_non_inverted => {
            try design.add_pt("clk2", "out3.C");
            try design.add_pt("clk3", "out4.C");
        },
        .second_complemented => {
            try design.add_pt("~clk3", "out3.C");
            try design.add_pt("clk3", "out4.C");
        },
        .first_complemented => {
            try design.add_pt("clk2", "out3.C");
            try design.add_pt("~clk2", "out4.C");
        },
        .both_inverted => {
            try design.add_pt("~clk3", "out3.C");
            try design.add_pt("~clk2", "out4.C");
        },
    }

    var results = try tc.run_toolchain(design);
    try helper.log_results(dev.device, "bclk_polarity_glb{}_{s}_{s}", .{ glb, @tagName(mode01), @tagName(mode23) }, results);
    try results.check_term();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("bclk_polarity");

    var defaults = std.EnumMap(BCLK_Mode, usize) {};

    var glb: u8 = 0;
    while (glb < dev.num_glbs) : (glb += 1) {
        try helper.write_glb(writer, glb);

        var base_clk: usize = 0;
        while (base_clk < 4) : (base_clk += 2) {
            try writer.expression("clk");
            try writer.int(base_clk, 10);
            try writer.int(base_clk + 1, 10);

            try tc.clean_temp_dir();
            helper.reset_temp();

            var jeds = std.EnumMap(BCLK_Mode, JEDEC_Data) {};
            for (std.enums.values(BCLK_Mode)) |mode| {
                const results = try if (base_clk == 0) run_toolchain(ta, tc, dev, glb, mode, .both_non_inverted) else run_toolchain(ta, tc, dev, glb, .both_non_inverted, mode);
                jeds.put(mode, results.jedec);
            }

            const diff = try JEDEC_Data.init_diff(ta, jeds.get(.both_non_inverted).?, jeds.get(.both_inverted).?);

            var values = std.EnumMap(BCLK_Mode, usize) {};

            var bit_value: usize = 1;
            var diff_iter = diff.iterator(.{});
            while (diff_iter.next()) |fuse| {
                try helper.write_fuse_opt_value(writer, fuse, bit_value);

                for (std.enums.values(BCLK_Mode)) |mode| {
                    if (jeds.get(mode)) |jed| {
                        var val: usize = values.get(mode) orelse 0;
                        if (jed.is_set(fuse)) {
                            val |= bit_value;
                        }
                        values.put(mode, val);
                    }
                }

                bit_value *= 2;
            }

            if (diff.count_set() != 2) {
                try helper.err("Expected two bclk polarity fuses, but found {}!", .{ diff.count_set() }, dev, .{ .glb = glb });
            }

            for (std.enums.values(BCLK_Mode)) |mode| {
                const val: usize = values.get(mode) orelse 0;
                if (defaults.get(mode)) |def| {
                    if (def != val) {
                        try helper.err("Expected all glbs and clock pairs to share the same bit patterns!", .{}, dev, .{ .glb = glb });
                    }
                } else {
                    defaults.put(mode, val);
                }
            }
            try writer.close(); // clk
        }
        try writer.close(); // glb
    }

    var default_iter = defaults.iterator();
    while (default_iter.next()) |entry| {
        try helper.write_value(writer, entry.value.*, entry.key);
    }

    try writer.done();

    _ = pa;
}
