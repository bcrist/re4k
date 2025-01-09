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
const Logic_Levels = toolchain.Logic_Levels;
const MC_Ref = lc4k.MC_Ref;

pub fn main() void {
    helper.main();
}

fn run_toolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, pin: lc4k.Pin_Info, iostd: Logic_Levels) !toolchain.Fit_Results {
    var design = Design.init(ta, dev);
    try design.pin_assignment(.{
        .signal = "in",
        .pin = pin.id,
        .iostd = iostd,
    });
    try design.add_pt("in", "out");

    var results = try tc.run_toolchain(design);
    try helper.log_results(dev.device, "threshold_pin_{s}", .{ pin.id }, results);
    try results.check_term();
    return results;
}

var default_high: ?u1 = null;
var default_low: ?u1 = null;

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    var maybe_fallback_output_fuse_map: ?std.AutoHashMap(MC_Ref, []const helper.Fuse_And_Value) = null;
    var fallback_output_fuse_data = try JEDEC_Data.init_empty(pa, dev.jedec_dimensions);
    if (helper.get_input_file("threshold.sx")) |_| {
        const map = try helper.parse_fuses_for_output_pins(ta, pa, "threshold.sx", "input_threshold", null);
        var iter = map.iterator();
        while (iter.next()) |fuses| {
            for (fuses.value_ptr.*) |fuseAndValue| {
                fallback_output_fuse_data.put(fuseAndValue.fuse, 1);
            }
        }
        maybe_fallback_output_fuse_map = map;
    }

    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("input_threshold");

    var pin_iter = helper.Input_Iterator { .pins = dev.all_pins };
    while (pin_iter.next()) |pin| {
        try tc.clean_temp_dir();
        helper.reset_temp();

        const results_high = try run_toolchain(ta, tc, dev, pin, .LVCMOS33);
        const results_low = try run_toolchain(ta, tc, dev, pin, .LVCMOS15);

        const diff = try JEDEC_Data.init_diff(ta, results_high.jedec, results_low.jedec);

        try helper.write_pin(writer, pin);

        var diff_iter = diff.iterator(.{});
        if (diff_iter.next()) |fuse1| {
            if (diff_iter.next()) |fuse2| {
                const fuse1_is_macrocell = fallback_output_fuse_data.is_set(fuse1);
                const fuse2_is_macrocell = fallback_output_fuse_data.is_set(fuse2);

                if (fuse1_is_macrocell and !fuse2_is_macrocell) {
                    try writeFuse(fuse2, results_high.jedec, results_low.jedec, writer);
                    while (diff_iter.next()) |f| {
                        try helper.err("Expected one threshold fuse but found multiple!", .{}, dev, .{ .pin = pin.id });
                        try writeFuse(f, results_high.jedec, results_low.jedec, writer);
                    }
                } else if (fuse2_is_macrocell and !fuse1_is_macrocell) {
                    try writeFuse(fuse1, results_high.jedec, results_low.jedec, writer);
                    while (diff_iter.next()) |f| {
                        try helper.err("Expected one threshold fuse but found multiple!", .{}, dev, .{ .pin = pin.id });
                        try writeFuse(f, results_high.jedec, results_low.jedec, writer);
                    }
                } else {
                    try helper.err("Expected one threshold fuse but found multiple!", .{}, dev, .{ .pin = pin.id });
                    try writeFuse(fuse1, results_high.jedec, results_low.jedec, writer);
                    try writeFuse(fuse2, results_high.jedec, results_low.jedec, writer);

                    while (diff_iter.next()) |f| {
                        try writeFuse(f, results_high.jedec, results_low.jedec, writer);
                    }
                }
            } else {
                try writeFuse(fuse1, results_high.jedec, results_low.jedec, writer);
            }
        } else if (maybe_fallback_output_fuse_map) |fallback| {
            if (pin.mc()) |mcref| {
                if (fallback.get(mcref)) |fuses| {
                    for (fuses) |fuseAndValue| {
                        // workaround for fitter bug, see readme.md
                        try helper.write_fuse(writer, fuseAndValue.fuse);
                    }
                } else {
                    try helper.err("Expected one threshold fuse but found none!", .{}, dev, .{ .pin = pin.id });
                }
            } else {
                try helper.err("Expected one threshold fuse but found none!", .{}, dev, .{ .pin = pin.id });
            }
        } else {
            try helper.err("Expected one threshold fuse but found none!", .{}, dev, .{ .pin = pin.id });
        }

        try writer.close();
    }

    if (default_high) |def| {
        try helper.write_value(writer, def, "high");
    }

    if (default_low) |def| {
        try helper.write_value(writer, def, "low");
    }

    try writer.done();
}

fn writeFuse(fuse: Fuse, results_high: JEDEC_Data, results_low: JEDEC_Data, writer: *sx.Writer) !void {
    try helper.write_fuse(writer, fuse);

    const high_value = results_high.get(fuse);
    if (default_high) |def| {
        if (high_value != def) {
            try helper.write_value(writer, high_value, "high");
        }
    } else {
        default_high = high_value;
    }

    const low_value = results_low.get(fuse);
    if (default_low) |def| {
        if (low_value != def) {
            try helper.write_value(writer, low_value, "low");
        }
    } else {
        default_low = low_value;
    }
}
