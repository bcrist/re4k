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

fn run_toolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, pin: lc4k.Pin_Info, inreg: bool) !toolchain.Fit_Results {
    var design = Design.init(ta, dev);

    try design.pin_assignment(.{
        .signal = "x0",
    });
    try design.pin_assignment(.{
        .signal = "x1",
    });
    try design.pin_assignment(.{
        .signal = "x2",
    });
    try design.pin_assignment(.{
        .signal = "x3",
    });
    try design.pin_assignment(.{
        .signal = "x4",
    });

    var mc: u8 = 0;
    while (mc < pin.mc().?.mc) : (mc += 1) {
        const signal_name = try std.fmt.allocPrint(ta, "dum{}", .{ mc });
        try design.node_assignment(.{
            .signal = signal_name,
            .glb = pin.glb.?,
            .mc = mc,
        });
        try design.add_pt("x0", signal_name);
        try design.add_pt("x1", signal_name);
        try design.add_pt("x2", signal_name);
        try design.add_pt("x3", signal_name);
        try design.add_pt("x4", signal_name);
    }

    try design.pin_assignment(.{
        .signal = "in",
        .pin = pin.id,
    });
    try design.node_assignment(.{
        .signal = "out",
        .glb = pin.glb.?,
        .mc = pin.mc().?.mc,
        .input_register = inreg,
    });
    try design.add_pt("in", "out.D");

    var results = try tc.run_toolchain(design);
    try helper.log_results(dev.device, "input_reg_pin_{s}_{}", .{ pin.id, inreg }, results);
    try results.check_term();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    var maybe_fallback_fuses: ?std.AutoHashMap(MC_Ref, []const helper.Fuse_And_Value) = null;
    if (helper.get_input_file("input_bypass.sx")) |_| {
        maybe_fallback_fuses = try helper.parse_fuses_for_output_pins(ta, pa, "input_bypass.sx", "macrocell_data", null);
    }

    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("macrocell_data");

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

        const results_none = try run_toolchain(ta, tc, dev, pin, false);
        const results_inreg = try run_toolchain(ta, tc, dev, pin, true);

        var diff = try JEDEC_Data.init_diff(ta, results_none.jedec, results_inreg.jedec);

        diff.put_range(dev.get_routing_range(), 0);

        try helper.write_pin(writer, pin);

        var n_fuses: usize = 0;

        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            if (results_none.jedec.is_set(fuse)) {
                try helper.write_fuse(writer, fuse);
                n_fuses += 1;
            }
        }

        if (n_fuses != 1) {
            try helper.err("Expected one input register fuse but found {}!", .{ n_fuses }, dev, .{ .pin = pin.id });
        }

        try writer.close();
    }

    try helper.write_value(writer, 1, "normal");
    try helper.write_value(writer, 0, "input_bypass");

    try writer.done();
}
