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

pub fn main() void {
    helper.main();
}

fn run_toolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, pin: lc4k.Pin_Info, offset: u3) !toolchain.Fit_Results {
    var design = Design.init(ta, dev);

    try design.pin_assignment(.{
        .signal = "in",
        .pin = dev.get_clock_pin(0).?.id,
    });
    try design.pin_assignment(.{
        .signal = "out",
        .pin = pin.id,
    });
    // making the main output registered should prevent the use of the ORM bypass,
    // except in the case where offset == 0.
    // We'll test the ORM bypass mux separately, for families that have it.
    // (see output_routing_mode.zig)
    try design.add_pt("in", "out.D");

    const out_mc = (pin.mc().?.mc + offset) & 0xF;

    var mc: u8 = 0;
    while (mc < 16) : (mc += 1) {
        if (mc != out_mc) {
            const signal_d = try std.fmt.allocPrint(ta, "node{}.D", .{ mc });
            const signal = signal_d[0..signal_d.len-2];
            try design.node_assignment(.{
                .signal = signal,
                .glb = pin.glb.?,
                .mc = mc,
            });
            try design.add_pt("in", signal_d);
        }
    }

    var results = try tc.run_toolchain(design);
    try helper.log_results(dev.device, "orm_{s}_plus{}", .{ pin.id, offset }, results);
    try results.check_term();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    var maybe_fallback_fuses: ?std.AutoHashMap(MC_Ref, []const helper.Fuse_And_Value) = null;
    if (helper.get_input_file("output_routing.sx")) |_| {
        maybe_fallback_fuses = try helper.parse_fuses_for_output_pins(ta, pa, "output_routing.sx", "output_routing", null);
    }

    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("output_routing");

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

        const results_1 = try run_toolchain(ta, tc, dev, pin, 1);
        const results_2 = try run_toolchain(ta, tc, dev, pin, 2);
        const results_4 = try run_toolchain(ta, tc, dev, pin, 4);

        var diff = try JEDEC_Data.init_diff(ta, results_1.jedec, results_2.jedec);
        diff.union_diff(results_1.jedec, results_4.jedec);

        try helper.write_pin(writer, pin);

        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            var value: u32 = 0;
            if (results_1.jedec.is_set(fuse)) {
                value += 1;
            }
            if (results_2.jedec.is_set(fuse)) {
                value += 2;
            }
            if (results_4.jedec.is_set(fuse)) {
                value += 4;
            }

            switch (value) {
                1, 2, 4 => {},
                else => {
                    try helper.err("Expected ORM fuse {}:{} to have a value of 1, 2, or 4, but found {}",
                        .{ fuse.row, fuse.col, value }, dev, .{ .pin = pin.id });
                },
            }

            try helper.write_fuse_opt_value(writer, fuse, value);
        }

        if (diff.count_set() != 3) {
            try helper.err("Expected exactly 3 ORM fuses but found {}!", .{ diff.count_set() }, dev, .{ .pin = pin.id });
        }

        try writer.close();
    }

    try helper.write_value(writer, 0, "from_mc");
    try helper.write_value(writer, 1, "from_mc_plus_1");
    try helper.write_value(writer, 2, "from_mc_plus_2");
    try helper.write_value(writer, 3, "from_mc_plus_3");
    try helper.write_value(writer, 4, "from_mc_plus_4");
    try helper.write_value(writer, 5, "from_mc_plus_5");
    try helper.write_value(writer, 6, "from_mc_plus_6");
    try helper.write_value(writer, 7, "from_mc_plus_7");

    try writer.done();
}
