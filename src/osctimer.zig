const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const jedec = lc4k.jedec;
const lc4k = @import("lc4k");
const device_info = @import("device_info.zig");
const DeviceInfo = device_info.DeviceInfo;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JedecData = jedec.JedecData;
const Fuse = jedec.Fuse;

pub fn main() void {
    helper.main();
}

const Polarity = enum {
    positive,
    negative,
};

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, osc_out: bool, timer_out: bool, disable: bool, reset: bool, div: lc4k.TimerDivisor, glb: u8) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    if (osc_out or timer_out) {
        try design.oscillator(div);
    }

    var pin_iter = helper.OutputIterator {
        .pins = dev.all_pins,
        .single_glb = glb,
    };

    if (osc_out) {
        try design.pinAssignment(.{
            .signal = "out_osc",
            .pin = pin_iter.next().?.id,
        });
        try design.addPT("OSC_out", "out_osc");
    } else {
        _ = pin_iter.next();
    }

    if (timer_out) {
        try design.pinAssignment(.{
            .signal = "out_timer",
            .pin = pin_iter.next().?.id,
        });
        try design.addPT("OSC_tout", "out_timer");
    } else {
        _ = pin_iter.next();
    }

    if (disable) {
        try design.pinAssignment(.{
            .signal = "in_disable",
            .pin = pin_iter.next().?.id,
        });
        try design.addPT("in_disable", "OSC_disable");
    } else {
        _ = pin_iter.next();
    }

    if (reset) {
        try design.pinAssignment(.{
            .signal = "in_reset",
            .pin = pin_iter.next().?.id,
        });
        try design.addPT("in_reset", "OSC_reset");
    } else {
        _ = pin_iter.next();
    }

    var results = try tc.runToolchain(design);
    try helper.logResults(dev.device, "osctimer_{}_{}_{}_{}_{s}", .{ osc_out, timer_out, disable, reset, @tagName(div) }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer) !void {
    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("osctimer");


    {
        const results_none = try runToolchain(ta, tc, dev, false, false, false, false, .div1048576, 0);
        const results_both = try runToolchain(ta, tc, dev, true, true, false, false, .div1048576, 0);
        const results_osc = try runToolchain(ta, tc, dev, true, false, false, false, .div1048576, 0);
        const results_timer = try runToolchain(ta, tc, dev, false, true, false, false, .div1048576, 0);
        const results_timer1024 = try runToolchain(ta, tc, dev, false, true, false, false, .div1024, 0);

        const results_1_both = try runToolchain(ta, tc, dev, true, true, false, false, .div1048576, 1);
        const results_1_osc = try runToolchain(ta, tc, dev, true, false, false, false, .div1048576, 1);
        const results_1_timer = try runToolchain(ta, tc, dev, false, true, false, false, .div1048576, 1);

        var ignore = try JedecData.initDiff(ta, results_both.jedec, results_1_both.jedec);
        ignore.unionDiff(results_osc.jedec, results_1_osc.jedec);
        ignore.unionDiff(results_timer.jedec, results_1_timer.jedec);

        var diff = try JedecData.initDiff(ta, results_both.jedec, results_osc.jedec);
        diff.unionDiff(results_both.jedec, results_timer.jedec);
        diff.putRange(dev.getRoutingRange(), 0);

        var en_diff = try JedecData.initDiff(ta, results_both.jedec, results_none.jedec);

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
                try helper.writeFuse(writer, fuse);
                try helper.writeValue(writer, both, "enabled");
                try helper.writeValue(writer, none, "disabled");
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
                try helper.writeFuse(writer, fuse);
                try helper.writeValue(writer, results_osc.jedec.get(fuse), "enabled");
                try helper.writeValue(writer, results_timer.jedec.get(fuse), "disabled");
                try writer.close(); // osc_out
            }

            if (results_timer.jedec.get(fuse) == results_both.jedec.get(fuse)) {
                if (found_timer_out) {
                    try helper.err("Expected 1 fuse for timer_out, but found multiple!\n", .{}, dev, .{});
                }
                found_timer_out = true;
                try writer.expression_expanded("timer_out");
                try helper.writeFuse(writer, fuse);
                try helper.writeValue(writer, results_timer.jedec.get(fuse), "enabled");
                try helper.writeValue(writer, results_osc.jedec.get(fuse), "disabled");
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

        const results_div128 = try runToolchain(ta, tc, dev, true, true, false, false, .div128, 0);
        const results_div1024 = try runToolchain(ta, tc, dev, true, true, false, false, .div1024, 0);
        const results_div1048576 = try runToolchain(ta, tc, dev, true, true, false, false, .div1048576, 0);

        var diff = try JedecData.initDiff(ta, results_div128.jedec, results_div1024.jedec);
        diff.unionDiff(results_div128.jedec, results_div1048576.jedec);

        var val128: usize = 0;
        var val1024: usize = 0;
        var val1048576: usize = 0;

        var bit_value: usize = 1;
        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            if (results_div128.jedec.isSet(fuse)) val128 |= bit_value;
            if (results_div1024.jedec.isSet(fuse)) val1024 |= bit_value;
            if (results_div1048576.jedec.isSet(fuse)) val1048576 |= bit_value;
            try helper.writeFuseValue(writer, fuse, bit_value);
            bit_value *= 2;
        }

        if (diff.countSet() != 2) {
            try helper.err("Expected 2 fuses for timer_div options, but found {}!\n", .{ diff.countSet() }, dev, .{});
        }

        try helper.writeValue(writer, val128, "div128");
        try helper.writeValue(writer, val1024, "div1024");
        try helper.writeValue(writer, val1048576, "div1048576");

        try writer.close(); // timer_div
    }

    try writer.close(); // osctimer
    try writer.done();

    _ = pa;
}
