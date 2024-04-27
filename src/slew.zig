const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const jedec = lc4k.jedec;
const device_info = @import("device_info.zig");
const DeviceInfo = device_info.DeviceInfo;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JedecData = jedec.JedecData;
const MacrocellRef = lc4k.MacrocellRef;

pub fn main() void {
    helper.main();
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, pin: lc4k.PinInfo, slew: lc4k.SlewRate) !toolchain.FitResults {
    var design = Design.init(ta, dev);
    try design.pinAssignment(.{
        .signal = "out",
        .pin = pin.id,
        .slew_rate = slew,
    });
    try design.addPT("in", "out");

    var results = try tc.runToolchain(design);
    try helper.logResults(dev.device, "slew_pin_{s}", .{ pin.id }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer) !void {
    var maybe_fallback_fuses: ?std.AutoHashMap(MacrocellRef, []const helper.FuseAndValue) = null;
    if (helper.getInputFile("slew.sx")) |_| {
        maybe_fallback_fuses = try helper.parseFusesForOutputPins(ta, pa, "slew.sx", "slew_rate", null);
    }

    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("slew_rate");

    var default_slow: ?u1 = null;
    var default_fast: ?u1 = null;

    var pin_iter = helper.OutputIterator { .pins = dev.all_pins };
    while (pin_iter.next()) |pin| {
        if (maybe_fallback_fuses) |fallback_fuses| {
            if (std.mem.eql(u8, pin.id, "F8") or std.mem.eql(u8, pin.id, "E3")) {
                // These pins are connected to macrocells, but lpf4k thinks they're dedicated inputs, and won't allow them to be used as outputs.
                const mcref = MacrocellRef.init(pin.glb.?, switch (pin.func) {
                    .io, .io_oe0, .io_oe1 => |mc| mc,
                    else => unreachable,
                });

                if (fallback_fuses.get(mcref)) |fuses| {
                    try helper.writePin(writer, pin);
                    for (fuses) |fuse_and_value| {
                        try helper.writeFuseOptValue(writer, fuse_and_value.fuse, fuse_and_value.value);
                    }
                    try writer.close();
                    continue;
                }
            }
        }

        try tc.cleanTempDir();
        helper.resetTemp();

        const results_slow = try runToolchain(ta, tc, dev, pin, .slow);
        const results_fast = try runToolchain(ta, tc, dev, pin, .fast);

        const diff = try JedecData.initDiff(ta, results_slow.jedec, results_fast.jedec);

        try helper.writePin(writer, pin);

        var diff_iter = diff.iterator(.{});
        if (diff_iter.next()) |fuse| {
            try helper.writeFuse(writer, fuse);

            const slow_value = results_slow.jedec.get(fuse);
            if (default_slow) |def| {
                if (slow_value != def) {
                    try helper.writeValue(writer, slow_value, "slow");
                }
            } else {
                default_slow = slow_value;
            }

            const fast_value = results_fast.jedec.get(fuse);
            if (default_fast) |def| {
                if (fast_value != def) {
                    try helper.writeValue(writer, fast_value, "fast");
                }
            } else {
                default_fast = fast_value;
            }

        } else {
            try helper.err("Expected one slew fuse but found none!", .{}, dev, .{ .pin = pin.id });
            return error.Think;
        }

        if (diff_iter.next()) |_| {
            try helper.err("Expected one slew fuse but found multiple!", .{}, dev, .{ .pin = pin.id });
            return error.Think;
        }

        try writer.close();
    }

    if (default_slow) |def| {
        try helper.writeValue(writer, def, "slow");
    }

    if (default_fast) |def| {
        try helper.writeValue(writer, def, "fast");
    }

    try writer.done();
}
