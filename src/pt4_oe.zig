const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const core = @import("core.zig");
const jedec = @import("jedec.zig");
const devices = @import("devices.zig");
const JedecData = jedec.JedecData;
const FuseRange = jedec.FuseRange;
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

pub fn main() void {
    helper.main(1);
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, pin: devices.pins.InputOutputPinInfo, pt4_oe: bool) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    try design.nodeAssignment(.{ .signal = "node0" });
    try design.nodeAssignment(.{ .signal = "node1" });
    try design.nodeAssignment(.{ .signal = "node2" });
    try design.nodeAssignment(.{ .signal = "node3" });
    try design.nodeAssignment(.{ .signal = "node4" });

    var mc_iter = core.MacrocellIterator { .device = dev };
    var n: usize = 0;
    while (mc_iter.next()) |mcref| {
        if (mcref.glb == pin.glb and mcref.mc != pin.mc) {
            var data_name = try std.fmt.allocPrint(ta, "node{}.D", .{ n });
            var signal_name = data_name[0..data_name.len - 2];
            try design.nodeAssignment(.{
                .signal = signal_name,
                .glb = mcref.glb,
                .mc = mcref.mc,
            });
            try design.addPT("node0.Q", data_name);
            try design.addPT("node1.Q", data_name);
            try design.addPT("node2.Q", data_name);
            try design.addPT("node3.Q", data_name);
            try design.addPT("node4.Q", data_name);
            n += 1;
        }
    }

    try design.pinAssignment(.{
        .signal = "out",
        .pin_index = pin.pin_index,
    });
    try design.addPT("node0.Q", "out");
    try design.addPT("node1.Q", "out");
    try design.addPT("node2.Q", "out");
    try design.addPT("node3.Q", "out");
    if (pt4_oe) {
        try design.addPT(.{ "node0.Q", "node1.Q", "node2.Q" }, "out.OE");
    } else {
        try design.addPT(.{ "node0.Q", "node1.Q", "node2.Q" }, "out");
    }

    var iter = devices.pins.OutputIterator {
        .pins = dev.getPins(),
        .exclude_glb = pin.glb,
    };
    n = 0;
    while (iter.next()) |io| {
        var oe_signal_name = try std.fmt.allocPrint(ta, "temp_{}.OE", .{ n });
        var signal_name = oe_signal_name[0..oe_signal_name.len-3];
        try design.pinAssignment(.{
            .signal = signal_name,
            .pin_index = io.pin_index,
        });

        const goe = switch (n % 4) {
            0 => "node0.Q",
            1 => "node1.Q",
            2 => "node2.Q",
            3 => "node3.Q",
            else => unreachable,
        };

        try design.addPT(.{}, signal_name);
        try design.addPT(.{ goe, "node4.Q" }, oe_signal_name);

        n += 1;
    }

    var results = try tc.runToolchain(design);
    try helper.logResults("pt4_oe_{s}_glb{}_mc{}_{}", .{ pin.pin_number, pin.glb, pin.mc, pt4_oe }, results);
    try results.checkTerm();
    return results;
}

var default_off: ?usize = null;
var default_on: ?usize = null;

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    var oe_mux_rows = try helper.parseOEMuxRows(ta, pa, null);

    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("pt4_oe");

    var iter = devices.pins.OutputIterator {
        .pins = dev.getPins(),
    };
    while (iter.next()) |io| {
        try tc.cleanTempDir();
        helper.resetTemp();

        const results_off = try runToolchain(ta, tc, dev, io, false);
        const results_on = try runToolchain(ta, tc, dev, io, true);

        var diff = try JedecData.initDiff(ta, results_off.jedec, results_on.jedec);

        // ignore differences in PTs and GLB routing
        diff.putRange(dev.getRoutingRange(), 0);

        // ignore rows that we already know are used for the OE mux in the I/O cell:
        var oe_row_iter = oe_mux_rows.iterator(.{});
        while (oe_row_iter.next()) |row| {
            diff.putRange(dev.getRowRange(@intCast(u16, row), @intCast(u16, row)), 0);
        }

        try writer.expression("pin");
        try writer.printRaw("{s}", .{ io.pin_number });

        var value_off: usize = 0;
        var value_on: usize = 0;

        var bit_value: usize = 1;
        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            try helper.writeFuseOptValue(writer, fuse, bit_value);

            if (results_off.jedec.isSet(fuse)) {
                value_off |= bit_value;
            }
            if (results_on.jedec.isSet(fuse)) {
                value_on |= bit_value;
            }

            bit_value *= 2;
        }

        if (diff.countSet() != 1) {
            try helper.err("Expected one pt4_oe fuse but found {}!", .{ diff.countSet() }, dev, .{ .pin_index = io.pin_index });
        }

        if (default_off) |def| {
            if (value_off != def) {
                try writer.expression("value");
                try writer.printRaw("{} disabled", .{ value_off });
                try writer.close();
            }
        } else {
            default_off = value_off;
        }

        if (default_on) |def| {
            if (value_on != def) {
                try writer.expression("value");
                try writer.printRaw("{} enabled", .{ value_on });
                try writer.close();
            }
        } else {
            default_on = value_on;
        }

        try writer.close();
    }

    if (default_off) |def| {
        try writer.expression("value");
        try writer.printRaw("{} disabled", .{ def });
        try writer.close();
    }

    if (default_on) |def| {
        try writer.expression("value");
        try writer.printRaw("{} enabled", .{ def });
        try writer.close();
    }

    try writer.done();
}
