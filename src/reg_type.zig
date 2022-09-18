const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx.zig");
const core = @import("core.zig");
const jedec = @import("jedec.zig");
const devices = @import("devices/devices.zig");
const JedecData = jedec.JedecData;
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

pub fn main() void {
    helper.main();
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
    try helper.logReport("reg_type_glb{}_mc{}_{s}", .{ mcref.glb, mcref.mc, @tagName(reg_type) }, results);
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

        var diff = try JedecData.initEmpty(ta, dev.getJedecWidth(), dev.getJedecHeight());
        for (&[_]core.MacrocellType { .d_ff, .t_ff }) |reg_type| {
            diff.raw.setUnion((try helper.diff(ta, data.get(reg_type).?, data.get(.latch).?)).raw);
        }

        // ignore differences in PTs and GLB routing
        diff.setRange(0, 0, dev.getNumGlbInputs() * 2, dev.getJedecWidth(), 0);

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

        var values = std.EnumMap(core.MacrocellType, usize) {};
        var bit_value: usize = 1;
        var diff_iter = diff.raw.iterator(.{});
        while (diff_iter.next()) |fuse| {
            const row = diff.getRow(@intCast(u32, fuse));
            const col = diff.getColumn(@intCast(u32, fuse));

            try writer.expression("fuse");
            try writer.printRaw("{}", .{ row });
            try writer.printRaw("{}", .{ col });

            if (bit_value != 1) {
                try writer.expression("value");
                try writer.printRaw("{}", .{ bit_value });
                try writer.close();
            }

            for (std.enums.values(core.MacrocellType)) |reg_type| {
                if (data.get(reg_type).?.raw.isSet(fuse)) {
                    values.put(reg_type, (values.get(reg_type) orelse 0) + bit_value);
                }
            }

            try writer.close();

            bit_value *= 2;
        }

        if (diff.raw.count() != 2) {
            try std.io.getStdErr().writer().print("Expected two reg_type fuses for device {s} glb {} mc {} but found {}!\n", .{ @tagName(dev), mcref.glb, mcref.mc, diff.raw.count() });
        }

        for (std.enums.values(core.MacrocellType)) |reg_type| {
            const value = values.get(reg_type) orelse 0;
            if (defaults.get(reg_type)) |default| {
                if (value != default) {
                    try writer.expression("value");
                    try writer.printRaw("{} {s}", .{ value, @tagName(reg_type) });
                    try writer.close();
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
            try writer.expression("value");
            try writer.printRaw("{} {s}", .{ default, @tagName(reg_type) });
            try writer.close();
        }
    }

    try writer.done();

    _ = pa;
}