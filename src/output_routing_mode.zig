const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const jedec = @import("jedec.zig");
const core = @import("core.zig");
const devices = @import("devices.zig");
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JedecData = jedec.JedecData;

pub fn main() void {
    helper.main(0);
}

const ORPMode = enum {
    fast_bypass,
    fast_bypass_inverted,
    orm,
    orm_bypass,
};

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, pin_index: u16, bypass: ORPMode) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    try design.pinAssignment(.{
        .signal = "in",
    });
    try design.pinAssignment(.{
        .signal = "in2",
    });
    try design.pinAssignment(.{
        .signal = "in3",
    });
    try design.pinAssignment(.{
        .signal = "in4",
    });

    var io = dev.getPins()[pin_index].input_output;

    var mc: u8 = 0;
    while (mc < io.mc) : (mc += 1) {
        var signal_name = try std.fmt.allocPrint(ta, "dum{}", .{ mc });
        try design.nodeAssignment(.{
            .signal = signal_name,
            .glb = io.glb,
            .mc = mc,
        });
        try design.addPT(.{ "in", "in2" }, signal_name);
        try design.addPT(.{ "in", "in3" }, signal_name);
        try design.addPT(.{ "in", "in4" }, signal_name);
        try design.addPT(.{ "in2", "in3" }, signal_name);
        try design.addPT(.{ "in2", "in4" }, signal_name);
    }

    var fast_bypass = switch (bypass) {
        .fast_bypass, .fast_bypass_inverted => true,
        else => false,
    };
    try design.pinAssignment(.{
        .signal = "out",
        .pin_index = pin_index,
        .fast_bypass = fast_bypass,
        .orm_bypass = (bypass == .orm_bypass),
    });

    var out_signal = if (bypass == .fast_bypass_inverted) "out.-" else "out";
    try design.addPT("in", out_signal);
    try design.addPT("in2", out_signal);
    try design.addPT("in3", out_signal);
    try design.addPT("in4", out_signal);

    var results = try tc.runToolchain(design);
    try helper.logReport("bypass_pin{}_{s}", .{ pin_index, @tagName(bypass) }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("output_routing_mode");

    var defaults = std.EnumMap(ORPMode, usize) {};

    var pin_iter = devices.pins.OutputIterator { .pins = dev.getPins() };
    while (pin_iter.next()) |io| {
        try tc.cleanTempDir();
        helper.resetTemp();

        var jeds = std.EnumMap(ORPMode, JedecData) {};
        for (std.enums.values(ORPMode)) |mode| {
            const results = try runToolchain(ta, tc, dev, io.pin_index, mode);
            jeds.put(mode, results.jedec);
        }

        // The fitter also sets the XOR invert fuse when .fast_bypass_inverted is used, even though that
        // doesn't affect the bypass path. So we won't include that one when computing the diff:
        var diff = try JedecData.initDiff(ta, jeds.get(.orm).?, jeds.get(.fast_bypass).?);
        diff.unionDiff(jeds.get(.orm).?, jeds.get(.orm_bypass).?);

        try writer.expression("pin");
        try writer.printRaw("{s}", .{ io.pin_number });

        var values = std.EnumMap(ORPMode, usize) {};

        var bit_value: usize = 1;
        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            try helper.writeFuseOptValue(writer, fuse, bit_value);

            for (std.enums.values(ORPMode)) |mode| {
                if (jeds.get(mode)) |jed| {
                    var val = values.get(mode) orelse 0;
                    val |= jed.get(fuse) * bit_value;
                    values.put(mode, val);
                }
            }

            bit_value *= 2;
        }

        for (std.enums.values(ORPMode)) |mode| {
            var val = values.get(mode) orelse 0;
            if (defaults.get(mode)) |def| {
                if (def != val) {

                }
            } else {
                defaults.put(mode, val);
            }
        }

        if (diff.countSet() != 2) {
            try helper.err("Expected two bypass fuses but found {}!", .{ diff.countSet() }, dev, .{ .pin_index = io.pin_index });
        }

        try writer.close();
    }

    for (std.enums.values(ORPMode)) |mode| {
        if (defaults.get(mode)) |def| {
            try writer.expression("value");
            try writer.printRaw("{} {s}", .{ def, @tagName(mode) });
            try writer.close();
        }
    }

    try writer.done();

    _ = pa;
}
