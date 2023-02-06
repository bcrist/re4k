const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const jedec = @import("jedec");
const common = @import("common");
const device_info = @import("device_info.zig");
const DeviceInfo = device_info.DeviceInfo;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JedecData = jedec.JedecData;

pub fn main() void {
    helper.main();
}

const Polarity = enum {
    positive,
    negative,
};

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, glb: u8, polarity: Polarity) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    var pin_iter = helper.InputIterator {
        .pins = dev.all_pins,
        .exclude_glb = glb,
        .exclude_clocks = true,
    };
    try design.pinAssignment(.{
        .signal = "sck1",
        .pin = pin_iter.next().?.id,
    });
    try design.pinAssignment(.{
        .signal = "sck2",
        .pin = pin_iter.next().?.id,
    });

    try design.nodeAssignment(.{
        .signal = "out",
        .glb = glb,
        .mc = 3,
    });
    try design.addPT("in", "out.D");
    try design.addPT(.{ "sck1", "sck2" }, switch (polarity) {
        .positive => "out.C",
        .negative => "out.C-",
    });

    var results = try tc.runToolchain(design);
    try helper.logResults(dev.device, "shared_pt_clk_polarity_glb{}_{s}", .{ glb, @tagName(polarity) }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev.device));
    try writer.expressionExpanded("shared_pt_clk_polarity");

    var defaults = std.EnumMap(Polarity, usize) {};

    var glb: u8 = 0;
    while (glb < dev.num_glbs) : (glb += 1) {
        try helper.writeGlb(writer, glb);

        const positive_results = try runToolchain(ta, tc, dev, glb, .positive);
        const negative_results = try runToolchain(ta, tc, dev, glb, .negative);

        const diff = try JedecData.initDiff(ta,
            positive_results.jedec,
            negative_results.jedec,
        );

        var values = std.EnumMap(Polarity, usize) {};

        var bit_value: usize = 1;
        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            try helper.writeFuseOptValue(writer, fuse, bit_value);

            for (std.enums.values(Polarity)) |mode| {
                const results = switch (mode) {
                    .positive => positive_results,
                    .negative => negative_results,
                };
                var val: usize = values.get(mode) orelse 0;
                if (results.jedec.isSet(fuse)) {
                    val |= bit_value;
                }
                values.put(mode, val);
            }

            bit_value *= 2;
        }

        if (diff.countSet() != 1) {
            try helper.err("Expected one shared PT clock polarity fuses, but found {}!", .{ diff.countSet() }, dev, .{ .glb = glb });
        }

        for (std.enums.values(Polarity)) |mode| {
            var val: usize = values.get(mode) orelse 0;
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
        try helper.writeValue(writer, entry.value.*, entry.key);
    }

    try writer.done();

    _ = pa;
}
