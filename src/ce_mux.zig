const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx.zig");
const core = @import("core.zig");
const jedec = @import("jedec.zig");
const devices = @import("devices.zig");
const JedecData = jedec.JedecData;
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

const ClockEnableSource = enum {
    always,
    shared_pt,
    inv_pt,
    pt,
};

pub fn main() void {
    helper.main(0);
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, mcref: core.MacrocellRef, src: ClockEnableSource) !toolchain.FitResults {
    var design = Design.init(ta, dev);
    var scratch_base: u8 = if (mcref.mc < 8) 8 else 1;

    try design.nodeAssignment(.{
        .signal = "out",
        .glb = mcref.glb,
        .mc = mcref.mc,
    });
    try design.nodeAssignment(.{
        .signal = "ceo",
        .glb = mcref.glb,
    });
    try design.nodeAssignment(.{
        .signal = "out2",
        .glb = mcref.glb,
        .mc = scratch_base,
    });
    try design.nodeAssignment(.{
        .signal = "out3",
        .glb = mcref.glb,
        .mc = scratch_base + 1,
    });
    try design.nodeAssignment(.{
        .signal = "out4",
        .glb = mcref.glb,
        .mc = scratch_base + 2,
    });

    try design.addPT(.{ "ce0", "ce1" }, "ceo");

    try design.addPT("in", "out.D");
    try design.addPT("in2", "out2.D");
    try design.addPT("in3", "out3.D");
    try design.addPT("in4", "out4.D");

    try design.addPT("clk", .{ "out.C", "out2.C", "out3.C", "out4.C" });
    try design.addPT("gce", .{ "out2.CE", "out3.CE", "out4.CE" });

    switch (src) {
        .always => {},
        .shared_pt => {
            try design.addPT("gce", "out.CE");
        },
        .pt => {
            try design.addPT(.{ "ce0", "ce1" }, "out.CE");
        },
        .inv_pt => {
            try design.addPT(.{ "ce0", "ce1" }, "out.CE-");
        },
    }

    var results = try tc.runToolchain(design);
    try helper.logReport("ce_mux_glb{}_mc{}_{s}", .{ mcref.glb, mcref.mc, @tagName(src) }, results);
    try results.checkTerm(false);
    return results;
}

var defaults = std.EnumMap(ClockEnableSource, usize) {};

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("clock_enable_mux");

    var mc_iter = core.MacrocellIterator { .device = dev };
    while (mc_iter.next()) |mcref| {
        try tc.cleanTempDir();
        helper.resetTemp();

        var data = std.EnumMap(ClockEnableSource, JedecData) {};
        var values = std.EnumMap(ClockEnableSource, usize) {};

        var diff = try dev.initJedecZeroes(ta);

        for (std.enums.values(ClockEnableSource)) |src| {
            var results = try runToolchain(ta, tc, dev, mcref, src);
            data.put(src, results.jedec);

            if (src != .always) {
                diff.unionAll(try JedecData.initDiff(ta, results.jedec, data.get(.always).?));
            }
        }

        // ignore differences in PTs and GLB routing
        diff.putRange(dev.getRoutingRange(), 0);

        if (mcref.mc == 0) {
            try writer.expression("glb");
            try writer.printRaw("{}", .{ mcref.glb });
            try writer.expression("name");
            try writer.printRaw("{s}", .{ devices.getGlbName(mcref.glb) });
            try writer.close();

            writer.setCompact(false);
        }

        try writer.expression("mc");
        try writer.printRaw("{}", .{ mcref.mc });

        var bit_value: usize = 1;
        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            try helper.writeFuseOptValue(writer, fuse, bit_value);

            for (std.enums.values(ClockEnableSource)) |src| {
                if (data.get(src).?.isSet(fuse)) {
                    values.put(src, (values.get(src) orelse 0) + bit_value);
                }
            }

            bit_value *= 2;
        }

        if (diff.countSet() != 2) {
            try helper.err("Expected two ce_mux fuses but found {}!", .{ diff.countSet() }, dev, .{ .mcref = mcref });
        }

        for (std.enums.values(ClockEnableSource)) |src| {
            const value = values.get(src) orelse 0;
            if (defaults.get(src)) |default| {
                if (value != default) {
                    try writer.expression("value");
                    try writer.printRaw("{} {s}", .{ value, @tagName(src) });
                    try writer.close();
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

    for (std.enums.values(ClockEnableSource)) |src| {
        if (defaults.get(src)) |default| {
            try writer.expression("value");
            try writer.printRaw("{} {s}", .{ default, @tagName(src) });
            try writer.close();
        }
    }

    try writer.done();

    _ = pa;
}
