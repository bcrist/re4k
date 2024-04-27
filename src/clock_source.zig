const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const jedec = lc4k.jedec;
const device_info = @import("device_info.zig");
const JedecData = jedec.JedecData;
const DeviceInfo = device_info.DeviceInfo;
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

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, mcref: lc4k.MacrocellRef, src: ClockSource) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    const clocks = dev.clock_pins;

    const clk0: []const u8 = "clk0";
    try design.pinAssignment(.{
        .signal = clk0,
        .pin = clocks[0].id,
    });

    var clk1: []const u8 = "clk1";
    const clk2: []const u8 = "clk2";
    var clk3: []const u8 = "clk3";
    if (clocks.len >= 4) {
        try design.pinAssignment(.{
            .signal = clk1,
            .pin = clocks[1].id,
        });
        try design.pinAssignment(.{
            .signal = clk2,
            .pin = clocks[2].id,
        });
        try design.pinAssignment(.{
            .signal = clk3,
            .pin = clocks[3].id,
        });
    } else {
        try design.pinAssignment(.{
            .signal = clk2,
            .pin = clocks[1].id,
        });
        clk1 = "~clk0";
        clk3 = "~clk2";
    }

    try design.nodeAssignment(.{
        .signal = "out",
        .glb = mcref.glb,
        .mc = mcref.mc,
    });
    try design.addPT("in", "out.D");

    const scratch_glb: u8 = if (mcref.glb == 0) 1 else 0;
    try design.nodeAssignment(.{
        .signal = "sck",
        .glb = scratch_glb,
        .mc = 3,
    });
    try design.addPT(.{}, "sck");

    try design.nodeAssignment(.{
        .signal = "dum1",
        .glb = mcref.glb,
    });
    try design.addPT(.{}, "dum1.D");
    try design.addPT("sck", "dum1.C");

    try design.nodeAssignment(.{
        .signal = "dum2",
        .glb = mcref.glb,
    });
    try design.addPT(.{}, "dum2.D");
    try design.addPT("sck", "dum2.C");

    switch (src) {
        .bclk0 => {
            try design.addPT(clk0, "out.C");
        },
        .bclk1 => {
            try design.addPT(clk1, "out.C");
        },
        .bclk2 => {
            try design.addPT(clk2, "out.C");
        },
        .bclk3 => {
            try design.addPT(clk3, "out.C");
        },
        .shared_pt => {
            try design.addPT("sck", "out.C");
        },
        .pt, .inv_pt => {
            try design.nodeAssignment(.{
                .signal = "a",
                .glb = scratch_glb,
                .mc = 4,
            });
            try design.nodeAssignment(.{
                .signal = "b",
                .glb = scratch_glb,
                .mc = 5,
            });
            try design.addPT(.{}, .{ "a", "b" });
            const out_clk = if (src == .pt) "out.C" else "out.C-";
            try design.addPT(.{ "a", "b" }, out_clk);
        },
        .gnd => {
            try design.addOutput("out.C");
        },
    }

    var results = try tc.runToolchain(design);
    try helper.logResults(dev.device, "clk_mux_glb{}_mc{}_{s}", .{ mcref.glb, mcref.mc, @tagName(src) }, results);
    try results.checkTerm();
    return results;
}

var defaults = std.EnumMap(ClockSource, usize) {};

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer) !void {
    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("clock_source");

    var mc_iter = helper.MacrocellIterator { .dev = dev };
    while (mc_iter.next()) |mcref| {
        try tc.cleanTempDir();
        helper.resetTemp();

        var data = std.EnumMap(ClockSource, JedecData) {};
        var values = std.EnumMap(ClockSource, usize) {};

        var diff = try JedecData.initEmpty(ta, dev.jedec_dimensions);

        for (std.enums.values(ClockSource)) |src| {
            const results = try runToolchain(ta, tc, dev, mcref, src);
            data.put(src, results.jedec);
        }

        for (&[_]ClockSource { .bclk0, .bclk2, .shared_pt }) |src| {
            diff.unionDiff(data.get(src).?, data.get(.gnd).?);
        }

        // ignore differences in PTs and GLB routing
        diff.putRange(dev.getRoutingRange(), 0);

        if (mcref.mc == 0) {
            try helper.writeGlb(writer, mcref.glb);
        }

        try helper.writeMc(writer, mcref.mc);

        var bit_value: usize = 1;
        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            try helper.writeFuseOptValue(writer, fuse, bit_value);

            for (std.enums.values(ClockSource)) |src| {
                if (data.get(src).?.isSet(fuse)) {
                    values.put(src, (values.get(src) orelse 0) + bit_value);
                }
            }

            bit_value *= 2;
        }

        if (diff.countSet() != 3) {
            try helper.err("Expected three clock_source fuses but found {}!", .{ diff.countSet() }, dev, .{ .mcref = mcref });
        }

        for (std.enums.values(ClockSource)) |src| {
            const value = values.get(src) orelse 0;
            if (defaults.get(src)) |default| {
                if (value != default) {
                    try helper.writeValue(writer, value, src);
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
            try helper.writeValue(writer, default, src);
        }
    }

    try writer.done();

    _ = pa;
}
