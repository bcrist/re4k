const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const jedec = @import("jedec");
const common = @import("common");
const device_info = @import("device_info.zig");
const DeviceInfo = device_info.DeviceInfo;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JedecData = jedec.JedecData;

pub fn main() void {
    helper.main(0);
}

const BClkMode = enum {
    both_non_inverted,
    second_complemented,
    first_complemented,
    both_inverted,
};

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, glb: u8, mode01: BClkMode, mode23: BClkMode) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    const clocks = dev.clock_pins;

    try design.pinAssignment(.{
        .signal = "clk0",
        .pin = clocks[0].id,
    });
    try design.pinAssignment(.{
        .signal = "clk1",
        .pin = clocks[1].id,
    });
    try design.pinAssignment(.{
        .signal = "clk2",
        .pin = clocks[2].id,
    });
    try design.pinAssignment(.{
        .signal = "clk3",
        .pin = clocks[3].id,
    });

    try design.nodeAssignment(.{
        .signal = "out1",
        .glb = glb,
        .mc = 0,
    });
    try design.nodeAssignment(.{
        .signal = "out2",
        .glb = glb,
        .mc = 1,
    });
    try design.nodeAssignment(.{
        .signal = "out3",
        .glb = glb,
        .mc = 2,
    });
    try design.nodeAssignment(.{
        .signal = "out4",
        .glb = glb,
        .mc = 3,
    });

    try design.addPT(.{}, .{ "out1.D", "out2.D", "out3.D", "out4.D" });

    switch (mode01) {
        .both_non_inverted => {
            try design.addPT("clk0", "out1.C");
            try design.addPT("clk1", "out2.C");
        },
        .second_complemented => {
            try design.addPT("~clk1", "out1.C");
            try design.addPT("clk1", "out2.C");
        },
        .first_complemented => {
            try design.addPT("clk0", "out1.C");
            try design.addPT("~clk0", "out2.C");
        },
        .both_inverted => {
            try design.addPT("~clk1", "out1.C");
            try design.addPT("~clk0", "out2.C");
        },
    }

    switch (mode23) {
        .both_non_inverted => {
            try design.addPT("clk2", "out3.C");
            try design.addPT("clk3", "out4.C");
        },
        .second_complemented => {
            try design.addPT("~clk3", "out3.C");
            try design.addPT("clk3", "out4.C");
        },
        .first_complemented => {
            try design.addPT("clk2", "out3.C");
            try design.addPT("~clk2", "out4.C");
        },
        .both_inverted => {
            try design.addPT("~clk3", "out3.C");
            try design.addPT("~clk2", "out4.C");
        },
    }

    var results = try tc.runToolchain(design);
    try helper.logResults(dev.device, "bclk_polarity_glb{}_{s}_{s}", .{ glb, @tagName(mode01), @tagName(mode23) }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev.device));
    try writer.expressionExpanded("bclk_polarity");

    var defaults = std.EnumMap(BClkMode, usize) {};

    var glb: u8 = 0;
    while (glb < dev.num_glbs) : (glb += 1) {
        try helper.writeGlb(writer, glb);

        var base_clk: usize = 0;
        while (base_clk < 4) : (base_clk += 2) {
            try writer.expression("clk");
            try writer.int(base_clk, 10);
            try writer.int(base_clk + 1, 10);

            try tc.cleanTempDir();
            helper.resetTemp();

            var jeds = std.EnumMap(BClkMode, JedecData) {};
            for (std.enums.values(BClkMode)) |mode| {
                var results = try if (base_clk == 0) runToolchain(ta, tc, dev, glb, mode, .both_non_inverted) else runToolchain(ta, tc, dev, glb, .both_non_inverted, mode);
                jeds.put(mode, results.jedec);
            }

            const diff = try JedecData.initDiff(ta, jeds.get(.both_non_inverted).?, jeds.get(.both_inverted).?);

            var values = std.EnumMap(BClkMode, usize) {};

            var bit_value: usize = 1;
            var diff_iter = diff.iterator(.{});
            while (diff_iter.next()) |fuse| {
                try helper.writeFuseOptValue(writer, fuse, bit_value);

                for (std.enums.values(BClkMode)) |mode| {
                    if (jeds.get(mode)) |jed| {
                        var val: usize = values.get(mode) orelse 0;
                        if (jed.isSet(fuse)) {
                            val |= bit_value;
                        }
                        values.put(mode, val);
                    }
                }

                bit_value *= 2;
            }

            if (diff.countSet() != 2) {
                try helper.err("Expected two bclk polarity fuses, but found {}!", .{ diff.countSet() }, dev, .{ .glb = glb });
            }

            for (std.enums.values(BClkMode)) |mode| {
                var val: usize = values.get(mode) orelse 0;
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
        try helper.writeValue(writer, entry.value.*, entry.key);
    }

    try writer.done();

    _ = pa;
}
