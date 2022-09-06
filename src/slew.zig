const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx.zig");
const core = @import("core.zig");
const DeviceType = @import("device.zig").DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

pub fn main() void {
    helper.main();
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, pin_index: u16, slew: core.SlewRate) !toolchain.FitResults {
    var design = Design.init(ta, dev);
    try design.pinAssignment(.{
        .signal = "out",
        .pin_index = pin_index,
        .slew_rate = slew,
    });
    try design.addPT("in", "out");

    var results = try tc.runToolchain(design);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("slew_rate");

    var default_slow: ?u1 = null;
    var default_fast: ?u1 = null;

    var pin_index: u16 = 0;
    while (pin_index < dev.getNumPins()) : (pin_index += 1) {
        const pin_info = dev.getPinInfo(pin_index);
        std.debug.assert(pin_index == pin_info.pin_index());
        switch (pin_info) {
            .input_output => {},
            else => continue,
        }
        const pin_number = pin_info.pin_number();

        try tc.cleanTempDir();
        helper.resetTemp();

        const results_slow = try runToolchain(ta, tc, dev, pin_index, .slow);
        const results_fast = try runToolchain(ta, tc, dev, pin_index, .fast);

        var diff = try results_slow.jedec.clone(ta);
        try diff.xor(results_fast.jedec);

        try writer.expression("pin");
        try writer.printRaw("{s}", .{ pin_number });

        var diff_iter = diff.raw.iterator(.{});
        if (diff_iter.next()) |fuse| {
            const row = diff.getRow(@intCast(u32, fuse));
            const col = diff.getColumn(@intCast(u32, fuse));

            try writer.expression("fuse");
            try writer.printRaw("{}", .{ row });
            try writer.printRaw("{}", .{ col });

            const slow_value = results_slow.jedec.get(row, col);
            if (default_slow) |def| {
                if (slow_value != def) {
                    try writer.expression("value");
                    try writer.printRaw("{} slow", .{ slow_value });
                    try writer.close();
                }
            } else {
                default_slow = slow_value;
            }

            const fast_value = results_fast.jedec.get(row, col);
            if (default_fast) |def| {
                if (fast_value != def) {
                    try writer.expression("value");
                    try writer.printRaw("{} fast", .{ fast_value });
                    try writer.close();
                }
            } else {
                default_fast = fast_value;
            }

            try writer.close();

        } else {
            try std.io.getStdErr().writer().print("Expected one slew fuse for device {} pin {s} but found none!\n", .{ dev, pin_number });
            return error.Think;
        }

        if (diff_iter.next()) |_| {
            try std.io.getStdErr().writer().print("Expected one slew fuse for device {} pin {s} but found multiple!\n", .{ dev, pin_number });
            return error.Think;
        }

        try writer.close();
    }

    if (default_slow) |def| {
        try writer.expression("value");
        try writer.printRaw("{} slow", .{ def });
        try writer.close();
    }

    if (default_fast) |def| {
        try writer.expression("value");
        try writer.printRaw("{} fast", .{ def });
        try writer.close();
    }

    try writer.done();

    _ = pa;
}
