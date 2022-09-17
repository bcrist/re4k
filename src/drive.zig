const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx.zig");
const core = @import("core.zig");
const DeviceType = @import("devices/devices.zig").DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

pub fn main() void {
    helper.main();
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, pin_index: u16, drive: core.DriveType) !toolchain.FitResults {
    var design = Design.init(ta, dev);
    try design.pinAssignment(.{
        .signal = "out",
        .pin_index = pin_index,
        .drive = drive,
    });
    try design.addPT("in", "out");

    var results = try tc.runToolchain(design);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("drive_type");

    var default_pp: ?u1 = null;
    var default_od: ?u1 = null;

    var pin_index: u16 = 0;
    while (pin_index < dev.getNumPins()) : (pin_index += 1) {
        const pin_info = dev.getPins()[pin_index];
        std.debug.assert(pin_index == pin_info.pin_index());
        switch (pin_info) {
            .input_output => {},
            else => continue,
        }
        const pin_number = pin_info.pin_number();

        try tc.cleanTempDir();
        helper.resetTemp();

        const results_pp = try runToolchain(ta, tc, dev, pin_index, .push_pull);
        const results_od = try runToolchain(ta, tc, dev, pin_index, .open_drain);

        var diff = try results_pp.jedec.clone(ta);
        try diff.xor(results_od.jedec);

        try writer.expression("pin");
        try writer.printRaw("{s}", .{ pin_number });

        var diff_iter = diff.raw.iterator(.{});
        if (diff_iter.next()) |fuse| {
            const row = diff.getRow(@intCast(u32, fuse));
            const col = diff.getColumn(@intCast(u32, fuse));

            try writer.expression("fuse");
            try writer.printRaw("{}", .{ row });
            try writer.printRaw("{}", .{ col });

            const pp_value = results_pp.jedec.get(row, col);
            if (default_pp) |def| {
                if (pp_value != def) {
                    try writer.expression("value");
                    try writer.printRaw("{} push-pull", .{ pp_value });
                    try writer.close();
                }
            } else {
                default_pp = pp_value;
            }

            const od_value = results_od.jedec.get(row, col);
            if (default_od) |def| {
                if (od_value != def) {
                    try writer.expression("value");
                    try writer.printRaw("{} open-drain", .{ od_value });
                    try writer.close();
                }
            } else {
                default_od = od_value;
            }

            try writer.close();

        } else {
            try std.io.getStdErr().writer().print("Expected one drive fuse for device {} pin {s} but found none!\n", .{ dev, pin_number });
            return error.Think;
        }

        if (diff_iter.next()) |_| {
            try std.io.getStdErr().writer().print("Expected one drive fuse for device {} pin {s} but found multiple!\n", .{ dev, pin_number });
            return error.Think;
        }

        try writer.close();
    }

    if (default_pp) |def| {
        try writer.expression("value");
        try writer.printRaw("{} push-pull", .{ def });
        try writer.close();
    }

    if (default_od) |def| {
        try writer.expression("value");
        try writer.printRaw("{} open-drain", .{ def });
        try writer.close();
    }

    try writer.done();

    _ = pa;
}
