const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const core = @import("core.zig");
const jedec = @import("jedec.zig");
const devices = @import("devices.zig");
const JedecData = jedec.JedecData;
const Fuse = jedec.Fuse;
const DeviceType = devices.DeviceType;
const PinInfo = devices.pins.PinInfo;
const InputOutputPinInfo = devices.pins.InputOutputPinInfo;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

pub fn main() void {
    helper.main(0);
}

fn runToolchainOnOff(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, io: InputOutputPinInfo, off: bool) !toolchain.FitResults {
     var design = Design.init(ta, dev);
    try design.pinAssignment(.{
        .signal = "out",
        .pin_index = io.pin_index,
    });
    try design.addPT("in", "out");

    if (off) {
        try design.addOutput("out.OE");
    }

    const glb = io.glb;
    const mc = io.mc;

    var results = try tc.runToolchain(design);
    if (off) {
        try helper.logReport("off.glb{}.mc{}", .{ glb, mc }, results);
    } else {
        try helper.logReport("on.glb{}.mc{}", .{ glb, mc }, results);
    }
    try results.checkTerm();
    return results;
}

fn getFirstNonGOE(device: DeviceType, exclude_glb: u8) !u16 {
    var iter = devices.pins.OutputIterator {
        .pins = device.getPins(),
        .exclude_goes = true,
        .exclude_glb = exclude_glb,
    };

    if (iter.next()) |info| {
        return info.pin_index;
    } else {
        return error.NotFound;
    }
}

fn getFirstInGLB(device: DeviceType, glb: u8, exclude_mc: u8) !u16 {
    var iter = devices.pins.OutputIterator {
        .pins = device.getPins(),
        .single_glb = glb,
    };
    while (iter.next()) |info| {
        if (info.mc != exclude_mc) {
            return info.pin_index;
        }
    }
    return error.NotFound;
}

fn runToolchainGOE(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, io: InputOutputPinInfo, goe: bool) !toolchain.FitResults {
     var design = Design.init(ta, dev);
    try design.pinAssignment(.{
        .signal = "out",
        .pin_index = io.pin_index,
    });
    try design.addPT("in", "out");

    const glb = io.glb;
    const mc = io.mc;

    try design.pinAssignment(.{
        .signal = "goe2",
        .pin_index = try getFirstNonGOE(dev, glb),
    });
    try design.pinAssignment(.{
        .signal = "gout",
        .pin_index = try getFirstInGLB(dev, glb, mc),
    });

    try design.addPT(.{}, "gout");
    try design.addPT("goe2", "gout.OE");

    if (goe) {
        try design.addPT("goe2", "out.OE");
    }

    var results = try tc.runToolchain(design);
    if (goe) {
        try helper.logReport("goe.glb{}.mc{}", .{ glb, mc }, results);
    } else {
        try helper.logReport("nogoe.glb{}.mc{}", .{ glb, mc }, results);
    }
    try results.checkTerm();
    return results;
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, io: InputOutputPinInfo, mode: core.OutputEnableMode) !toolchain.FitResults {
    var design = Design.init(ta, dev);
    try design.pinAssignment(.{
        .signal = "out",
        .pin_index = io.pin_index,
    });
    try design.addPT("in", "out");

    const glb = io.glb;
    const mc = io.mc;

    switch (mode) {
        .input_only => {
            try design.addOutput("out.OE");
        },
        .output_only => {
            // don't define an OE signal; this is the default
        },
        .from_orp_active_low, .from_orp_active_high => {
            if (mode == .from_orp_active_low) {
                try design.addPT(.{ "in0", "in1" }, "out.OE-");
            } else {
                try design.addPT(.{ "in0", "in1" }, "out.OE");
            }

            var iter = devices.pins.OutputIterator {
                .pins = dev.getPins(),
                .exclude_glb = glb,
                .exclude_goes = true,
            };
            if (iter.next()) |info| {
                try design.pinAssignment(.{
                    .signal = "goe2",
                    .pin_index = info.pin_index,
                });
            }
            if (iter.next()) |info| {
                try design.pinAssignment(.{
                    .signal = "goe3",
                    .pin_index = info.pin_index,
                });
            }

            iter = devices.pins.OutputIterator {
                .pins = dev.getPins(),
                .single_glb = glb,
                .exclude_goes = true,
            };
            while (iter.next()) |info| {
                if (info.mc != mc) {
                    const oe_signal = try std.fmt.allocPrint(ta, "dum{}.OE", .{ info.mc });
                    const signal = oe_signal[0..oe_signal.len - 3];
                    try design.pinAssignment(.{
                        .signal = signal,
                        .pin_index = info.pin_index,
                    });
                    try design.addPT(.{}, signal);
                    if (info.mc < 8) {
                        try design.addPT("goe2", oe_signal);
                    } else {
                        try design.addPT("goe3", oe_signal);
                    }
                }
            }
        },
        .goe0 => {
            try design.pinAssignment(.{
                .signal = "goe0",
                .pin_index = dev.getGOEPin(0).pin_index,
            });
            try design.addPT("goe0", "out.OE");
        },
        .goe1 => {
            try design.pinAssignment(.{
                .signal = "goe1",
                .pin_index = dev.getGOEPin(1).pin_index,
            });
            try design.addPT("goe1", "out.OE");
        },
        .goe2 => {
            try design.pinAssignment(.{
                .signal = "goe2",
                .pin_index = try getFirstNonGOE(dev, glb),
            });
            try design.addPT("goe2", "out.OE");
        },
        .goe3 => {
            try design.addPT("goe3", "out.OE");

            var iter = devices.pins.OutputIterator {
                .pins = dev.getPins(),
                .exclude_glb = glb,
                .exclude_goes = true,
            };
            if (iter.next()) |info| {
                try design.pinAssignment(.{
                    .signal = "goe2",
                    .pin_index = info.pin_index,
                });
            }
            if (iter.next()) |info| {
                try design.pinAssignment(.{
                    .signal = "goe3",
                    .pin_index = info.pin_index,
                });
            }

            iter = devices.pins.OutputIterator {
                .pins = dev.getPins(),
                .single_glb = glb,
                .exclude_goes = true,
            };
            while (iter.next()) |info| {
                if (info.mc != mc) {
                    const oe_signal = try std.fmt.allocPrint(ta, "dum{}.OE", .{ info.mc });
                    const signal = oe_signal[0..oe_signal.len - 3];
                    try design.pinAssignment(.{
                        .signal = signal,
                        .pin_index = info.pin_index,
                    });
                    try design.addPT(.{}, signal);
                    try design.addPT("goe2", oe_signal);
                }
            }
        },
    }

    var results = try tc.runToolchain(design);
    try helper.logReport("{s}.glb{}.mc{}", .{ @tagName(mode), glb, mc }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("oe_mux");

    var detail_pin_index: ?u16 = null;
    var detail_fuses = std.ArrayList(Fuse).init(pa);

    var pin_iter = devices.pins.OutputIterator { .pins = dev.getPins() };
    while (pin_iter.next()) |io| {
        try tc.cleanTempDir();
        helper.resetTemp();

        // First we just check input-only and output-only configurations.
        // This should discover exactly one of the three OE mux configuration fuses for this pin.
        var diff = try JedecData.initDiff(ta, 
            (try runToolchainOnOff(ta, tc, dev, io, false)).jedec,
            (try runToolchainOnOff(ta, tc, dev, io, true)).jedec,
        );

        // Next check GOE2 vs output-only; this should find the other two OE mux fuses.
        diff.unionDiff(
            (try runToolchainGOE(ta, tc, dev, io, false)).jedec,
            (try runToolchainGOE(ta, tc, dev, io, true)).jedec,
        );

        try writer.expression("pin");
        try writer.printRaw("{s}", .{ io.pin_number });

        var bit_value: usize = 1;
        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            try helper.writeFuseOptValue(writer, fuse, bit_value);

            if (detail_pin_index == null and io.goe_index == null) {
                try detail_fuses.append(fuse);
            }

            bit_value *= 2;
        }

        try writer.close();

        if (diff.countSet() != 3) {
            try helper.err("Expected 3 fuses to define oe_mux options but found {}!", .{ diff.countSet() }, dev, .{ .pin_index = io.pin_index });
        }

        if (detail_pin_index == null and io.goe_index == null) {
            detail_pin_index = io.pin_index;
        }
    }

    for ([_]core.OutputEnableMode {
                .input_only, .output_only,
                .from_orp_active_low, .from_orp_active_high,
                .goe0, .goe1, .goe2, .goe3
            }) |mode| {
        const pin_info = dev.getPins()[detail_pin_index orelse unreachable];

        var results = try runToolchain(ta, tc, dev, pin_info.input_output, mode);

        var value: usize = 0;
        var bit_value: usize = 1;
        for (detail_fuses.items) |fuse| {
            if (results.jedec.isSet(fuse)) {
                value += bit_value;
            }
            bit_value *= 2;
        }

        try writer.expression("value");
        try writer.printRaw("{} {s}", .{ value, @tagName(mode) });
        try writer.close();
    }

    // For now I'm just assuming the OE mux inputs have the same ordering on all devices/families.
    // It's incredibly difficult to coax the fitter into placing a particular OE line.  It's mostly
    // doable on the 4032, which only has two shared PTOEs, but larger devices have up to 4 per GLB
    // TODO figure out a way to reliably test permutations of OE mux for all devices
    try writer.expression("value");
    try writer.printRaw("0 goe0", .{});
    try writer.close();
    try writer.expression("value");
    try writer.printRaw("1 goe1", .{});
    try writer.close();
    try writer.expression("value");
    try writer.printRaw("2 goe2", .{});
    try writer.close();
    try writer.expression("value");
    try writer.printRaw("3 goe3", .{});
    try writer.close();
    try writer.expression("value");
    try writer.printRaw("4 from_orp_active_high", .{});
    try writer.close();
    try writer.expression("value");
    try writer.printRaw("5 from_orp_active_low", .{});
    try writer.close();
    try writer.expression("value");
    try writer.printRaw("6 output_only", .{});
    try writer.close();
    try writer.expression("value");
    try writer.printRaw("7 input_only", .{});
    try writer.close();

    try writer.done();
}
