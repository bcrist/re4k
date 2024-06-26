const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const jedec = lc4k.jedec;
const device_info = @import("device_info.zig");
const JedecData = jedec.JedecData;
const FuseRange = jedec.FuseRange;
const DeviceInfo = device_info.DeviceInfo;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const OutputIterator = helper.OutputIterator;
const MacrocellRef = lc4k.MacrocellRef;
const PinInfo = lc4k.PinInfo;

pub fn main() void {
    helper.main();
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, mcref: MacrocellRef, pt4_oe: bool) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    try design.nodeAssignment(.{ .signal = "node0" });
    try design.nodeAssignment(.{ .signal = "node1" });
    try design.nodeAssignment(.{ .signal = "node2" });
    try design.nodeAssignment(.{ .signal = "node3" });
    try design.nodeAssignment(.{ .signal = "node4" });

    var mc_iter = helper.MacrocellIterator { .dev = dev };
    var n: usize = 0;
    while (mc_iter.next()) |other_mcref| {
        if (other_mcref.glb == mcref.glb and other_mcref.mc != mcref.mc) {
            var data_name = try std.fmt.allocPrint(ta, "node{}.D", .{ n });
            const signal_name = data_name[0..data_name.len - 2];
            try design.nodeAssignment(.{
                .signal = signal_name,
                .glb = other_mcref.glb,
                .mc = other_mcref.mc,
            });
            try design.addPT("node0.Q", data_name);
            try design.addPT("node1.Q", data_name);
            try design.addPT("node2.Q", data_name);
            try design.addPT("node3.Q", data_name);
            try design.addPT(.{ "node0.Q", "node1.Q", "node2.Q" }, data_name);
            n += 1;
        }
    }

    try design.pinAssignment(.{
        .signal = "out",
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

    var iter = OutputIterator {
        .pins = dev.all_pins,
        .exclude_glb = mcref.glb,
    };
    n = 0;
    while (iter.next()) |oe_pin| {
        if (dev.device == .LC4064ZC_csBGA56) {
            // These pins are connected to macrocells, but lpf4k thinks they're dedicated inputs, and won't allow them to be used as outputs.
            if (std.mem.eql(u8, oe_pin.id, "F8")) continue;
            if (std.mem.eql(u8, oe_pin.id, "E3")) continue;
        }
        var oe_signal_name = try std.fmt.allocPrint(ta, "temp_{}.OE", .{ n });
        const signal_name = oe_signal_name[0..oe_signal_name.len-3];
        try design.pinAssignment(.{
            .signal = signal_name,
            .pin = oe_pin.id,
        });

        const oe = switch (n % 4) {
            0 => "node0.Q",
            1 => "node1.Q",
            2 => "node2.Q",
            3 => "node3.Q",
            else => unreachable,
        };

        try design.addPT(.{}, signal_name);
        try design.addPT(.{ oe, "node4.Q" }, oe_signal_name);

        n += 1;
    }

    var results = try tc.runToolchain(design);
    try helper.logResults(dev.device, "pt4_oe_glb{}_mc{}_{}", .{ mcref.glb, mcref.mc, pt4_oe }, results);
    try results.checkTerm();
    return results;
}

var default_off: ?usize = null;
var default_on: ?usize = null;

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer) !void {
    var oe_src_rows = try parseOESourceRows(ta, pa, null);

    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("pt4_output_enable");

    var mc_iter = helper.MacrocellIterator { .dev = dev };
    while (mc_iter.next()) |mcref| {
        if (mcref.mc == 0) {
            try helper.writeGlb(writer, mcref.glb);
        }

        try tc.cleanTempDir();
        helper.resetTemp();

        const results_off = try runToolchain(ta, tc, dev, mcref, false);
        const results_on = try runToolchain(ta, tc, dev, mcref, true);

        var diff = try JedecData.initDiff(ta, results_off.jedec, results_on.jedec);

        // ignore differences in PTs and GLB routing
        //diff.putRange(dev.getRoutingRange(), 0);

        // ignore rows that we already know are used for the OE mux in the I/O cell:
        var oe_row_iter = oe_src_rows.iterator(.{});
        while (oe_row_iter.next()) |row| {
            diff.putRange(dev.getRowRange(@intCast(row), @intCast(row)), 0);
        }

        try helper.writeMc(writer, mcref.mc);

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
            try helper.err("Expected one pt4_oe fuse but found {}!", .{ diff.countSet() }, dev, .{ .mcref = mcref });
        }

        if (default_off) |def| {
            if (value_off != def) {
                try helper.writeValue(writer, value_off, "disabled");
            }
        } else {
            default_off = value_off;
        }

        if (default_on) |def| {
            if (value_on != def) {
                try helper.writeValue(writer, value_on, "enabled");
            }
        } else {
            default_on = value_on;
        }

        try writer.close();

        if (mcref.mc == 15) {
            try writer.close(); // glb
        }
    }

    if (default_off) |def| {
        try helper.writeValue(writer, def, "disabled");
    }

    if (default_on) |def| {
        try helper.writeValue(writer, def, "enabled");
    }

    try writer.done();
}


fn parseOESourceRows(ta: std.mem.Allocator, pa: std.mem.Allocator, out_device: ?*DeviceInfo) !std.DynamicBitSet {
    const input_file = helper.getInputFile("oe_source.sx") orelse return error.MissingOESourceInputFile;
    const dev = DeviceInfo.init(input_file.device_type);

    var results = try std.DynamicBitSet.initEmpty(pa, dev.jedec_dimensions.height());

    var stream = std.io.fixedBufferStream(input_file.contents);
    const reader = stream.reader();
    var parser = sx.reader(ta, reader.any());
    defer parser.deinit();

    parseOESourceRows0(&parser, &results) catch |e| switch (e) {
        error.SExpressionSyntaxError => {
            var ctx = try parser.token_context();
            try ctx.print_for_string(input_file.contents, std.io.getStdErr().writer(), 120);
            return e;
        },
        else => return e,
    };

    if (out_device) |ptr| {
        ptr.* = dev;
    }

    return results;
}

fn parseOESourceRows0(parser: *sx.Reader, results: *std.DynamicBitSet) !void {
    _ = try parser.require_any_expression(); // device name, we already know it
    try parser.require_expression("output_enable_source");

    while (try helper.parsePin(parser, null)) {
        while (try parser.expression("fuse")) {
            const row = try parser.require_any_int(u16, 10);
            _ = try parser.require_any_int(u16, 10);

            if (try parser.expression("value")) {
                try parser.ignore_remaining_expression();
            }

            results.set(row);

            try parser.require_close(); // fuse
        }
        try parser.require_close(); // pin
    }
    while (try parser.expression("value")) {
        try parser.ignore_remaining_expression();
    }
    try parser.require_close(); // oe_source
    try parser.require_close(); // device
    try parser.require_done();
}
