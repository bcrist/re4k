const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx.zig");
const core = @import("core.zig");
const jedec = @import("jedec.zig");
const devices = @import("devices/devices.zig");
const device_pins = @import("devices/device_pins.zig");
const JedecData = jedec.JedecData;
const DeviceType = devices.DeviceType;
const PinInfo = device_pins.PinInfo;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

pub fn main() void {
    helper.main();
}

fn runToolchainOnOff(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, pin_info: PinInfo, off: bool) !toolchain.FitResults {
     var design = Design.init(ta, dev);
    try design.pinAssignment(.{
        .signal = "out",
        .pin_index = pin_info.input_output.pin_index,
    });
    try design.addPT("in", "out");

    if (off) {
        try design.addOutput("out.OE");
    }

    const glb = pin_info.input_output.glb;
    const mc = pin_info.input_output.mc;

    var results = try tc.runToolchain(design);
    try results.checkTerm();
    if (off) {
        try helper.logReport("off.glb{}.mc{}", .{ glb, mc }, results);
    } else {
        try helper.logReport("on.glb{}.mc{}", .{ glb, mc }, results);
    }
    return results;
}

fn getFirstNonGOE(device: DeviceType, exclude_glb: u8) !u16 {
    var iter = device_pins.OutputIterator {
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
    var iter = device_pins.OutputIterator {
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

fn runToolchainGOE(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, pin_info: PinInfo, goe: bool) !toolchain.FitResults {
     var design = Design.init(ta, dev);
    try design.pinAssignment(.{
        .signal = "out",
        .pin_index = pin_info.input_output.pin_index,
    });
    try design.addPT("in", "out");

    const glb = pin_info.input_output.glb;
    const mc = pin_info.input_output.mc;

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
    try results.checkTerm();
    if (goe) {
        try helper.logReport("goe.glb{}.mc{}", .{ glb, mc }, results);
    } else {
        try helper.logReport("nogoe.glb{}.mc{}", .{ glb, mc }, results);
    }
    return results;
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, pin_info: PinInfo, mode: core.OutputEnableMode) !toolchain.FitResults {
    var design = Design.init(ta, dev);
    try design.pinAssignment(.{
        .signal = "out",
        .pin_index = pin_info.input_output.pin_index,
    });
    try design.addPT("in", "out");

    const glb = pin_info.input_output.glb;
    const mc = pin_info.input_output.mc;

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

            var iter = device_pins.OutputIterator {
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

            iter = device_pins.OutputIterator {
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

            var iter = device_pins.OutputIterator {
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

            iter = device_pins.OutputIterator {
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
    try results.checkTerm();
    try helper.logReport("{s}.glb{}.mc{}", .{ @tagName(mode), glb, mc }, results);
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("oe_mux");

    var detail_pin_index: ?u16 = null;
    var detail_fuses = std.ArrayList(usize).init(pa);

    var pin_index: u16 = 0;
    while (pin_index < dev.getNumPins()) : (pin_index += 1) {
        const pin_info = dev.getPins()[pin_index];
        const io = switch (pin_info) {
            .input_output => |info| info,
            else => continue,
        };

        try tc.cleanTempDir();
        helper.resetTemp();

        // First we just check input-only and output-only configurations.
        // This should discover exactly one of the three OE mux configuration fuses for this pin.
        var diff = try helper.diff(ta, 
            (try runToolchainOnOff(ta, tc, dev, pin_info, false)).jedec,
            (try runToolchainOnOff(ta, tc, dev, pin_info, true)).jedec,
        );

        // Next check GOE2 vs output-only; this should find the other two OE mux fuses.
        diff.raw.setUnion((try helper.diff(ta, 
                (try runToolchainGOE(ta, tc, dev, pin_info, false)).jedec,
                (try runToolchainGOE(ta, tc, dev, pin_info, true)).jedec,
            )).raw);

        try writer.expression("pin");
        try writer.printRaw("{s}", .{ io.pin_number });

        var n_fuses: usize = 0;

        // var values = std.EnumMap(core.OutputEnableMode, usize) {};

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
            try writer.close();

            if (detail_pin_index == null and io.goe_index == null) {
                try detail_fuses.append(fuse);
            }

            n_fuses += 1;
            bit_value *= 2;
        }

        try writer.close();

        if (n_fuses != 3) {
            try std.io.getStdErr().writer().print("Expected 3 fuses to define oe_mux options for device {} pin {s}, but found {}!\n", .{ dev, io.pin_number, n_fuses });
        }

        if (detail_pin_index == null and io.goe_index == null) {
            detail_pin_index = pin_index;
        }
    }

    for ([_]core.OutputEnableMode {
                .input_only, .output_only,
                .from_orp_active_low, .from_orp_active_high,
                .goe0, .goe1, .goe2, .goe3
            }) |mode| {
        const pin_info = dev.getPins()[detail_pin_index orelse unreachable];

        var results = try runToolchain(ta, tc, dev, pin_info, mode);

        var value: usize = 0;
        var bit_value: usize = 1;
        for (detail_fuses.items) |fuse| {
            if (results.jedec.raw.isSet(fuse)) {
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