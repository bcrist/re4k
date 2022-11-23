const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const jedec = @import("jedec.zig");
const core = @import("core.zig");
const devices = @import("devices.zig");
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JedecData = jedec.JedecData;
const Fuse = jedec.Fuse;

pub fn main() void {
    helper.main(0);
}

const Polarity = enum {
    positive,
    negative,
};

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, osc_out: bool, timer_out: bool, disable: bool, reset: bool, div: core.TimerDivisor, glb: u8) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    if (osc_out or timer_out) {
        try design.oscillator(div);
    }

    var pin_iter = devices.pins.OutputIterator {
        .pins = dev.getPins(),
        .single_glb = glb,
    };

    if (osc_out) {
        try design.pinAssignment(.{
            .signal = "out_osc",
            .pin_index = pin_iter.next().?.pin_index,
        });
        try design.addPT("OSC_out", "out_osc");
    } else {
        _ = pin_iter.next();
    }

    if (timer_out) {
        try design.pinAssignment(.{
            .signal = "out_timer",
            .pin_index = pin_iter.next().?.pin_index,
        });
        try design.addPT("OSC_tout", "out_timer");
    } else {
        _ = pin_iter.next();
    }

    if (disable) {
        try design.pinAssignment(.{
            .signal = "in_disable",
            .pin_index = pin_iter.next().?.pin_index,
        });
        try design.addPT("in_disable", "OSC_disable");
    } else {
        _ = pin_iter.next();
    }

    if (reset) {
        try design.pinAssignment(.{
            .signal = "in_reset",
            .pin_index = pin_iter.next().?.pin_index,
        });
        try design.addPT("in_reset", "OSC_reset");
    } else {
        _ = pin_iter.next();
    }

    var results = try tc.runToolchain(design);
    try helper.logResults("osctimer_{}_{}_{}_{}_{s}", .{ osc_out, timer_out, disable, reset, @tagName(div) }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("osctimer");


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
                try writer.expressionExpanded("enable");
                try helper.writeFuse(writer, fuse);

                try writer.expression("value");
                try writer.printRaw("{} enabled", .{ both });
                try writer.close();

                try writer.expression("value");
                try writer.printRaw("{} disabled", .{ none });
                try writer.close();

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
                try writer.expressionExpanded("osc_out");
                try helper.writeFuse(writer, fuse);

                try writer.expression("value");
                try writer.printRaw("{} enabled", .{ results_osc.jedec.get(fuse) });
                try writer.close();

                try writer.expression("value");
                try writer.printRaw("{} disabled", .{ 1 ^ results_osc.jedec.get(fuse) });
                try writer.close();

                try writer.close(); // osc_out
            }

            if (results_timer.jedec.get(fuse) == results_both.jedec.get(fuse)) {
                if (found_timer_out) {
                    try helper.err("Expected 1 fuse for timer_out, but found multiple!\n", .{}, dev, .{});
                }
                found_timer_out = true;
                try writer.expressionExpanded("timer_out");
                try helper.writeFuse(writer, fuse);

                try writer.expression("value");
                try writer.printRaw("{} enabled", .{ results_timer.jedec.get(fuse) });
                try writer.close();

                try writer.expression("value");
                try writer.printRaw("{} disabled", .{ 1 ^ results_timer.jedec.get(fuse) });
                try writer.close();

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
        try writer.expressionExpanded("timer_div");

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

        try writer.expression("value");
        try writer.printRaw("{} div128", .{ val128 });
        try writer.close();

        try writer.expression("value");
        try writer.printRaw("{} div1024", .{ val1024 });
        try writer.close();

        try writer.expression("value");
        try writer.printRaw("{} div1048576", .{ val1048576 });
        try writer.close();

        try writer.close(); // timer_div
    }

    try writer.close(); // osctimer
    try writer.done();

    _ = pa;
}
