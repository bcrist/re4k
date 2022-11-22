const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const jedec = @import("jedec.zig");
const core = @import("core.zig");
const devices = @import("devices.zig");
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JedecData = jedec.JedecData;
const Fuse = jedec.Fuse;

pub fn main() void {
    helper.main(1);
}

const Polarity = enum {
    positive,
    negative,
};

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, oe0: Polarity, oe1: Polarity, use_goe_pins: bool) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    if (use_goe_pins) {
        try design.pinAssignment(.{
            .signal = "oe0",
            .pin_index = dev.getGOEPin(0).pin_index,
        });
        try design.pinAssignment(.{
            .signal = "oe1",
            .pin_index = dev.getGOEPin(1).pin_index,
        });
    } else {
        var pin_iter = devices.pins.InputIterator {
            .pins = dev.getPins(),
            .exclude_glb = 0,
            .exclude_goes = true,
        };
        try design.pinAssignment(.{
            .signal = "oe0",
            .pin_index = pin_iter.next().?.pin_index(),
        });
        try design.pinAssignment(.{
            .signal = "oe1",
            .pin_index = pin_iter.next().?.pin_index(),
        });
    }

    var pin_iter = devices.pins.OutputIterator {
        .pins = dev.getPins(),
        .single_glb = 0,
        .exclude_goes = true,
    };
    var n: u1 = 0;
    while (pin_iter.next()) |io| {
        var oe_signal_name = try std.fmt.allocPrint(ta, "out{}.OE", .{ io.pin_index });
        const signal_name = oe_signal_name[0..oe_signal_name.len-3];

        try design.pinAssignment(.{
            .signal = signal_name,
            .pin_index = io.pin_index,
        });

        try design.addPT(.{ "x1", "x2" }, signal_name);
        try design.addPT(.{ "x1", "x3" }, signal_name);
        try design.addPT(.{ "x1", "x4" }, signal_name);
        try design.addPT(.{ "x2", "x3" }, signal_name);
        try design.addPT(.{ "x2", "x4" }, signal_name);

        // Note: using `.OE-` instead of inverting the inputs seems like it should work just as well,
        // and the fitter accepts that and shows it the same way in the post-fit equations, but
        // it doesn't actually invert the GOE signal.  Definitely a fitter bug.
        try design.addPT(switch (n) {
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

    var results = try tc.runToolchain(design);
    try helper.logResults("goe_polarity_eoe0_{s}_eoe1_{s}", .{ @tagName(oe0), @tagName(oe1) }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    const sptclk_polarity_fuses = try helper.parseSharedPTClockPolarityFuses(ta, pa, dev);

    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("goe_polarity");

    // Getting the fitter to output specific GOE configurations has proven extremely difficult.  In particular, it seems incapable of
    // routing more than 2 GOEs simultaneously for some reason, even though it should be easily possible to do 4.  So most of what we're
    // going to do here is just spit out the fuses that we expect, based on manually reverse engineering with LC4032ZE and LC4064ZC devices.
    // We're going to assume that other devices use the same layout.  In particular, the assumptions we're making are:
    //
    //    * GOE polarity fuses are always in a vertical block of 4 fuses, with GOE0 polarity at the top and GOE3 polarity at the bottom
    //    * For LC4032 devices, the first pin GOE (i.e. not from the shared OE bus) corresponds to GOE2, and the second corresponds to GOE3
    //    * For non-LC4032 devices, the first pin GOE corresponds to GOE0 and the second to GOE1
    //    * For non-LC4032 devices, the GOE0/1 source fuses are always directly above the GOE polarity fuses, and 0 means "use external pin as GOE"
    //    * Shared PT OE routing fuses are in a single block, between the shared PT clock polarity and shared PT async polarity fuses (2 for LC4032, 4 for others)

    const results_pos_pos = try runToolchain(ta, tc, dev, .positive, .positive, true);
    const results_pos_neg = try runToolchain(ta, tc, dev, .positive, .negative, true);
    const results_neg_pos = try runToolchain(ta, tc, dev, .negative, .positive, true);
    const results_neg_neg = try runToolchain(ta, tc, dev, .negative, .negative, true);

    var combined_diff = try JedecData.initDiff(ta,
        results_pos_pos.jedec,
        results_neg_neg.jedec,
    );

    combined_diff.unionDiff(results_pos_pos.jedec, results_pos_neg.jedec);
    combined_diff.unionDiff(results_pos_pos.jedec, results_neg_pos.jedec);

    if (combined_diff.countSet() != 2) {
        try helper.err("Expected two fuses for GOE2/3 polarity shared PT clock polarity fuses, but found {}!", .{ combined_diff.countSet() }, dev, .{});
        return error.Unexpected;
    }
    var oe0_diff = try JedecData.initDiff(ta, results_pos_pos.jedec, results_neg_pos.jedec);
    if (oe0_diff.countSet() != 1) {
        try helper.err("Expected one fuse for GOE2 polarity shared PT clock polarity fuses, but found {}!", .{ oe0_diff.countSet() }, dev, .{});
        return error.Unexpected;
    }
    var oe1_diff = try JedecData.initDiff(ta, results_pos_pos.jedec, results_pos_neg.jedec);
    if (oe1_diff.countSet() != 1) {
        try helper.err("Expected one fuse for GOE3 polarity shared PT clock polarity fuses, but found {}!", .{ oe1_diff.countSet() }, dev, .{});
        return error.Unexpected;
    }

    try writer.expression("goe0");
    var iter = oe0_diff.iterator(.{});
    var fuse = iter.next().?;
    if (results_pos_pos.jedec.get(fuse) != 1) try helper.err("Expected OE0 fuse to be 1 for positive", .{}, dev, .{});
    if (results_pos_neg.jedec.get(fuse) != 1) try helper.err("Expected OE0 fuse to be 1 for positive", .{}, dev, .{});
    if (results_neg_pos.jedec.get(fuse) != 0) try helper.err("Expected OE0 fuse to be 0 for negative", .{}, dev, .{});
    if (results_neg_neg.jedec.get(fuse) != 0) try helper.err("Expected OE0 fuse to be 0 for negative", .{}, dev, .{});
    if (dev.getNumGlbs() < 4) {
        fuse = Fuse.init(fuse.row - 2, fuse.col);
    }
    try helper.writeFuse(writer, fuse);
    try writer.close();

    try writer.expression("goe1");
    iter = oe1_diff.iterator(.{});
    fuse = iter.next().?;
    if (results_pos_pos.jedec.get(fuse) != 1) try helper.err("Expected OE1 fuse to be 1 for positive", .{}, dev, .{});
    if (results_pos_neg.jedec.get(fuse) != 0) try helper.err("Expected OE1 fuse to be 0 for negative", .{}, dev, .{});
    if (results_neg_pos.jedec.get(fuse) != 1) try helper.err("Expected OE1 fuse to be 1 for positive", .{}, dev, .{});
    if (results_neg_neg.jedec.get(fuse) != 0) try helper.err("Expected OE1 fuse to be 0 for negative", .{}, dev, .{});
    if (dev.getNumGlbs() < 4) {
        fuse = Fuse.init(fuse.row - 2, fuse.col);
    }
    try helper.writeFuse(writer, fuse);
    try writer.close();

    try writer.expression("goe2");
    iter = oe0_diff.iterator(.{});
    fuse = iter.next().?;
    if (dev.getNumGlbs() >= 4) {
        fuse = Fuse.init(fuse.row + 2, fuse.col);
    }
    try helper.writeFuse(writer, fuse);
    try writer.close();

    try writer.expression("goe3");
    iter = oe1_diff.iterator(.{});
    fuse = iter.next().?;
    if (dev.getNumGlbs() >= 4) {
        fuse = Fuse.init(fuse.row + 2, fuse.col);
    }
    try helper.writeFuse(writer, fuse);
    try writer.close();

    try writer.expression("value");
    try writer.int(0, 10);
    try writer.string("active_low");
    try writer.close();

    try writer.expression("value");
    try writer.int(1, 10);
    try writer.string("active_high");
    try writer.close();

    try writer.close(); // goe_polarity


    if (dev.getNumGlbs() >= 4) {
        try writer.expressionExpanded("goe_source");

        try writer.expression("goe0");
        iter = oe0_diff.iterator(.{});
        fuse = iter.next().?;
        try helper.writeFuse(writer, Fuse.init(fuse.row - 2, fuse.col));
        try writer.close();

        try writer.expression("goe1");
        iter = oe1_diff.iterator(.{});
        fuse = iter.next().?;
        try helper.writeFuse(writer, Fuse.init(fuse.row - 2, fuse.col));
        try writer.close();

        try writer.expression("value");
        try writer.int(0, 10);
        try writer.string("pin");
        try writer.close();

        try writer.expression("value");
        try writer.int(1, 10);
        try writer.string("shared_ptoe_bus");
        try writer.close();

        try writer.close(); // goe_source
    }

    try writer.expressionExpanded("shared_ptoe_bus");

    var glb: usize = 0;
    while (glb < sptclk_polarity_fuses.len) : (glb += 1) {
        try writer.expression("glb");
        try writer.int(glb, 10);
        try writer.expression("name");
        try writer.string(devices.getGlbName(@intCast(u8, glb)));
        try writer.close();
        writer.setCompact(false);

        const sptclk_fuse = sptclk_polarity_fuses[glb];

        const bus_size = @min(4, dev.getNumGlbs());
        var n: u8 = 0;
        while (n < bus_size) : (n += 1) {
            try writer.open();
            try writer.printValue("goe{}", .{ n });
            try helper.writeFuse(writer, Fuse.init(sptclk_fuse.row + 1 + n, sptclk_fuse.col));
            try writer.close();
        }

        try writer.close(); // glb
    }

    try writer.expression("value");
    try writer.int(0, 10);
    try writer.string("enabled");
    try writer.close();

    try writer.expression("value");
    try writer.int(1, 10);
    try writer.string("disabled");
    try writer.close();

    try writer.close(); // shared_ptoe_bus

    try writer.done();
}
