const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx.zig");
const core = @import("core.zig");
const device_pins = @import("devices/device_pins.zig");
const jedec = @import("jedec.zig");
const DeviceType = @import("devices/devices.zig").DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

pub fn main() void {
    helper.main();
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, pin_index: u16, offset: u3) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    try design.pinAssignment(.{
        .signal = "in",
        .pin_index = dev.getClockPin(0).pin_index,
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
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("output_routing_mux");

    var pin_iter = device_pins.OutputIterator {
        .pins = dev.getPins(),
    };

    while (pin_iter.next()) |io| {

        try tc.cleanTempDir();
        helper.resetTemp();

        const results_1 = try runToolchain(ta, tc, dev, io.pin_index, 1);
        const results_2 = try runToolchain(ta, tc, dev, io.pin_index, 2);
        const results_4 = try runToolchain(ta, tc, dev, io.pin_index, 4);

        var diff = try helper.diff(ta, results_1.jedec, results_2.jedec);
        diff.raw.setUnion((try helper.diff(ta, results_1.jedec, results_4.jedec)).raw);

        try writer.expression("pin");
        try writer.printRaw("{s}", .{ io.pin_number });

        var n_fuses: u32 = 0;

        var diff_iter = diff.raw.iterator(.{});
        while (diff_iter.next()) |fuse| {
            const row = diff.getRow(@intCast(u32, fuse));
            const col = diff.getColumn(@intCast(u32, fuse));

            try writer.expression("fuse");
            try writer.printRaw("{}", .{ row });
            try writer.printRaw("{}", .{ col });

            var value: u32 = 0;
            if (results_1.jedec.raw.isSet(fuse)) {
                value += 1;
            }
            if (results_2.jedec.raw.isSet(fuse)) {
                value += 2;
            }
            if (results_4.jedec.raw.isSet(fuse)) {
                value += 4;
            }

            switch (value) {
                1, 2, 4 => {},
                else => {
                    try std.io.getStdErr().writer().print("Expected ORM fuse {}:{} to have a value of 1, 2, or 4, but found {} for pin {s} in device {s}\n", .{ row, col, value, io.pin_number, @tagName(dev) });
                },
            }

            if (value != 1) {
                try writer.expression("value");
                try writer.printRaw("{}", .{ value });
                try writer.close();
            }

            try writer.close();

            n_fuses += 1;
        }

        if (n_fuses != 3) {
            try std.io.getStdErr().writer().print("Expected exactly 3 ORM fuses for pin {s} in device {s}, but found {}!\n", .{ io.pin_number, @tagName(dev), n_fuses });
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
