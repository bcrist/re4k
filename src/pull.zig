const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx.zig");
const core = @import("core.zig");
const jedec = @import("jedec.zig");
const devices = @import("devices/devices.zig");
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

    design.ignore_fitter_warnings = true;
    var results = try tc.runToolchain(design);
    try helper.logReport("pull_pin{s}_{s}", .{ dev.getPins()[pin_index].pin_number(), @tagName(pull) }, results);
    try results.checkTerm();
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

    var float_diff = try JedecData.initEmpty(pa, dev.getJedecWidth(), dev.getJedecHeight());

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

        var diff = try helper.diff(ta, results_pullup.jedec, results_pulldown.jedec);
        diff.raw.setUnion((try helper.diff(ta, results_keeper.jedec, results_pulldown.jedec)).raw);

        if (has_per_pin_config) {
            try writer.expression("pin");
            try writer.printRaw("{s}", .{ pin_number });

            diff.raw.setUnion((try helper.diff(ta, results_float.jedec, results_pulldown.jedec)).raw);
        } else {
            var temp_diff = try helper.diff(ta, results_float.jedec, results_pulldown.jedec);
            var diff_iter = temp_diff.raw.iterator(.{});
            while (diff_iter.next()) |fuse| {
                if (!diff.raw.isSet(fuse)) {
                    if (results_float.jedec.raw.isSet(fuse)) {
                        const row = diff.getRow(@intCast(u32, fuse));
                        const col = diff.getColumn(@intCast(u32, fuse));
                        try std.io.getStdErr().writer().print("Expected additional float fuse differences to be 0-valued fuses: device {s} {}:{}\n", .{ @tagName(dev), row, col });
                    } else {
                        float_diff.raw.set(fuse);
                    }
                }
            }
        }

        var n_fuses: usize = 0;

        var val_float: usize = 0;
        var val_pulldown: usize = 0;
        var val_pullup: usize = 0;
        var val_keeper: usize = 0;

        var bit_value: usize = 1;
        var diff_iter = diff.raw.iterator(.{});
        while (diff_iter.next()) |fuse| {
            const row = diff.getRow(@intCast(u32, fuse));
            const col = diff.getColumn(@intCast(u32, fuse));

            if (results_float.jedec.raw.isSet(fuse)) val_float |= bit_value;
            if (results_pulldown.jedec.raw.isSet(fuse)) val_pulldown |= bit_value;
            if (results_pullup.jedec.raw.isSet(fuse)) val_pullup |= bit_value;
            if (results_keeper.jedec.raw.isSet(fuse)) val_keeper |= bit_value;

            try writer.expression("fuse");
            try writer.printRaw("{}", .{ row });
            try writer.printRaw("{}", .{ col });
            if (bit_value != 1 or !has_per_pin_config) {
                try writer.expression("value");
                try writer.printRaw("{}", .{ bit_value });
                try writer.close();
            }
            try writer.close();

            n_fuses += 1;
            bit_value *= 2;
        }

        if (has_per_pin_config) {
            try writer.close();
        }

        if (n_fuses != 2) {
            try std.io.getStdErr().writer().print("Expected 2 fuses to define bus maintenance options for device {} pin {s}, but found {}!\n", .{ dev, pin_number, n_fuses });
        }

        if (default_val_float) |val| {
            if (val != val_float) {
                try std.io.getStdErr().writer().print("Expected same fuse patterns for all pins in device {}!\n", .{ dev });
            }
        } else {
            default_val_float = val_float;
        }
        if (default_val_pulldown) |val| {
            if (val != val_pulldown) {
                try std.io.getStdErr().writer().print("Expected same fuse patterns for all pins in device {}!\n", .{ dev });
            }
        } else {
            default_val_pulldown = val_pulldown;
        }
        if (default_val_pullup) |val| {
            if (val != val_pullup) {
                try std.io.getStdErr().writer().print("Expected same fuse patterns for all pins in device {}!\n", .{ dev });
            }
        } else {
            default_val_pullup = val_pullup;
        }
        if (default_val_keeper) |val| {
            if (val != val_keeper) {
                try std.io.getStdErr().writer().print("Expected same fuse patterns for all pins in device {}!\n", .{ dev });
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

    if (float_diff.raw.count() > 0) {
        // Some devices have buried I/O cells that aren't connected to any package pin.
        // If the device doesn't have per-pin bus maintenance, and the maintenance is set to float,
        // those extra I/O cells should be configured as outputs to avoid excessive power usage.
        // The remaining fuses in float_diff should do that.
        try writer.expressionExpanded("bus_maintenance_extra");
        var diff_iter = float_diff.raw.iterator(.{});
        while (diff_iter.next()) |fuse| {
            const row = float_diff.getRow(@intCast(u32, fuse));
            const col = float_diff.getColumn(@intCast(u32, fuse));

            try writer.expression("fuse");
            try writer.printRaw("{}", .{ row });
            try writer.printRaw("{}", .{ col });
            try writer.close();
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
