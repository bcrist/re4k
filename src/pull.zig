const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx.zig");
const core = @import("core.zig");
const jedec = @import("jedec.zig");
const devices = @import("devices.zig");
const JedecData = jedec.JedecData;
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

pub fn main() void {
    helper.main();
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, pin_index: u16, pull: core.BusMaintenanceType) !toolchain.FitResults {
    var design = Design.init(ta, dev);
    try design.nodeAssignment(.{
        .signal = "out",
        .glb = 0,
        .mc = 0,
    });
    try design.pinAssignment(.{
        .signal = "in",
        .pin_index = pin_index,
        .bus_maintenance = pull,
    });
    try design.addPT("in", "out");

    var results = try tc.runToolchain(design);
    try helper.logReport("pull_pin{s}_{s}", .{ dev.getPins()[pin_index].pin_number(), @tagName(pull) }, results);
    try results.checkTerm(true);
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("bus_maintenance");

    var default_val_float: ?usize = null;
    var default_val_pulldown: ?usize = null;
    var default_val_pullup: ?usize = null;
    var default_val_keeper: ?usize = null;

    var has_per_pin_config = dev.getFamily() == .zero_power_enhanced;

    var max_pin = if (has_per_pin_config) dev.getNumPins() else 1;

    var float_diff = try dev.initJedecZeroes(pa);

    var pin_index: u16 = 0;
    while (pin_index < max_pin) : (pin_index += 1) {
        const pin_info = dev.getPins()[pin_index];
        switch (pin_info) {
            .input_output, .input, .clock_input => {},
            .misc => {
                if (!has_per_pin_config) max_pin += 1;
                continue;
            },
        }
        const pin_number = pin_info.pin_number();

        try tc.cleanTempDir();
        helper.resetTemp();

        const results_float = try runToolchain(ta, tc, dev, pin_index, .float);
        const results_pulldown = try runToolchain(ta, tc, dev, pin_index, .pulldown);
        const results_pullup = try runToolchain(ta, tc, dev, pin_index, .pullup);
        const results_keeper = try runToolchain(ta, tc, dev, pin_index, .keeper);

        var diff = try JedecData.initDiff(ta, results_pullup.jedec, results_pulldown.jedec);
        diff.unionAll(try JedecData.initDiff(ta, results_keeper.jedec, results_pulldown.jedec));

        if (has_per_pin_config) {
            try writer.expression("pin");
            try writer.printRaw("{s}", .{ pin_number });

            diff.unionAll(try JedecData.initDiff(ta, results_float.jedec, results_pulldown.jedec));
        } else {
            var temp_diff = try JedecData.initDiff(ta, results_float.jedec, results_pulldown.jedec);
            var diff_iter = temp_diff.iterator(.{});
            while (diff_iter.next()) |fuse| {
                if (!diff.isSet(fuse)) {
                    if (results_float.jedec.isSet(fuse)) {
                        try helper.err("Expected additional float fuse differences to be 0-valued fuses: {}:{}\n", .{ fuse.row, fuse.col }, dev, .{ .pin_index = pin_index });
                    } else {
                        float_diff.put(fuse, 1);
                    }
                }
            }
        }

        var val_float: usize = 0;
        var val_pulldown: usize = 0;
        var val_pullup: usize = 0;
        var val_keeper: usize = 0;

        var bit_value: usize = 1;
        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            if (results_float.jedec.isSet(fuse)) val_float |= bit_value;
            if (results_pulldown.jedec.isSet(fuse)) val_pulldown |= bit_value;
            if (results_pullup.jedec.isSet(fuse)) val_pullup |= bit_value;
            if (results_keeper.jedec.isSet(fuse)) val_keeper |= bit_value;

            if (bit_value != 1 or !has_per_pin_config) {
                try helper.writeFuseValue(writer, fuse, bit_value);
            } else {
                try helper.writeFuse(writer, fuse);
            }

            bit_value *= 2;
        }

        if (has_per_pin_config) {
            try writer.close();
        }

        if (diff.countSet() != 2) {
            try helper.err("Expected 2 fuses to define bus maintenance options, but found {}!\n", .{ diff.countSet() }, dev, .{ .pin_index = pin_index });
        }

        if (default_val_float) |val| {
            if (val != val_float) {
                try helper.err("Expected same fuse patterns for all pins!", .{}, dev, .{ .pin_index = pin_index });
            }
        } else {
            default_val_float = val_float;
        }
        if (default_val_pulldown) |val| {
            if (val != val_pulldown) {
                try helper.err("Expected same fuse patterns for all pins!", .{}, dev, .{ .pin_index = pin_index });
            }
        } else {
            default_val_pulldown = val_pulldown;
        }
        if (default_val_pullup) |val| {
            if (val != val_pullup) {
                try helper.err("Expected same fuse patterns for all pins!", .{}, dev, .{ .pin_index = pin_index });
            }
        } else {
            default_val_pullup = val_pullup;
        }
        if (default_val_keeper) |val| {
            if (val != val_keeper) {
                try helper.err("Expected same fuse patterns for all pins!", .{}, dev, .{ .pin_index = pin_index });
            }
        } else {
            default_val_keeper = val_keeper;
        }
    }

    if (default_val_pullup) |val| {
        try writer.expression("value");
        try writer.printRaw("{} pullup", .{ val });
        try writer.close();
    }

    if (default_val_keeper) |val| {
        try writer.expression("value");
        try writer.printRaw("{} keeper", .{ val });
        try writer.close();
    }

    if (default_val_float) |val| {
        try writer.expression("value");
        try writer.printRaw("{} float", .{ val });
        try writer.close();
    }

    if (default_val_pulldown) |val| {
        try writer.expression("value");
        try writer.printRaw("{} pulldown", .{ val });
        try writer.close();
    }

    try writer.close();

    if (float_diff.countSet() > 0) {
        // Some devices have buried I/O cells that aren't connected to any package pin.
        // If the device doesn't have per-pin bus maintenance, and the maintenance is set to float,
        // those extra I/O cells should be configured as outputs to avoid excessive power usage.
        // The remaining fuses in float_diff should do that.
        try writer.expressionExpanded("bus_maintenance_extra");
        var diff_iter = float_diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            try helper.writeFuse(writer, fuse);
        }

        try writer.expression("value");
        try writer.printRaw("0 float", .{});
        try writer.close();
        try writer.expression("value");
        try writer.printRaw("1 other", .{});
        try writer.close();
    }

    try writer.done();

    _ = pa;
}
