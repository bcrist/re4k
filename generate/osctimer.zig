const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const Device_Info = @import("Device_Info.zig");
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JEDEC_Data = lc4k.JEDEC_Data;
const Fuse = lc4k.Fuse;

pub const main = helper.main;

const Polarity = enum {
    positive,
    negative,
};

fn run_toolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, osc_out: bool, timer_out: bool, disable: bool, reset: bool, div: lc4k.Timer_Divisor, glb: u8) !toolchain.Fit_Results {
    var design = Design.init(ta, dev);

    if (osc_out or timer_out) {
        try design.oscillator(div);
    }

    var pin_iter = helper.Output_Iterator {
        .pins = dev.all_pins,
        .single_glb = glb,
    };

    if (osc_out) {
        try design.pin_assignment(.{
            .signal = "out_osc",
            .pin = pin_iter.next().?.id,
        });
        try design.add_pt("OSC_out", "out_osc");
    } else {
        _ = pin_iter.next();
    }

    if (timer_out) {
        try design.pin_assignment(.{
            .signal = "out_timer",
            .pin = pin_iter.next().?.id,
        });
        try design.add_pt("OSC_tout", "out_timer");
    } else {
        _ = pin_iter.next();
    }

    if (disable) {
        try design.pin_assignment(.{
            .signal = "in_disable",
            .pin = pin_iter.next().?.id,
        });
        try design.add_pt("in_disable", "OSC_disable");
    } else {
        _ = pin_iter.next();
    }

    if (reset) {
        try design.pin_assignment(.{
            .signal = "in_reset",
            .pin = pin_iter.next().?.id,
        });
        try design.add_pt("in_reset", "OSC_reset");
    } else {
        _ = pin_iter.next();
    }

    var results = try tc.run_toolchain(design);
    try helper.log_results(dev.device, "osctimer_{}_{}_{}_{}_{s}", .{ osc_out, timer_out, disable, reset, @tagName(div) }, results);
    try results.check_term();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("osctimer");


    {
        const results_none = try run_toolchain(ta, tc, dev, false, false, false, false, .div_1048576, 0);
        const results_both = try run_toolchain(ta, tc, dev, true, true, false, false, .div_1048576, 0);
        const results_osc = try run_toolchain(ta, tc, dev, true, false, false, false, .div_1048576, 0);
        const results_timer = try run_toolchain(ta, tc, dev, false, true, false, false, .div_1048576, 0);
        const results_timer1024 = try run_toolchain(ta, tc, dev, false, true, false, false, .div_1024, 0);

        const results_1_both = try run_toolchain(ta, tc, dev, true, true, false, false, .div_1048576, 1);
        const results_1_osc = try run_toolchain(ta, tc, dev, true, false, false, false, .div_1048576, 1);
        const results_1_timer = try run_toolchain(ta, tc, dev, false, true, false, false, .div_1048576, 1);

        var ignore = try JEDEC_Data.init_diff(ta, results_both.jedec, results_1_both.jedec);
        ignore.union_diff(results_osc.jedec, results_1_osc.jedec);
        ignore.union_diff(results_timer.jedec, results_1_timer.jedec);

        var diff = try JEDEC_Data.init_diff(ta, results_both.jedec, results_osc.jedec);
        diff.union_diff(results_both.jedec, results_timer.jedec);
        diff.put_range(dev.get_routing_range(), 0);

        var en_diff = try JEDEC_Data.init_diff(ta, results_both.jedec, results_none.jedec);

        var ignore_iter = ignore.iterator(.{});
        while (ignore_iter.next()) |fuse| {
            diff.put(fuse, 0);
            en_diff.put(fuse, 0);
        }

        var en_diff_iter = en_diff.iterator(.{});
        while (en_diff_iter.next()) |fuse| {
            const osc = results_osc.jedec.get(fuse);
            const timer = results_timer1024.jedec.get(fuse);
            const both = results_both.jedec.get(fuse);
            const none = results_none.jedec.get(fuse);
            if (osc == timer and osc == both and both != none) {
                try writer.expression_expanded("enable");
                try helper.write_fuse(writer, fuse);
                try helper.write_value(writer, both, "enabled");
                try helper.write_value(writer, none, "disabled");
                try writer.close(); // enable
            }
        }

        var found_osc_out = false;
        var found_timer_out = false;
        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            if (results_osc.jedec.get(fuse) == results_both.jedec.get(fuse)) {
                if (found_osc_out) {
                    try helper.err("Expected 1 fuse for osc_out, but found multiple!\n", .{}, dev, .{});
                }
                found_osc_out = true;
                try writer.expression_expanded("osc_out");
                try helper.write_fuse(writer, fuse);
                try helper.write_value(writer, results_osc.jedec.get(fuse), "enabled");
                try helper.write_value(writer, results_timer.jedec.get(fuse), "disabled");
                try writer.close(); // osc_out
            }

            if (results_timer.jedec.get(fuse) == results_both.jedec.get(fuse)) {
                if (found_timer_out) {
                    try helper.err("Expected 1 fuse for timer_out, but found multiple!\n", .{}, dev, .{});
                }
                found_timer_out = true;
                try writer.expression_expanded("timer_out");
                try helper.write_fuse(writer, fuse);
                try helper.write_value(writer, results_timer.jedec.get(fuse), "enabled");
                try helper.write_value(writer, results_osc.jedec.get(fuse), "disabled");
                try writer.close(); // timer_out
            }
        }

        if (!found_osc_out) {
            try helper.err("Expected 1 fuse for osc_out, but found none!\n", .{}, dev, .{});
        }
        if (!found_timer_out) {
            try helper.err("Expected 1 fuse for timer_out, but found none!\n", .{}, dev, .{});
        }
    }

    {
        try writer.expression_expanded("timer_div");

        const results_div128 = try run_toolchain(ta, tc, dev, true, true, false, false, .div_128, 0);
        const results_div1024 = try run_toolchain(ta, tc, dev, true, true, false, false, .div_1024, 0);
        const results_div1048576 = try run_toolchain(ta, tc, dev, true, true, false, false, .div_1048576, 0);

        var diff = try JEDEC_Data.init_diff(ta, results_div128.jedec, results_div1024.jedec);
        diff.union_diff(results_div128.jedec, results_div1048576.jedec);

        var val128: usize = 0;
        var val1024: usize = 0;
        var val1048576: usize = 0;

        var bit_value: usize = 1;
        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            if (results_div128.jedec.is_set(fuse)) val128 |= bit_value;
            if (results_div1024.jedec.is_set(fuse)) val1024 |= bit_value;
            if (results_div1048576.jedec.is_set(fuse)) val1048576 |= bit_value;
            try helper.write_fuse_value(writer, fuse, bit_value);
            bit_value *= 2;
        }

        if (diff.count_set() != 2) {
            try helper.err("Expected 2 fuses for timer_div options, but found {}!\n", .{ diff.count_set() }, dev, .{});
        }

        try helper.write_value(writer, val128, "div128");
        try helper.write_value(writer, val1024, "div1024");
        try helper.write_value(writer, val1048576, "div1048576");

        try writer.close(); // timer_div
    }

    try writer.close(); // osctimer
    try writer.done();

    _ = pa;
}
