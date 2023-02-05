const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const common = @import("common");
const jedec = @import("jedec");
const device_info = @import("device_info.zig");
const JedecData = jedec.JedecData;
const DeviceInfo = device_info.DeviceInfo;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

pub fn main() void {
    helper.main(0);
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, pin: common.PinInfo, pull: common.BusMaintenance) !toolchain.FitResults {
    var design = Design.init(ta, dev);
    try design.nodeAssignment(.{
        .signal = "out",
        .glb = 0,
        .mc = 0,
    });
    try design.pinAssignment(.{
        .signal = "in",
        .pin = pin.id,
        .bus_maintenance = pull,
    });
    try design.addPT("in", "out");

    var results = try tc.runToolchain(design);
    try helper.logResults(dev.device, "pull_pin{s}_{s}", .{ pin.id, @tagName(pull) }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev.device));
    try writer.expressionExpanded("bus_maintenance");

    var default_val_float: ?usize = null;
    var default_val_pulldown: ?usize = null;
    var default_val_pullup: ?usize = null;
    var default_val_keeper: ?usize = null;

    var has_per_pin_config = dev.family == .zero_power_enhanced;


    var float_diff = try JedecData.initEmpty(pa, dev.jedec_dimensions);

    var max_pin = if (has_per_pin_config) dev.all_pins.len else 1;
    var pin_index: usize = 0;
    while (pin_index < max_pin) : (pin_index += 1) {
        const pin = dev.all_pins[pin_index];
        switch (pin.func) {
            .io, .io_oe0, .io_oe1, .input, .clock => {},
            else => {
                if (!has_per_pin_config) max_pin += 1;
                continue;
            },
        }

        try tc.cleanTempDir();
        helper.resetTemp();

        const results_float = try runToolchain(ta, tc, dev, pin, .float);
        const results_pulldown = try runToolchain(ta, tc, dev, pin, .pulldown);
        const results_pullup = try runToolchain(ta, tc, dev, pin, .pullup);
        const results_keeper = try runToolchain(ta, tc, dev, pin, .keeper);

        var diff = try JedecData.initDiff(ta, results_pullup.jedec, results_pulldown.jedec);
        diff.unionDiff(results_keeper.jedec, results_pulldown.jedec);

        if (has_per_pin_config) {
            try helper.writePin(writer, pin);

            diff.unionDiff(results_float.jedec, results_pulldown.jedec);
        } else {
            var temp_diff = try JedecData.initDiff(ta, results_float.jedec, results_pulldown.jedec);
            var diff_iter = temp_diff.iterator(.{});
            while (diff_iter.next()) |fuse| {
                if (!diff.isSet(fuse)) {
                    if (results_float.jedec.isSet(fuse)) {
                        try helper.err("Expected additional float fuse differences to be 0-valued fuses: {}:{}\n", .{ fuse.row, fuse.col }, dev, .{ .pin = pin.id });
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
            try helper.err("Expected 2 fuses to define bus maintenance options, but found {}!\n", .{ diff.countSet() }, dev, .{ .pin = pin.id });
        }

        if (default_val_float) |val| {
            if (val != val_float) {
                try helper.err("Expected same fuse patterns for all pins!", .{}, dev, .{ .pin = pin.id });
            }
        } else {
            default_val_float = val_float;
        }
        if (default_val_pulldown) |val| {
            if (val != val_pulldown) {
                try helper.err("Expected same fuse patterns for all pins!", .{}, dev, .{ .pin = pin.id });
            }
        } else {
            default_val_pulldown = val_pulldown;
        }
        if (default_val_pullup) |val| {
            if (val != val_pullup) {
                try helper.err("Expected same fuse patterns for all pins!", .{}, dev, .{ .pin = pin.id });
            }
        } else {
            default_val_pullup = val_pullup;
        }
        if (default_val_keeper) |val| {
            if (val != val_keeper) {
                try helper.err("Expected same fuse patterns for all pins!", .{}, dev, .{ .pin = pin.id });
            }
        } else {
            default_val_keeper = val_keeper;
        }
    }

    if (default_val_pullup) |val| {
        try helper.writeValue(writer, val, .pullup);
    }

    if (default_val_keeper) |val| {
        try helper.writeValue(writer, val, .keeper);
    }

    if (default_val_float) |val| {
        try helper.writeValue(writer, val, .float);
    }

    if (default_val_pulldown) |val| {
        try helper.writeValue(writer, val, .pulldown);
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

        try helper.writeValue(writer, 0, .float);
        try helper.writeValue(writer, 1, .other);
    }

    try writer.done();
}
