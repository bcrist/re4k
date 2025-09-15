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

const ORPMode = enum {
    fast_bypass,
    fast_bypass_inverted,
    orm,
    orm_bypass,
};

fn run_toolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, pin: lc4k.Pin_Info, bypass: ORPMode) !toolchain.Fit_Results {
    var design = Design.init(ta, dev);

    try design.pin_assignment(.{
        .signal = "in",
    });
    try design.pin_assignment(.{
        .signal = "in2",
    });
    try design.pin_assignment(.{
        .signal = "in3",
    });
    try design.pin_assignment(.{
        .signal = "in4",
    });

    const pin_mc = pin.mc().?.mc;

    var mc: u8 = 0;
    while (mc < pin_mc) : (mc += 1) {
        const signal_name = try std.fmt.allocPrint(ta, "dum{}", .{ mc });
        try design.node_assignment(.{
            .signal = signal_name,
            .glb = pin.glb.?,
            .mc = mc,
        });
        try design.add_pt(.{ "in", "in2" }, signal_name);
        try design.add_pt(.{ "in", "in3" }, signal_name);
        try design.add_pt(.{ "in", "in4" }, signal_name);
        try design.add_pt(.{ "in2", "in3" }, signal_name);
        try design.add_pt(.{ "in2", "in4" }, signal_name);
    }

    const fast_bypass = switch (bypass) {
        .fast_bypass, .fast_bypass_inverted => true,
        else => false,
    };
    try design.pin_assignment(.{
        .signal = "out",
        .pin = pin.id,
        .fast_bypass = fast_bypass,
        .orm_bypass = (bypass == .orm_bypass),
    });

    const out_signal = if (bypass == .fast_bypass_inverted) "out.-" else "out";
    try design.add_pt("in", out_signal);
    try design.add_pt("in2", out_signal);
    try design.add_pt("in3", out_signal);
    try design.add_pt("in4", out_signal);

    var results = try tc.run_toolchain(design);
    try helper.log_results(dev.device, "bypass_{s}_{s}", .{ pin.id, @tagName(bypass) }, results);
    try results.check_term();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    var maybe_fallback_fuses: ?std.AutoHashMap(MC_Ref, []const helper.Fuse_And_Value) = null;
    if (helper.get_input_file("output_routing_mode.sx")) |_| {
        maybe_fallback_fuses = try helper.parse_fuses_for_output_pins(ta, pa, "output_routing_mode.sx", "output_routing_mode", null);
    }

    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("output_routing_mode");

    var defaults = std.EnumMap(ORPMode, usize) {};

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

        var jeds = std.EnumMap(ORPMode, JEDEC_Data) {};
        for (std.enums.values(ORPMode)) |mode| {
            const results = try run_toolchain(ta, tc, dev, pin, mode);
            jeds.put(mode, results.jedec);
        }

        // The fitter also sets the XOR invert fuse when .fast_bypass_inverted is used, even though that
        // doesn't affect the bypass path. So we won't include that one when computing the diff:
        var diff = try JEDEC_Data.init_diff(ta, jeds.get(.orm).?, jeds.get(.fast_bypass).?);
        diff.union_diff(jeds.get(.orm).?, jeds.get(.orm_bypass).?);

        try helper.write_pin(writer, pin);

        var values = std.EnumMap(ORPMode, usize) {};

        var bit_value: usize = 1;
        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            try helper.write_fuse_opt_value(writer, fuse, bit_value);

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
            const val = values.get(mode) orelse 0;
            if (defaults.get(mode)) |def| {
                if (def != val) {

                }
            } else {
                defaults.put(mode, val);
            }
        }

        if (diff.count_set() != 2) {
            try helper.err("Expected two bypass fuses but found {}!", .{ diff.count_set() }, dev, .{ .pin = pin.id });
        }

        try writer.close();
    }

    for (std.enums.values(ORPMode)) |mode| {
        if (defaults.get(mode)) |def| {
            try helper.write_value(writer, def, mode);
        }
    }

    try writer.done();
}
