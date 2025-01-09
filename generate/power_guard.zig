const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const Device_Info = @import("Device_Info.zig");
const JEDEC_Data = lc4k.JEDEC_Data;
const Fuse = lc4k.Fuse;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const Input_Iterator = helper.Input_Iterator;

pub fn main() void {
    helper.main();
}

fn run_toolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, pin: lc4k.Pin_Info, pg_enabled: bool) !toolchain.Fit_Results {
    var design = Design.init(ta, dev);

    try design.node_assignment(.{
        .signal = "pg_enable",
    });
    try design.add_pt("pg_enable_pin", "pg_enable");

    if (pg_enabled) {
        try design.pin_assignment(.{
            .signal = "in",
            .pin = pin.id,
            .power_guard_signal = "pg_enable",
        });
    } else {
        try design.pin_assignment(.{
            .signal = "in",
            .pin = pin.id,
        });
    }

    var glb: u8 = 0;
    while (glb < dev.num_glbs) : (glb += 1) {
        var iter = Input_Iterator {
            .pins = dev.all_pins,
            .single_glb = glb,
            .exclude_pin = pin.id,
        };

        const signal_name = try std.fmt.allocPrint(ta, "temp{}", .{ glb });
        try design.pin_assignment(.{
            .signal = signal_name,
            .pin = iter.next().?.id,
            .power_guard_signal = "pg_enable",
        });

        if (glb == 0) {
            try design.pin_assignment(.{
                .signal = "pg_enable_pin",
                .pin = iter.next().?.id,
            });
        }
    }

    var results = try tc.run_toolchain(design);
    try helper.log_results(dev.device, "power_guard_pin_{s}_{}", .{ pin.id, pg_enabled }, results);
    try results.check_term();
    return results;
}

var default_enabled: ?u1 = null;
var default_disabled: ?u1 = null;

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("power_guard");

    var pin_iter = Input_Iterator { .pins = dev.all_pins };
    while (pin_iter.next()) |pin| {
        try tc.clean_temp_dir();
        helper.reset_temp();

        const results_enabled = try run_toolchain(ta, tc, dev, pin, true);
        const results_disabled = try run_toolchain(ta, tc, dev, pin, false);

        const diff = try JEDEC_Data.init_diff(ta, results_enabled.jedec, results_disabled.jedec);

        try helper.write_pin(writer, pin);

        var diff_iter = diff.iterator(.{});
        if (diff_iter.next()) |fuse| {
            try writeFuse(fuse, results_enabled.jedec, results_disabled.jedec, writer);
        } else if (dev.device == .LC4128ZE_TQFP100 and std.mem.eql(u8, pin.id, "89")) {
            // The report generated looks correct for this bit, but it doesn't actually set any bit in the jed.
            // In the other packages, CLK0's PGDF bit is 87:98, and that fuse is suspiciously missing
            // for this device, so we're going to assume this is just a bug in the fitter.
            try helper.write_fuse(writer, Fuse.init(87, 98));
        } else {
            try helper.err("Expected one power guard fuse but found none!", .{}, dev, .{ .pin = pin.id });
        }

        if (diff_iter.next()) |fuse| {
            try helper.err("Expected one power guard fuse but found multiple!", .{}, dev, .{ .pin = pin.id });
            try writeFuse(fuse, results_enabled.jedec, results_disabled.jedec, writer);

            while (diff_iter.next()) |f| {
                try writeFuse(f, results_enabled.jedec, results_disabled.jedec, writer);
            }
        }

        try writer.close();
    }

    if (default_enabled) |def| {
        try helper.write_value(writer, def, "from_bie");
    }

    if (default_disabled) |def| {
        try helper.write_value(writer, def, "disabled");
    }

    try writer.done();

    _ = pa;
}

fn writeFuse(fuse: Fuse, results_enabled: JEDEC_Data, results_disabled: JEDEC_Data, writer: *sx.Writer) !void {
    try helper.write_fuse(writer, fuse);

    const enabled_value = results_enabled.get(fuse);
    if (default_enabled) |def| {
        if (enabled_value != def) {
            try helper.write_value(writer, enabled_value, "from_bie");
        }
    } else {
        default_enabled = enabled_value;
    }

    const disabled_value = results_disabled.get(fuse);
    if (default_disabled) |def| {
        if (disabled_value != def) {
            try helper.write_value(writer, disabled_value, "disabled");
        }
    } else {
        default_disabled = disabled_value;
    }
}
