const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const core = @import("core.zig");
const jedec = @import("jedec.zig");
const devices = @import("devices.zig");
const JedecData = jedec.JedecData;
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

const ClockSource = enum {
    clk0,
    clk1,
    clk2,
    clk3,
    pt,
    inv_pt,
    shared_pt,
    gnd,
};

pub fn main() void {
    helper.main(0);
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, mcref: core.MacrocellRef, src: ClockSource) !toolchain.FitResults {
    var design = Design.init(ta, dev);


    const clk0: []const u8 = "clk0";
    try design.pinAssignment(.{
        .signal = clk0,
        .pin_index = dev.getClockPin(0).?.pin_index,
    });

    var clk1: []const u8 = "clk1";
    if (dev.getClockPin(1)) |info| {
        try design.pinAssignment(.{
            .signal = clk1,
            .pin_index = info.pin_index,
        });
    } else {
        clk1 = "~clk0";
    }

    const clk2: []const u8 = "clk2";
    try design.pinAssignment(.{
        .signal = clk2,
        .pin_index = dev.getClockPin(2).?.pin_index,
    });

    var clk3: []const u8 = "clk3";
    if (dev.getClockPin(3)) |info| {
        try design.pinAssignment(.{
            .signal = clk3,
            .pin_index = info.pin_index,
        });
    } else {
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
        .clk0 => {
            try design.addPT(clk0, "out.C");
        },
        .clk1 => {
            try design.addPT(clk1, "out.C");
        },
        .clk2 => {
            try design.addPT(clk2, "out.C");
        },
        .clk3 => {
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
    try helper.logResults("clk_mux_glb{}_mc{}_{s}", .{ mcref.glb, mcref.mc, @tagName(src) }, results);
    try results.checkTerm();
    return results;
}

var defaults = std.EnumMap(ClockSource, usize) {};

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("clock_mux");

    var mc_iter = core.MacrocellIterator { .device = dev };
    while (mc_iter.next()) |mcref| {
        try tc.cleanTempDir();
        helper.resetTemp();

        var data = std.EnumMap(ClockSource, JedecData) {};
        var values = std.EnumMap(ClockSource, usize) {};

        var diff = try dev.initJedecZeroes(ta);

        for (std.enums.values(ClockSource)) |src| {
            var results = try runToolchain(ta, tc, dev, mcref, src);
            data.put(src, results.jedec);
        }

        for (&[_]ClockSource { .clk0, .clk2, .shared_pt }) |src| {
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
            try helper.err("Expected three clk_mux fuses but found {}!", .{ diff.countSet() }, dev, .{ .mcref = mcref });
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
