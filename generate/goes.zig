const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const Device_Info = @import("Device_Info.zig");
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JEDEC_Data = lc4k.JEDEC_Data;
const Fuse = lc4k.Fuse;
const Input_Iterator = helper.Input_Iterator;
const Output_Iterator = helper.Output_Iterator;

pub fn main() void {
    helper.main();
}

const Polarity = enum {
    positive,
    negative,
};

fn run_toolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, oe0: Polarity, oe1: Polarity, use_goe_pins: bool) !toolchain.Fit_Results {
    var design = Design.init(ta, dev);

    if (use_goe_pins) {
        try design.pin_assignment(.{
            .signal = "oe0",
            .pin = dev.oe_pins[0].id,
        });
        try design.pin_assignment(.{
            .signal = "oe1",
            .pin = dev.oe_pins[1].id,
        });
    } else {
        var pin_iter = Input_Iterator {
            .pins = dev.all_pins,
            .exclude_glb = 0,
            .exclude_oes = true,
        };
        try design.pin_assignment(.{
            .signal = "oe0",
            .pin = pin_iter.next().?.id,
        });
        try design.pin_assignment(.{
            .signal = "oe1",
            .pin = pin_iter.next().?.id,
        });
    }

    var pin_iter = Output_Iterator {
        .pins = dev.all_pins,
        .single_glb = 0,
        .exclude_oes = true,
    };
    var n: u1 = 0;
    while (pin_iter.next()) |pin| {
        if (dev.device == .LC4064ZC_csBGA56) {
            // These pins are connected to macrocells, but lpf4k thinks they're dedicated inputs, and won't allow them to be used as outputs.
            if (std.mem.eql(u8, pin.id, "F8")) continue;
            if (std.mem.eql(u8, pin.id, "E3")) continue;
        }

        var oe_signal_name = try std.fmt.allocPrint(ta, "out{s}.OE", .{ pin.id });
        const signal_name = oe_signal_name[0..oe_signal_name.len-3];

        try design.pin_assignment(.{
            .signal = signal_name,
            .pin = pin.id,
        });

        try design.add_pt(.{ "x1", "x2" }, signal_name);
        try design.add_pt(.{ "x1", "x3" }, signal_name);
        try design.add_pt(.{ "x1", "x4" }, signal_name);
        try design.add_pt(.{ "x2", "x3" }, signal_name);
        try design.add_pt(.{ "x2", "x4" }, signal_name);

        // Note: using `.OE-` instead of inverting the inputs seems like it should work just as well,
        // and the fitter accepts that and shows it the same way in the post-fit equations, but
        // it doesn't actually invert the GOE signal.  Definitely a fitter bug.
        try design.add_pt(switch (n) {
            0 => switch (oe0) {
                .positive => "oe0",
                .negative => "~oe0",
            },
            1 => switch (oe1) {
                .positive => "oe1",
                .negative => "~oe1",
            },
        }, oe_signal_name);

        n = switch (n) {
            0 => 1,
            1 => 0,
        };
    }

    var results = try tc.run_toolchain(design);
    try helper.log_results(dev.device, "goe_polarity_eoe0_{s}_eoe1_{s}", .{ @tagName(oe0), @tagName(oe1) }, results);
    try results.check_term();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    const sptclk_polarity_fuses = try helper.parse_shared_pt_clock_polarity_fuses(ta, pa, dev);

    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("goe_polarity");

    // Getting the fitter to output specific GOE configurations has proven extremely difficult.  In particular, it seems incapable of
    // routing more than 2 GOEs simultaneously for some reason, even though it should be easily possible to do 4.  So most of what we're
    // going to do here is just spit out the fuses that we expect, based on manually reverse engineering with LC4032ZE and LC4064ZC devices.
    // We're going to assume that other devices use the same layout.  In particular, the assumptions we're making are:
    //
    //    * GOE polarity fuses are always in a vertical block of 4 fuses, with GOE0 polarity at the top and GOE3 polarity at the bottom
    //    * For LC4032 devices, the first pin GOE (i.e. not from the shared OE bus) corresponds to GOE2, and the second corresponds to GOE3
    //    * For non-LC4032 devices, the first pin GOE corresponds to GOE0 and the second to GOE1
    //    * For non-LC4032 devices, the GOE0/1 source fuses are always directly above the GOE polarity fuses, and 0 means "use external pin as GOE"
    //    * Shared PT OE routing fuses are in a single block, between the shared PT clock polarity and shared PT init polarity fuses (2 for LC4032, 4 for others)

    const results_pos_pos = try run_toolchain(ta, tc, dev, .positive, .positive, true);
    const results_pos_neg = try run_toolchain(ta, tc, dev, .positive, .negative, true);
    const results_neg_pos = try run_toolchain(ta, tc, dev, .negative, .positive, true);
    const results_neg_neg = try run_toolchain(ta, tc, dev, .negative, .negative, true);

    var combined_diff = try JEDEC_Data.init_diff(ta,
        results_pos_pos.jedec,
        results_neg_neg.jedec,
    );

    combined_diff.union_diff(results_pos_pos.jedec, results_pos_neg.jedec);
    combined_diff.union_diff(results_pos_pos.jedec, results_neg_pos.jedec);

    if (combined_diff.count_set() != 2) {
        try helper.err("Expected two fuses for GOE2/3 polarity shared PT clock polarity fuses, but found {}!", .{ combined_diff.count_set() }, dev, .{});
        return error.Unexpected;
    }
    var oe0_diff = try JEDEC_Data.init_diff(ta, results_pos_pos.jedec, results_neg_pos.jedec);
    if (oe0_diff.count_set() != 1) {
        try helper.err("Expected one fuse for GOE2 polarity shared PT clock polarity fuses, but found {}!", .{ oe0_diff.count_set() }, dev, .{});
        return error.Unexpected;
    }
    var oe1_diff = try JEDEC_Data.init_diff(ta, results_pos_pos.jedec, results_pos_neg.jedec);
    if (oe1_diff.count_set() != 1) {
        try helper.err("Expected one fuse for GOE3 polarity shared PT clock polarity fuses, but found {}!", .{ oe1_diff.count_set() }, dev, .{});
        return error.Unexpected;
    }

    try writer.expression("goe0");
    var iter = oe0_diff.iterator(.{});
    var fuse = iter.next().?;
    if (results_pos_pos.jedec.get(fuse) != 1) try helper.err("Expected OE0 fuse to be 1 for positive", .{}, dev, .{});
    if (results_pos_neg.jedec.get(fuse) != 1) try helper.err("Expected OE0 fuse to be 1 for positive", .{}, dev, .{});
    if (results_neg_pos.jedec.get(fuse) != 0) try helper.err("Expected OE0 fuse to be 0 for negative", .{}, dev, .{});
    if (results_neg_neg.jedec.get(fuse) != 0) try helper.err("Expected OE0 fuse to be 0 for negative", .{}, dev, .{});
    if (dev.num_glbs < 4) {
        fuse = Fuse.init(fuse.row - 2, fuse.col);
    }
    try helper.write_fuse(writer, fuse);
    try writer.close();

    try writer.expression("goe1");
    iter = oe1_diff.iterator(.{});
    fuse = iter.next().?;
    if (results_pos_pos.jedec.get(fuse) != 1) try helper.err("Expected OE1 fuse to be 1 for positive", .{}, dev, .{});
    if (results_pos_neg.jedec.get(fuse) != 0) try helper.err("Expected OE1 fuse to be 0 for negative", .{}, dev, .{});
    if (results_neg_pos.jedec.get(fuse) != 1) try helper.err("Expected OE1 fuse to be 1 for positive", .{}, dev, .{});
    if (results_neg_neg.jedec.get(fuse) != 0) try helper.err("Expected OE1 fuse to be 0 for negative", .{}, dev, .{});
    if (dev.num_glbs < 4) {
        fuse = Fuse.init(fuse.row - 2, fuse.col);
    }
    try helper.write_fuse(writer, fuse);
    try writer.close();

    try writer.expression("goe2");
    iter = oe0_diff.iterator(.{});
    fuse = iter.next().?;
    if (dev.num_glbs >= 4) {
        fuse = Fuse.init(fuse.row + 2, fuse.col);
    }
    try helper.write_fuse(writer, fuse);
    try writer.close();

    try writer.expression("goe3");
    iter = oe1_diff.iterator(.{});
    fuse = iter.next().?;
    if (dev.num_glbs >= 4) {
        fuse = Fuse.init(fuse.row + 2, fuse.col);
    }
    try helper.write_fuse(writer, fuse);
    try writer.close();

    try helper.write_value(writer, 0, "active_low");
    try helper.write_value(writer, 1, "active_high");

    try writer.close(); // goe_polarity


    if (dev.num_glbs >= 4) {
        try writer.expression_expanded("goe_source");

        try writer.expression("goe0");
        iter = oe0_diff.iterator(.{});
        fuse = iter.next().?;
        try helper.write_fuse(writer, Fuse.init(fuse.row - 2, fuse.col));
        try writer.close();

        try writer.expression("goe1");
        iter = oe1_diff.iterator(.{});
        fuse = iter.next().?;
        try helper.write_fuse(writer, Fuse.init(fuse.row - 2, fuse.col));
        try writer.close();

        try helper.write_value(writer, 0, "pin");
        try helper.write_value(writer, 1, "shared_pt_oe_bus");

        try writer.close(); // goe_source
    }

    try writer.expression_expanded("shared_pt_oe_bus");

    var glb: usize = 0;
    while (glb < sptclk_polarity_fuses.len) : (glb += 1) {
        try writer.expression("glb");
        try writer.int(glb, 10);
        try writer.expression("name");
        try writer.string(helper.get_glb_name(@intCast(glb)));
        try writer.close();
        writer.set_compact(false);

        const sptclk_fuse = sptclk_polarity_fuses[glb];

        const bus_size = @min(4, dev.num_glbs);
        var n: u8 = 0;
        while (n < bus_size) : (n += 1) {
            try writer.open();
            try writer.print_value("goe{}", .{ n });
            try helper.write_fuse(writer, Fuse.init(sptclk_fuse.row + 1 + n, sptclk_fuse.col));
            try writer.close();
        }

        try writer.close(); // glb
    }

    try helper.write_value(writer, 0, "enabled");
    try helper.write_value(writer, 1, "disabled");

    try writer.close(); // shared_pt_oe_bus

    try writer.done();
}
