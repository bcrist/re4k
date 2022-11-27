const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const common = @import("common");
const jedec = @import("jedec");
const device_info = @import("device_info.zig");
const JedecData = jedec.JedecData;
const Fuse = jedec.Fuse;
const DeviceInfo = device_info.DeviceInfo;
const PinInfo = common.PinInfo;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const OutputIterator = helper.OutputIterator;

pub fn main() void {
    helper.main(0);
}

fn runToolchainOnOff(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, pin: PinInfo, off: bool) !toolchain.FitResults {
     var design = Design.init(ta, dev);
    try design.pinAssignment(.{
        .signal = "out",
        .pin = pin.id,
    });
    try design.addPT("in", "out");

    if (off) {
        try design.addOutput("out.OE");
    }

    var results = try tc.runToolchain(design);
    if (off) {
        try helper.logResults("off_{s}", .{ pin.id }, results);
    } else {
        try helper.logResults("on_{s}", .{ pin.id }, results);
    }
    try results.checkTerm();
    return results;
}

fn getFirstNonOE(dev: *const DeviceInfo, exclude_glb: u8) !common.PinInfo {
    var iter = OutputIterator {
        .pins = dev.all_pins,
        .exclude_oes = true,
        .exclude_glb = exclude_glb,
    };

    if (iter.next()) |info| {
        return info;
    } else {
        return error.NotFound;
    }
}

fn getFirstInGLB(dev: *const DeviceInfo, glb: u8, exclude_mc: u8) !common.PinInfo {
    var iter = OutputIterator {
        .pins = dev.all_pins,
        .single_glb = glb,
    };
    while (iter.next()) |pin| {
        if (pin.mcRef()) |mcref| {
            if (mcref.mc != exclude_mc) {
                return pin;
            }
        }
    }
    return error.NotFound;
}

fn runToolchainGOE(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, pin: PinInfo, goe: bool) !toolchain.FitResults {
     var design = Design.init(ta, dev);
    try design.pinAssignment(.{
        .signal = "out",
        .pin = pin.id,
    });
    try design.addPT("in", "out");

    const glb = pin.glb.?;
    const mc = pin.mcRef().?.mc;

    try design.pinAssignment(.{
        .signal = "oe",
        .pin = (try getFirstNonOE(dev, glb)).id,
    });
    try design.pinAssignment(.{
        .signal = "gout",
        .pin = (try getFirstInGLB(dev, glb, mc)).id,
    });

    try design.addPT(.{}, "gout");
    try design.addPT("oe", "gout.OE");

    if (goe) {
        try design.addPT("oe", "out.OE");
    }

    var results = try tc.runToolchain(design);
    if (goe) {
        try helper.logResults("goe.glb{}.mc{}", .{ glb, mc }, results);
    } else {
        try helper.logResults("nogoe.glb{}.mc{}", .{ glb, mc }, results);
    }
    try results.checkTerm();
    return results;
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, pin: PinInfo, mode: common.OutputEnableMode) !toolchain.FitResults {
    var design = Design.init(ta, dev);
    try design.pinAssignment(.{
        .signal = "out",
        .pin = pin.id,
    });
    try design.addPT("in", "out");

    const glb = pin.glb.?;
    const mc = pin.mcRef().?.mc;

    switch (mode) {
        .input_only => {
            try design.addOutput("out.OE");
        },
        .output_only => {
            // don't define an OE signal; this is the default
        },
        .from_orm_active_low, .from_orm_active_high => {
            if (mode == .from_orm_active_low) {
                try design.addPT(.{ "in0", "in1" }, "out.OE-");
            } else {
                try design.addPT(.{ "in0", "in1" }, "out.OE");
            }

            var iter = OutputIterator {
                .pins = dev.all_pins,
                .exclude_glb = glb,
                .exclude_oes = true,
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

            iter = OutputIterator {
                .pins = dev.all_pins,
                .single_glb = glb,
                .exclude_oes = true,
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
                .pin_index = dev.getOEPin(0).pin_index,
            });
            try design.addPT("goe0", "out.OE");
        },
        .goe1 => {
            try design.pinAssignment(.{
                .signal = "goe1",
                .pin_index = dev.getOEPin(1).pin_index,
            });
            try design.addPT("goe1", "out.OE");
        },
        .goe2 => {
            try design.pinAssignment(.{
                .signal = "goe2",
                .pin_index = try getFirstNonOE(dev, glb),
            });
            try design.addPT("goe2", "out.OE");
        },
        .goe3 => {
            try design.addPT("goe3", "out.OE");

            var iter = OutputIterator {
                .pins = dev.all_pins,
                .exclude_glb = glb,
                .exclude_oes = true,
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

            iter = OutputIterator {
                .pins = dev.all_pins,
                .single_glb = glb,
                .exclude_oes = true,
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
    try helper.logResults("{s}.glb{}.mc{}", .{ @tagName(mode), glb, mc }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev.device));
    try writer.expressionExpanded("output_enable_source");

    var pin_iter = OutputIterator { .pins = dev.all_pins };
    while (pin_iter.next()) |pin| {
        try tc.cleanTempDir();
        helper.resetTemp();

        // First we just check input-only and output-only configurations.
        // This should discover exactly one of the three OE mux configuration fuses for this pin.
        var diff = try JedecData.initDiff(ta, 
            (try runToolchainOnOff(ta, tc, dev, pin, false)).jedec,
            (try runToolchainOnOff(ta, tc, dev, pin, true)).jedec,
        );

        // Next check GOE2 vs output-only; this should find the other two OE mux fuses.
        diff.unionDiff(
            (try runToolchainGOE(ta, tc, dev, pin, false)).jedec,
            (try runToolchainGOE(ta, tc, dev, pin, true)).jedec,
        );

        try helper.writePin(writer, pin);

        var bit_value: usize = 1;
        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            try helper.writeFuseOptValue(writer, fuse, bit_value);
            bit_value *= 2;
        }

        try writer.close();

        if (diff.countSet() != 3) {
            try helper.err("Expected 3 fuses to define oe_source options but found {}!", .{ diff.countSet() }, dev, .{ .pin = pin.id });
        }
    }

    // For now I'm just assuming the OE mux inputs have the same ordering on all devices/families.
    // It's incredibly difficult to coax the fitter into placing a particular OE line.  It's mostly
    // doable on the 4032, which only has two shared PTOEs, but larger devices have up to 4 per GLB
    // TODO figure out a way to reliably test permutations of OE mux for all devices
    try helper.writeValue(writer, 0, .goe0);
    try helper.writeValue(writer, 1, .goe1);
    try helper.writeValue(writer, 2, .goe2);
    try helper.writeValue(writer, 3, .goe3);
    try helper.writeValue(writer, 4, .from_orm_active_high);
    try helper.writeValue(writer, 5, .from_orm_active_low);
    try helper.writeValue(writer, 6, .output_only);
    try helper.writeValue(writer, 7, .input_only);

    try writer.done();

    _ = pa;
}
