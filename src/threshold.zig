const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx.zig");
const core = @import("core.zig");
const JedecData = @import("jedec.zig").JedecData;
const DeviceType = @import("device.zig").DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

pub fn main() void {
    helper.main();
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, pin_index: u16, iostd: core.LogicLevels) !toolchain.FitResults {
    var design = Design.init(ta, dev);
    try design.pinAssignment(.{
        .signal = "in",
        .pin_index = pin_index,
        .iostd = iostd,
    });
    try design.addPT("in", "out");

    var results = try tc.runToolchain(design);
    try results.checkTerm();
    return results;
}

var default_high: ?u1 = null;
var default_low: ?u1 = null;

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("input_threshold");

    var pin_index: u16 = 0;
    while (pin_index < dev.getNumPins()) : (pin_index += 1) {
        const pin_info = dev.getPinInfo(pin_index);
        switch (pin_info) {
            .input_output, .input, .clock_input => {},
            .misc => continue,
        }
        const pin_number = pin_info.pin_number();

        try tc.cleanTempDir();
        helper.resetTemp();

        const results_high = try runToolchain(ta, tc, dev, pin_index, .LVCMOS33);
        const results_low = try runToolchain(ta, tc, dev, pin_index, .LVCMOS15);

        var diff = try results_high.jedec.clone(ta);
        try diff.xor(results_low.jedec);

        try writer.expression("pin");
        try writer.printRaw("{s}", .{ pin_number });

        var diff_iter = diff.raw.iterator(.{});
        if (diff_iter.next()) |fuse| {
            try writeFuse(fuse, results_high.jedec, results_low.jedec, diff, writer);
        } else {
            try std.io.getStdErr().writer().print("Expected one threshold fuse for device {} pin {s} but found none!\n", .{ dev, pin_number });
        }

        if (diff_iter.next()) |fuse| {
            try std.io.getStdErr().writer().print("Expected one threshold fuse for device {} pin {s} but found multiple!\n", .{ dev, pin_number });
            try writeFuse(fuse, results_high.jedec, results_low.jedec, diff, writer);

            while (diff_iter.next()) |f| {
                try writeFuse(f, results_high.jedec, results_low.jedec, diff, writer);
            }
        }

        try writer.close();
    }

    if (default_high) |def| {
        try writer.expression("value");
        try writer.printRaw("{} high", .{ def });
        try writer.close();
    }

    if (default_low) |def| {
        try writer.expression("value");
        try writer.printRaw("{} low", .{ def });
        try writer.close();
    }

    try writer.done();

    _ = pa;
}

fn writeFuse(fuse: usize, results_high: JedecData, results_low: JedecData, diff: JedecData, writer: anytype) !void {
    const row = diff.getRow(@intCast(u32, fuse));
    const col = diff.getColumn(@intCast(u32, fuse));

    try writer.expression("fuse");
    try writer.printRaw("{}", .{ row });
    try writer.printRaw("{}", .{ col });
    try writer.close();

    const high_value = results_high.get(row, col);
    if (default_high) |def| {
        if (high_value != def) {
            try writer.expression("value");
            try writer.printRaw("{} high", .{ high_value });
            try writer.close();
        }
    } else {
        default_high = high_value;
    }

    const low_value = results_low.get(row, col);
    if (default_low) |def| {
        if (low_value != def) {
            try writer.expression("value");
            try writer.printRaw("{} low", .{ low_value });
            try writer.close();
        }
    } else {
        default_low = low_value;
    }
}
