const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx.zig");
const core = @import("core.zig");
const jedec = @import("jedec.zig");
const devices = @import("devices.zig");
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JedecData = jedec.JedecData;

pub fn main() void {
    helper.main(0);
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, pin_index: u16, offset: u3) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    try design.pinAssignment(.{
        .signal = "in",
        .pin_index = dev.getClockPin(0).?.pin_index,
    });
    try design.pinAssignment(.{
        .signal = "out",
        .pin_index = pin_index,
    });
    // making the main output registered should prevent the use of the ORP bypass,
    // except in the case where offset == 0.
    // We'll test the ORP bypass mux separately, for families that have it.
    try design.addPT("in", "out.D");

    const out_info = dev.getPins()[pin_index].input_output;
    const out_mc = (out_info.mc + offset) & 0xF;

    var mc: u8 = 0;
    while (mc < 16) : (mc += 1) {
        if (mc != out_mc) {
            const signal_d = try std.fmt.allocPrint(ta, "node{}.D", .{ mc });
            const signal = signal_d[0..signal_d.len-2];
            try design.nodeAssignment(.{
                .signal = signal,
                .glb = out_info.glb,
                .mc = mc,
            });
            try design.addPT("in", signal_d);
        }
    }

    var results = try tc.runToolchain(design);
    try helper.logReport("orm_{s}_plus{}", .{ out_info.pin_number, offset }, results);
    try results.checkTerm(false);
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("output_routing_mux");

    var pin_iter = devices.pins.OutputIterator {
        .pins = dev.getPins(),
    };

    while (pin_iter.next()) |io| {

        try tc.cleanTempDir();
        helper.resetTemp();

        const results_1 = try runToolchain(ta, tc, dev, io.pin_index, 1);
        const results_2 = try runToolchain(ta, tc, dev, io.pin_index, 2);
        const results_4 = try runToolchain(ta, tc, dev, io.pin_index, 4);

        var diff = try JedecData.initDiff(ta, results_1.jedec, results_2.jedec);
        diff.unionAll(try JedecData.initDiff(ta, results_1.jedec, results_4.jedec));

        try writer.expression("pin");
        try writer.printRaw("{s}", .{ io.pin_number });

        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            var value: u32 = 0;
            if (results_1.jedec.isSet(fuse)) {
                value += 1;
            }
            if (results_2.jedec.isSet(fuse)) {
                value += 2;
            }
            if (results_4.jedec.isSet(fuse)) {
                value += 4;
            }

            switch (value) {
                1, 2, 4 => {},
                else => {
                    try helper.err("Expected ORM fuse {}:{} to have a value of 1, 2, or 4, but found {}",
                        .{ fuse.row, fuse.col, value }, dev, .{ .pin_index = io.pin_index });
                },
            }

            try helper.writeFuseOptValue(writer, fuse, value);
        }

        if (diff.countSet() != 3) {
            try helper.err("Expected exactly 3 ORM fuses but found {}!", .{ diff.countSet() }, dev, .{ .pin_index = io.pin_index });
        }

        try writer.close();
    }

    try writer.expression("value");
    try writer.printRaw("0 \"from MC+0\"", .{});
    try writer.close();
    try writer.expression("value");
    try writer.printRaw("1 \"from MC+1\"", .{});
    try writer.close();
    try writer.expression("value");
    try writer.printRaw("2 \"from MC+2\"", .{});
    try writer.close();
    try writer.expression("value");
    try writer.printRaw("3 \"from MC+3\"", .{});
    try writer.close();
    try writer.expression("value");
    try writer.printRaw("4 \"from MC+4\"", .{});
    try writer.close();
    try writer.expression("value");
    try writer.printRaw("5 \"from MC+5\"", .{});
    try writer.close();
    try writer.expression("value");
    try writer.printRaw("6 \"from MC+6\"", .{});
    try writer.close();
    try writer.expression("value");
    try writer.printRaw("7 \"from MC+7\"", .{});
    try writer.close();

    try writer.done();

    _ = pa;
}
