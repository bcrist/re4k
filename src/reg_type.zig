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

pub fn main() void {
    helper.main(0);
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, mcref: core.MacrocellRef, reg_type: core.MacrocellType) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    try design.nodeAssignment(.{
        .signal = "out",
        .glb = mcref.glb,
        .mc = mcref.mc,
    });

    switch (reg_type) {
        .combinational => {
            try design.addPT("in", "out");
        },
        .latch => {
            try design.addPT("in", "out.D");
            try design.addPT("clk", "out.LH");
        },
        .d_ff => {
            try design.addPT("in", "out.D");
            try design.addPT("clk", "out.C");
        },
        .t_ff => {
            try design.addPT("in", "out.T");
            try design.addPT("clk", "out.C");
        },
    }

    var results = try tc.runToolchain(design);
    try helper.logResults("reg_type_glb{}_mc{}_{s}", .{ mcref.glb, mcref.mc, @tagName(reg_type) }, results);
    try results.checkTerm();
    return results;
}

var defaults = std.EnumMap(core.MacrocellType, usize) {};

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("register_type");

    var mc_iter = core.MacrocellIterator { .device = dev };
    while (mc_iter.next()) |mcref| {
        try tc.cleanTempDir();
        helper.resetTemp();

        var data = std.EnumMap(core.MacrocellType, JedecData) {};
        for (std.enums.values(core.MacrocellType)) |reg_type| {
            var results = try runToolchain(ta, tc, dev, mcref, reg_type);
            data.put(reg_type, results.jedec);
        }

        var diff = try dev.initJedecZeroes(ta);
        for (&[_]core.MacrocellType { .d_ff, .t_ff }) |reg_type| {
            diff.unionDiff(data.get(reg_type).?, data.get(.latch).?);
        }

        // ignore differences in PTs and GLB routing
        diff.putRange(dev.getRoutingRange(), 0);

        if (mcref.mc == 0) {
            try helper.writeGlb(writer, mcref.glb);
        }

        try helper.writeMc(writer, mcref.mc);

        var values = std.EnumMap(core.MacrocellType, usize) {};
        var bit_value: usize = 1;
        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            try helper.writeFuseOptValue(writer, fuse, bit_value);

            for (std.enums.values(core.MacrocellType)) |reg_type| {
                if (data.get(reg_type).?.isSet(fuse)) {
                    values.put(reg_type, (values.get(reg_type) orelse 0) + bit_value);
                }
            }

            bit_value *= 2;
        }

        if (diff.countSet() != 2) {
            try helper.err("Expected two reg_type fuses but found {}!", .{ diff.countSet() }, dev, .{ .mcref = mcref });
        }

        for (std.enums.values(core.MacrocellType)) |reg_type| {
            const value = values.get(reg_type) orelse 0;
            if (defaults.get(reg_type)) |default| {
                if (value != default) {
                    try helper.writeValue(writer, value, reg_type);
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

    for (std.enums.values(core.MacrocellType)) |reg_type| {
        if (defaults.get(reg_type)) |default| {
            try helper.writeValue(writer, default, reg_type);
        }
    }

    try writer.done();

    _ = pa;
}
