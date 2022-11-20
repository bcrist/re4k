const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const core = @import("core.zig");
const jedec = @import("jedec.zig");
const devices = @import("devices.zig");
const JedecData = jedec.JedecData;
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const Fuse = jedec.Fuse;
const GlbInputSignal = toolchain.GlbInputSignal;

pub fn main() void {
    helper.main(1);
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, mcref: core.MacrocellRef) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    // Coercing the fitter to reliably place specific signals on the block init and block OE pterms is difficult.
    // Furthermore, it likes to place regular logic terms in different macrocells and then redirect it in, unless
    // the previous MC is using logic pterms from its own allocator, so forcing it to use PT0 is also difficult.
    //
    // So we're only going to try routing signals to PT1 (clock) and PT2 (clock enable).  These only compete
    // with the block clock pterm, but it's pretty easy to convince the fitter to allocate that for other stuff.
    //
    // Once we have the columns for PT1 and PT2, we can extrapolate the other 3, based on the assumption that they're
    // always laid out consecutively (which is true for the devices I've tested manually).

    var scratch_glb: u8 = if (mcref.glb == 0) 1 else 0;

    try design.pinAssignment(.{
        .signal = "x0",
        .pin_index = dev.getClockPin(0).?.pin_index,
    });
    try design.pinAssignment(.{
        .signal = "pt2",
        .pin_index = dev.getClockPin(2).?.pin_index,
    });
    try design.pinAssignment(.{
        .signal = "pt1",
        .pin_index = (devices.pins.OutputIterator {
            .pins = dev.getPins(),
            .single_glb = scratch_glb,
        }).next().?.pin_index,
    });

    var n: u8 = 0;
    while (n < 4) : (n += 1) {
        var signal_name = try std.fmt.allocPrint(ta, "dum{}", .{ n });
        var d_name = try std.fmt.allocPrint(ta, "dum{}.D", .{ n });
        var c_name = try std.fmt.allocPrint(ta, "dum{}.C", .{ n });
        var ar_name = try std.fmt.allocPrint(ta, "dum{}.AR", .{ n });
        try design.nodeAssignment(.{
            .signal = signal_name,
            .glb = mcref.glb,
            .powerup_state = 0,
        });
        try design.addPT(.{}, d_name);
        try design.addPT(.{ "x0", "pt1" }, ar_name);
        try design.addPT(.{ "x0", "pt2" }, c_name);
    }

    try design.nodeAssignment(.{
        .signal = "out",
        .glb = mcref.glb,
        .mc = mcref.mc,
        .powerup_state = 0,
    });
    try design.addPT(.{}, "out.D");
    try design.addPT("pt1", "out.C");
    try design.addPT("pt2", "out.CE");

    var results = try tc.runToolchain(design);
    try helper.logReport("pterms_glb{}_mc{}", .{ mcref.glb, mcref.mc }, results);
    try results.checkTerm();
    return results;
}

const RoutingType = enum {
    none,
    unknown,
    x0,
    pt1,
    pt2,
    block_clk,
    block_init,
};

fn parseJedecColumn(jed: JedecData, column: u16, device: DeviceType, glb: u8, gi_routing: std.AutoHashMap(Fuse, GlbInputSignal)) !RoutingType {
    var routing = RoutingType.none;

    var row: u8 = 0;
    while (row < 72) : (row += 1) {
        if (jed.isSet(Fuse.init(row, column))) {
            continue;
        }

        var gi = row / 2;

        var gi_signal: ?GlbInputSignal = null;
        var fuse_iter = device.getGIRange(glb, gi).iterator();
        var found_gi_fuse = false;
        while (fuse_iter.next()) |fuse| {
            if (!jed.isSet(fuse)) {
                found_gi_fuse = true;
                if (gi_routing.get(fuse)) |signal| {
                    gi_signal = signal;
                }
            }
        }

        if ((row & 1) == 1 and jed.isSet(Fuse.init(row - 1, column))) {
            try helper.err("Expected PT fuses on even rows only, buf found fuse {}:{} {any}!", .{ row, column, gi_signal }, device, .{});
        }

        if (gi_signal) |signal| {
            switch (signal) {
                .pin => |pin_index| {
                    switch (device.getPins()[pin_index]) {
                        .clock_input => |clock_info| {
                            switch (clock_info.clock_index) {
                                0 => {
                                    routing = switch (routing) {
                                        .none => .x0,
                                        .pt1 => .block_init,
                                        .pt2 => .block_clk,
                                        else => .unknown,
                                    };
                                },
                                2 => {
                                    routing = switch (routing) {
                                        .none => .pt2,
                                        .x0 => .block_clk,
                                        else => .unknown,
                                    };
                                },
                                else => {
                                    routing = .unknown;
                                }
                            }
                        },
                        else => {
                            routing = switch (routing) {
                                .none => .pt1,
                                .x0 => .block_init,
                                else => .unknown,
                            };
                        }
                    }
                },
                .fb => {
                    routing = .unknown;
                },
            }
        } else if (found_gi_fuse) {
            routing = .unknown;
        } else {
            return .none;
        }
    }
    return routing;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    var gi_routing = try helper.parseGRP(ta, pa, null);

    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("product_terms");

    var assigned_columns = try std.DynamicBitSet.initEmpty(pa, dev.getJedecWidth());

    var gi: u8 = 0;
    while (gi < 36) : (gi += 1) {
        try writer.expression("gi");
        try writer.printRaw("{}", .{ gi });
        try writer.expression("row");
        try writer.printRaw("{} non-inverted", .{ gi * 2 });
        try writer.close(); // row
        try writer.expression("row");
        try writer.printRaw("{} inverted", .{ gi * 2 + 1 });
        try writer.close(); // row
        try writer.close(); // gi
    }

    var mc_iter = core.MacrocellIterator { .device = dev };
    while (mc_iter.next()) |mcref| {
        try tc.cleanTempDir();
        helper.resetTemp();

        if (mcref.mc == 0) {
            try writer.expression("glb");
            try writer.printRaw("{}", .{ mcref.glb });
            try writer.expression("name");
            try writer.printRaw("{s}", .{ devices.getGlbName(mcref.glb) });
            try writer.close();
            writer.setCompact(false);
        }

        try writer.expression("mc");
        try writer.printRaw("{}", .{ mcref.mc });
        writer.setCompact(false);

        var results = try runToolchain(ta, tc, dev, mcref);

        results.jedec.putRange(dev.getOptionsRange(), 1);

        var columns = try std.DynamicBitSet.initEmpty(ta, dev.getJedecWidth());

        var fuse_iter = results.jedec.iterator(.{ .kind = .unset });
        while (fuse_iter.next()) |fuse| {
            columns.set(fuse.col);
        }

        {
            var glb: u8 = 0;
            while (glb < dev.getNumGlbs()) : (glb += 1) {
                var iter = dev.getGIRange(glb, 0).iterator();
                while (iter.next()) |fuse| {
                    columns.unset(fuse.col);
                }
            }
        }

        var column_routing = std.EnumMap(RoutingType, u16) {};

        var col_iter = columns.iterator(.{});
        while (col_iter.next()) |column| {
            column_routing.put(try parseJedecColumn(results.jedec, @intCast(u16, column), dev, mcref.glb, gi_routing), @intCast(u16, column));
        }

        var pt1 = column_routing.get(.pt1) orelse return error.PT1NotFound;
        var pt2 = column_routing.get(.pt2) orelse return error.PT2NotFound;

        var dc = @as(i32, pt2) - pt1;
        if (dc != 1 and dc != -1) {
            try helper.err("Expected PT1 and PT2 columns to be adjacent, but found {} and {}", .{ pt1, pt2 }, dev, .{ .mcref = mcref });
        }

        var pt0 = @intCast(u16, pt1 - dc);
        var pt3 = @intCast(u16, pt2 + dc);
        var pt4 = @intCast(u16, pt3 + dc);

        if (assigned_columns.isSet(pt0)) {
            try helper.err("Column {} assigned to multiple functions!", .{ pt0 }, dev, .{ .mcref = mcref });
        } else {
            assigned_columns.set(pt0);
        }
        if (assigned_columns.isSet(pt1)) {
            try helper.err("Column {} assigned to multiple functions!", .{ pt1 }, dev, .{ .mcref = mcref });
        } else {
            assigned_columns.set(pt1);
        }
        if (assigned_columns.isSet(pt2)) {
            try helper.err("Column {} assigned to multiple functions!", .{ pt2 }, dev, .{ .mcref = mcref });
        } else {
            assigned_columns.set(pt2);
        }
        if (assigned_columns.isSet(pt3)) {
            try helper.err("Column {} assigned to multiple functions!", .{ pt3 }, dev, .{ .mcref = mcref });
        } else {
            assigned_columns.set(pt3);
        }
        if (assigned_columns.isSet(pt4)) {
            try helper.err("Column {} assigned to multiple functions!", .{ pt4 }, dev, .{ .mcref = mcref });
        } else {
            assigned_columns.set(pt4);
        }

        try writer.expression("column");
        try writer.printRaw("{} pt0", .{ pt1 - dc });
        try writer.close();
        try writer.expression("column");
        try writer.printRaw("{} pt1", .{ pt1 });
        try writer.close();
        try writer.expression("column");
        try writer.printRaw("{} pt2", .{ pt2 });
        try writer.close();
        try writer.expression("column");
        try writer.printRaw("{} pt3", .{ pt2 + dc });
        try writer.close();
        try writer.expression("column");
        try writer.printRaw("{} pt4", .{ pt2 + dc + dc });
        try writer.close();

        try writer.close(); // mc

        if (mcref.mc == 15) {
            var binit = column_routing.get(.block_init) orelse return error.BlockInitNotFound;
            var bclk = column_routing.get(.block_clk) orelse return error.BlockClkNotFound;

            try writer.expression("column");
            try writer.printRaw("{} \"Shared PT Init\"", .{ binit });
            try writer.close();

            try writer.expression("column");
            try writer.printRaw("{} \"Shared PT Clock\"", .{ bclk });
            try writer.close();

            var boe = bclk + bclk - binit;

            try writer.expression("column");
            if (dev.getFamily() == .zero_power_enhanced) {
                try writer.printRaw("{} \"Shared PT OE / BIE\"", .{ boe });
            } else {
                try writer.printRaw("{} \"Shared PT OE\"", .{ boe });
            }
            try writer.close();

            if (assigned_columns.isSet(binit)) {
                try helper.err("Column {} assigned to multiple functions!", .{ binit }, dev, .{ .glb = mcref.glb });
            } else {
                assigned_columns.set(binit);
            }
            if (assigned_columns.isSet(bclk)) {
                try helper.err("Column {} assigned to multiple functions!", .{ bclk }, dev, .{ .glb = mcref.glb });
            } else {
                assigned_columns.set(bclk);
            }
            if (assigned_columns.isSet(boe)) {
                try helper.err("Column {} assigned to multiple functions!", .{ boe }, dev, .{ .glb = mcref.glb });
            } else {
                assigned_columns.set(boe);
            }

            try writer.close();
        }
    }


    try writer.done();
}
