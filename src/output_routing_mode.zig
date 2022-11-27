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

const ORPMode = enum {
    fast_bypass,
    fast_bypass_inverted,
    orm,
    orm_bypass,
};

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, pin: common.PinInfo, bypass: ORPMode) !toolchain.FitResults {
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

    const pin_mc = pin.mcRef().?.mc;

    var mc: u8 = 0;
    while (mc < pin_mc) : (mc += 1) {
        var signal_name = try std.fmt.allocPrint(ta, "dum{}", .{ mc });
        try design.nodeAssignment(.{
            .signal = signal_name,
            .glb = pin.glb.?,
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
        .pin = pin.id,
        .fast_bypass = fast_bypass,
        .orm_bypass = (bypass == .orm_bypass),
    });

    var out_signal = if (bypass == .fast_bypass_inverted) "out.-" else "out";
    try design.addPT("in", out_signal);
    try design.addPT("in2", out_signal);
    try design.addPT("in3", out_signal);
    try design.addPT("in4", out_signal);

    var results = try tc.runToolchain(design);
    try helper.logResults("bypass_{s}_{s}", .{ pin.id, @tagName(bypass) }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev.device));
    try writer.expressionExpanded("output_routing_mode");

    var defaults = std.EnumMap(ORPMode, usize) {};

    var pin_iter = helper.OutputIterator { .pins = dev.all_pins };
    while (pin_iter.next()) |pin| {
        try tc.cleanTempDir();
        helper.resetTemp();

        var jeds = std.EnumMap(ORPMode, JedecData) {};
        for (std.enums.values(ORPMode)) |mode| {
            const results = try runToolchain(ta, tc, dev, pin, mode);
            jeds.put(mode, results.jedec);
        }

        // The fitter also sets the XOR invert fuse when .fast_bypass_inverted is used, even though that
        // doesn't affect the bypass path. So we won't include that one when computing the diff:
        var diff = try JedecData.initDiff(ta, jeds.get(.orm).?, jeds.get(.fast_bypass).?);
        diff.unionDiff(jeds.get(.orm).?, jeds.get(.orm_bypass).?);

        try helper.writePin(writer, pin);

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
            try helper.err("Expected two bypass fuses but found {}!", .{ diff.countSet() }, dev, .{ .pin = pin.id });
        }

        try writer.close();
    }

    for (std.enums.values(ORPMode)) |mode| {
        if (defaults.get(mode)) |def| {
            try helper.writeValue(writer, def, mode);
        }
    }

    try writer.done();

    _ = pa;
}
