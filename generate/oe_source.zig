const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const Device_Info = @import("Device_Info.zig");
const JEDEC_Data = lc4k.JEDEC_Data;
const Fuse = lc4k.Fuse;
const Pin_Info = lc4k.Pin_Info;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const Output_Iterator = helper.Output_Iterator;
const MC_Ref = lc4k.MC_Ref;

pub fn main() void {
    helper.main();
}

fn run_toolchainOnOff(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, pin: Pin_Info, off: bool) !toolchain.Fit_Results {
     var design = Design.init(ta, dev);
    try design.pin_assignment(.{
        .signal = "out",
        .pin = pin.id,
    });
    try design.add_pt("in", "out");

    if (off) {
        try design.add_output("out.OE");
    }

    var results = try tc.run_toolchain(design);
    if (off) {
        try helper.log_results(dev.device, "off_{s}", .{ pin.id }, results);
    } else {
        try helper.log_results(dev.device, "on_{s}", .{ pin.id }, results);
    }
    try results.check_term();
    return results;
}

fn getFirstNonOE(dev: *const Device_Info, exclude_glb: u8) !lc4k.Pin_Info {
    var iter = Output_Iterator {
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

fn getFirstInGLB(dev: *const Device_Info, glb: u8, exclude_mc: u8) !lc4k.Pin_Info {
    var iter = Output_Iterator {
        .pins = dev.all_pins,
        .single_glb = glb,
    };
    while (iter.next()) |pin| {
        if (dev.device == .LC4064ZC_csBGA56) {
            // These pins are connected to macrocells, but lpf4k thinks they're dedicated inputs, and won't allow them to be used as outputs.
            if (std.mem.eql(u8, pin.id, "F8")) continue;
            if (std.mem.eql(u8, pin.id, "E3")) continue;
        }
        if (pin.mc()) |mcref| {
            if (mcref.mc != exclude_mc) {
                return pin;
            }
        }
    }
    return error.NotFound;
}

fn run_toolchainGOE(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, pin: Pin_Info, goe: bool) !toolchain.Fit_Results {
     var design = Design.init(ta, dev);
    try design.pin_assignment(.{
        .signal = "out",
        .pin = pin.id,
    });
    try design.add_pt("in", "out");

    const glb = pin.glb.?;
    const mc = pin.mc().?.mc;

    try design.pin_assignment(.{
        .signal = "oe",
        .pin = (try getFirstNonOE(dev, glb)).id,
    });
    try design.pin_assignment(.{
        .signal = "gout",
        .pin = (try getFirstInGLB(dev, glb, mc)).id,
    });

    try design.add_pt(.{}, "gout");
    try design.add_pt("oe", "gout.OE");

    if (goe) {
        try design.add_pt("oe", "out.OE");
    }

    var results = try tc.run_toolchain(design);
    if (goe) {
        try helper.log_results(dev.device, "goe.glb{}.mc{}", .{ glb, mc }, results);
    } else {
        try helper.log_results(dev.device, "nogoe.glb{}.mc{}", .{ glb, mc }, results);
    }
    try results.check_term();
    return results;
}

fn run_toolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, pin: Pin_Info, mode: lc4k.OutputEnableMode) !toolchain.Fit_Results {
    var design = Design.init(ta, dev);
    try design.pin_assignment(.{
        .signal = "out",
        .pin = pin.id,
    });
    try design.add_pt("in", "out");

    const glb = pin.glb.?;
    const mc = pin.mc().?.mc;

    switch (mode) {
        .input_only => {
            try design.add_output("out.OE");
        },
        .output_only => {
            // don't define an OE signal; this is the default
        },
        .from_orm_active_low, .from_orm_active_high => {
            if (mode == .from_orm_active_low) {
                try design.add_pt(.{ "in0", "in1" }, "out.OE-");
            } else {
                try design.add_pt(.{ "in0", "in1" }, "out.OE");
            }

            var iter = Output_Iterator {
                .pins = dev.all_pins,
                .exclude_glb = glb,
                .exclude_oes = true,
            };
            if (iter.next()) |info| {
                try design.pin_assignment(.{
                    .signal = "goe2",
                    .pin_index = info.pin_index,
                });
            }
            if (iter.next()) |info| {
                try design.pin_assignment(.{
                    .signal = "goe3",
                    .pin_index = info.pin_index,
                });
            }

            iter = Output_Iterator {
                .pins = dev.all_pins,
                .single_glb = glb,
                .exclude_oes = true,
            };
            while (iter.next()) |info| {
                if (info.mc != mc) {
                    const oe_signal = try std.fmt.allocPrint(ta, "dum{}.OE", .{ info.mc });
                    const signal = oe_signal[0..oe_signal.len - 3];
                    try design.pin_assignment(.{
                        .signal = signal,
                        .pin_index = info.pin_index,
                    });
                    try design.add_pt(.{}, signal);
                    if (info.mc < 8) {
                        try design.add_pt("goe2", oe_signal);
                    } else {
                        try design.add_pt("goe3", oe_signal);
                    }
                }
            }
        },
        .goe0 => {
            try design.pin_assignment(.{
                .signal = "goe0",
                .pin_index = dev.getOEPin(0).pin_index,
            });
            try design.add_pt("goe0", "out.OE");
        },
        .goe1 => {
            try design.pin_assignment(.{
                .signal = "goe1",
                .pin_index = dev.getOEPin(1).pin_index,
            });
            try design.add_pt("goe1", "out.OE");
        },
        .goe2 => {
            try design.pin_assignment(.{
                .signal = "goe2",
                .pin_index = try getFirstNonOE(dev, glb),
            });
            try design.add_pt("goe2", "out.OE");
        },
        .goe3 => {
            try design.add_pt("goe3", "out.OE");

            var iter = Output_Iterator {
                .pins = dev.all_pins,
                .exclude_glb = glb,
                .exclude_oes = true,
            };
            if (iter.next()) |info| {
                try design.pin_assignment(.{
                    .signal = "goe2",
                    .pin_index = info.pin_index,
                });
            }
            if (iter.next()) |info| {
                try design.pin_assignment(.{
                    .signal = "goe3",
                    .pin_index = info.pin_index,
                });
            }

            iter = Output_Iterator {
                .pins = dev.all_pins,
                .single_glb = glb,
                .exclude_oes = true,
            };
            while (iter.next()) |info| {
                if (info.mc != mc) {
                    const oe_signal = try std.fmt.allocPrint(ta, "dum{}.OE", .{ info.mc });
                    const signal = oe_signal[0..oe_signal.len - 3];
                    try design.pin_assignment(.{
                        .signal = signal,
                        .pin_index = info.pin_index,
                    });
                    try design.add_pt(.{}, signal);
                    try design.add_pt("goe2", oe_signal);
                }
            }
        },
    }

    var results = try tc.run_toolchain(design);
    try helper.log_results(dev.device, "{s}.glb{}.mc{}", .{ @tagName(mode), glb, mc }, results);
    try results.check_term();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    var maybe_fallback_fuses: ?std.AutoHashMap(MC_Ref, []const helper.Fuse_And_Value) = null;
    if (helper.get_input_file("oe_source.sx")) |_| {
        maybe_fallback_fuses = try helper.parse_fuses_for_output_pins(ta, pa, "oe_source.sx", "output_enable_source", null);
    }

    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("output_enable_source");

    var pin_iter = Output_Iterator { .pins = dev.all_pins };
    while (pin_iter.next()) |pin| {
        if (maybe_fallback_fuses) |fallback_fuses| {
            if (std.mem.eql(u8, pin.id, "F8") or std.mem.eql(u8, pin.id, "E3")) {
                // These pins are connected to macrocells, but lpf4k thinks they're dedicated inputs, and won't allow them to be used as outputs.
                const mcref = MC_Ref.init(pin.glb.?, switch (pin.func) {
                    .io, .io_oe0, .io_oe1 => |mc| mc,
                    else => unreachable,
                });

                if (fallback_fuses.get(mcref)) |fuses| {
                    try helper.write_pin(writer, pin);
                    for (fuses) |fuse_and_value| {
                        try helper.write_fuse_opt_value(writer, fuse_and_value.fuse, fuse_and_value.value);
                    }
                    try writer.close();
                    continue;
                }
            }
        }

        try tc.clean_temp_dir();
        helper.reset_temp();

        // First we just check input-only and output-only configurations.
        // This should discover exactly one of the three OE mux configuration fuses for this pin.
        var diff = try JEDEC_Data.init_diff(ta, 
            (try run_toolchainOnOff(ta, tc, dev, pin, false)).jedec,
            (try run_toolchainOnOff(ta, tc, dev, pin, true)).jedec,
        );

        // Next check GOE2 vs output-only; this should find the other two OE mux fuses.
        diff.union_diff(
            (try run_toolchainGOE(ta, tc, dev, pin, false)).jedec,
            (try run_toolchainGOE(ta, tc, dev, pin, true)).jedec,
        );

        try helper.write_pin(writer, pin);

        var bit_value: usize = 1;
        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            try helper.write_fuse_opt_value(writer, fuse, bit_value);
            bit_value *= 2;
        }

        try writer.close();

        if (diff.count_set() != 3) {
            try helper.err("Expected 3 fuses to define oe_source options but found {}!", .{ diff.count_set() }, dev, .{ .pin = pin.id });
        }
    }

    // For now I'm just assuming the OE mux inputs have the same ordering on all devices/families.
    // It's incredibly difficult to coax the fitter into placing a particular OE line.  It's mostly
    // doable on the 4032, which only has two shared PTOEs, but larger devices have up to 4 per GLB
    try helper.write_value(writer, 0, .goe0);
    try helper.write_value(writer, 1, .goe1);
    try helper.write_value(writer, 2, .goe2);
    try helper.write_value(writer, 3, .goe3);
    try helper.write_value(writer, 4, .from_orm_active_high);
    try helper.write_value(writer, 5, .from_orm_active_low);
    try helper.write_value(writer, 6, .output_only);
    try helper.write_value(writer, 7, .input_only);

    try writer.done();
}
