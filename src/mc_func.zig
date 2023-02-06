const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const common = @import("common");
const jedec = @import("jedec");
const device_info = @import("device_info.zig");
const JedecData = jedec.JedecData;
const DeviceInfo = device_info.DeviceInfo;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

pub fn main() void {
    helper.main();
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, mcref: common.MacrocellRef, func: common.MacrocellFunction) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    try design.nodeAssignment(.{
        .signal = "out",
        .glb = mcref.glb,
        .mc = mcref.mc,
    });

    switch (func) {
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
    try helper.logResults(dev.device, "mc_func_glb{}_mc{}_{s}", .{ mcref.glb, mcref.mc, @tagName(func) }, results);
    try results.checkTerm();
    return results;
}

var defaults = std.EnumMap(common.MacrocellFunction, usize) {};

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev.device));
    try writer.expressionExpanded("macrocell_function");

    var mc_iter = helper.MacrocellIterator { .dev = dev };
    while (mc_iter.next()) |mcref| {
        try tc.cleanTempDir();
        helper.resetTemp();

        var data = std.EnumMap(common.MacrocellFunction, JedecData) {};
        for (std.enums.values(common.MacrocellFunction)) |reg_type| {
            var results = try runToolchain(ta, tc, dev, mcref, reg_type);
            data.put(reg_type, results.jedec);
        }

        var diff = try JedecData.initEmpty(ta, dev.jedec_dimensions);
        for (&[_]common.MacrocellFunction { .d_ff, .t_ff }) |reg_type| {
            diff.unionDiff(data.get(reg_type).?, data.get(.latch).?);
        }

        // ignore differences in PTs and GLB routing
        diff.putRange(dev.getRoutingRange(), 0);

        if (mcref.mc == 0) {
            try helper.writeGlb(writer, mcref.glb);
        }

        try helper.writeMc(writer, mcref.mc);

        var values = std.EnumMap(common.MacrocellFunction, usize) {};
        var bit_value: usize = 1;
        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            try helper.writeFuseOptValue(writer, fuse, bit_value);

            for (std.enums.values(common.MacrocellFunction)) |reg_type| {
                if (data.get(reg_type).?.isSet(fuse)) {
                    values.put(reg_type, (values.get(reg_type) orelse 0) + bit_value);
                }
            }

            bit_value *= 2;
        }

        if (diff.countSet() != 2) {
            try helper.err("Expected two macrocell function fuses but found {}!", .{ diff.countSet() }, dev, .{ .mcref = mcref });
        }

        for (std.enums.values(common.MacrocellFunction)) |reg_type| {
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

    for (std.enums.values(common.MacrocellFunction)) |reg_type| {
        if (defaults.get(reg_type)) |default| {
            try helper.writeValue(writer, default, reg_type);
        }
    }

    try writer.done();

    _ = pa;
}
