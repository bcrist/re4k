const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const Device_Info = @import("Device_Info.zig");
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JEDEC_Data = lc4k.JEDEC_Data;
const MC_Ref = lc4k.MC_Ref;

pub const main = helper.main;

fn run_toolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, pin: lc4k.Pin_Info, slew: lc4k.Slew_Rate) !toolchain.Fit_Results {
    var design = Design.init(ta, dev);
    try design.pin_assignment(.{
        .signal = "out",
        .pin = pin.id,
        .slew_rate = slew,
    });
    try design.add_pt("in", "out");

    var results = try tc.run_toolchain(design);
    try helper.log_results(dev.device, "slew_pin_{s}", .{ pin.id }, results);
    try results.check_term();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    var maybe_fallback_fuses: ?std.AutoHashMap(MC_Ref, []const helper.Fuse_And_Value) = null;
    if (helper.get_input_file("slew.sx")) |_| {
        maybe_fallback_fuses = try helper.parse_fuses_for_output_pins(ta, pa, "slew.sx", "slew_rate", null);
    }

    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("slew_rate");

    var default_slow: ?u1 = null;
    var default_fast: ?u1 = null;

    var pin_iter = helper.Output_Iterator { .pins = dev.all_pins };
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

        const results_slow = try run_toolchain(ta, tc, dev, pin, .slow);
        const results_fast = try run_toolchain(ta, tc, dev, pin, .fast);

        const diff = try JEDEC_Data.init_diff(ta, results_slow.jedec, results_fast.jedec);

        try helper.write_pin(writer, pin);

        var diff_iter = diff.iterator(.{});
        if (diff_iter.next()) |fuse| {
            try helper.write_fuse(writer, fuse);

            const slow_value = results_slow.jedec.get(fuse);
            if (default_slow) |def| {
                if (slow_value != def) {
                    try helper.write_value(writer, slow_value, "slow");
                }
            } else {
                default_slow = slow_value;
            }

            const fast_value = results_fast.jedec.get(fuse);
            if (default_fast) |def| {
                if (fast_value != def) {
                    try helper.write_value(writer, fast_value, "fast");
                }
            } else {
                default_fast = fast_value;
            }

        } else {
            try helper.err("Expected one slew fuse but found none!", .{}, dev, .{ .pin = pin.id });
            return error.Think;
        }

        if (diff_iter.next()) |_| {
            try helper.err("Expected one slew fuse but found multiple!", .{}, dev, .{ .pin = pin.id });
            return error.Think;
        }

        try writer.close();
    }

    if (default_slow) |def| {
        try helper.write_value(writer, def, "slow");
    }

    if (default_fast) |def| {
        try helper.write_value(writer, def, "fast");
    }

    try writer.done();
}
