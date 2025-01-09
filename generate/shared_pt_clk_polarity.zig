const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const Device_Info = @import("Device_Info.zig");
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JEDEC_Data = lc4k.JEDEC_Data;

pub fn main() void {
    helper.main();
}

const Polarity = enum {
    positive,
    negative,
};

fn run_toolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, glb: u8, polarity: Polarity) !toolchain.Fit_Results {
    var design = Design.init(ta, dev);

    var pin_iter = helper.Input_Iterator {
        .pins = dev.all_pins,
        .exclude_glb = glb,
        .exclude_clocks = true,
    };
    try design.pin_assignment(.{
        .signal = "sck1",
        .pin = pin_iter.next().?.id,
    });
    try design.pin_assignment(.{
        .signal = "sck2",
        .pin = pin_iter.next().?.id,
    });

    try design.node_assignment(.{
        .signal = "out",
        .glb = glb,
        .mc = 3,
    });
    try design.add_pt("in", "out.D");
    try design.add_pt(.{ "sck1", "sck2" }, switch (polarity) {
        .positive => "out.C",
        .negative => "out.C-",
    });

    var results = try tc.run_toolchain(design);
    try helper.log_results(dev.device, "shared_pt_clk_polarity_glb{}_{s}", .{ glb, @tagName(polarity) }, results);
    try results.check_term();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("shared_pt_clk_polarity");

    var defaults = std.EnumMap(Polarity, usize) {};

    var glb: u8 = 0;
    while (glb < dev.num_glbs) : (glb += 1) {
        try helper.write_glb(writer, glb);

        const positive_results = try run_toolchain(ta, tc, dev, glb, .positive);
        const negative_results = try run_toolchain(ta, tc, dev, glb, .negative);

        const diff = try JEDEC_Data.init_diff(ta,
            positive_results.jedec,
            negative_results.jedec,
        );

        var values = std.EnumMap(Polarity, usize) {};

        var bit_value: usize = 1;
        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            try helper.write_fuse_opt_value(writer, fuse, bit_value);

            for (std.enums.values(Polarity)) |mode| {
                const results = switch (mode) {
                    .positive => positive_results,
                    .negative => negative_results,
                };
                var val: usize = values.get(mode) orelse 0;
                if (results.jedec.is_set(fuse)) {
                    val |= bit_value;
                }
                values.put(mode, val);
            }

            bit_value *= 2;
        }

        if (diff.count_set() != 1) {
            try helper.err("Expected one shared PT clock polarity fuses, but found {}!", .{ diff.count_set() }, dev, .{ .glb = glb });
        }

        for (std.enums.values(Polarity)) |mode| {
            const val: usize = values.get(mode) orelse 0;
            if (defaults.get(mode)) |def| {
                if (def != val) {
                    try helper.err("Expected all glbs to share the same bit patterns!", .{}, dev, .{ .glb = glb });
                }
            } else {
                defaults.put(mode, val);
            }
        }
        try writer.close(); // glb
    }

    var default_iter = defaults.iterator();
    while (default_iter.next()) |entry| {
        try helper.write_value(writer, entry.value.*, entry.key);
    }

    try writer.done();

    _ = pa;
}
