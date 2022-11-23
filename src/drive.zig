const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const core = @import("core.zig");
const devices = @import("devices.zig");
const jedec = @import("jedec.zig");
const DeviceType = @import("devices.zig").DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JedecData = jedec.JedecData;

pub fn main() void {
    helper.main(0);
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
    try helper.logResults("drive_pin_{s}", .{ dev.getPins()[pin_index].pin_number() }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("drive_type");

    var default_pp: ?u1 = null;
    var default_od: ?u1 = null;

    var pin_iter = devices.pins.OutputIterator { .pins = dev.getPins() };
    while (pin_iter.next()) |io| {
        try tc.cleanTempDir();
        helper.resetTemp();

        const results_pp = try runToolchain(ta, tc, dev, io.pin_index, .push_pull);
        const results_od = try runToolchain(ta, tc, dev, io.pin_index, .open_drain);

        try helper.writePin(writer, io);
        // try writer.expression("pin");
        // try writer.string(io.pin_number);

        var diff = try JedecData.initDiff(ta, results_pp.jedec, results_od.jedec);
        var diff_iter = diff.iterator(.{});
        if (diff_iter.next()) |fuse| {
            try helper.writeFuse(writer, fuse);

            const pp_value = results_pp.jedec.get(fuse);
            if (default_pp) |def| {
                if (pp_value != def) {
                    try helper.writeValue(writer, pp_value, "push-pull");
                }
            } else {
                default_pp = pp_value;
            }

            const od_value = results_od.jedec.get(fuse);
            if (default_od) |def| {
                if (od_value != def) {
                    try helper.writeValue(writer, od_value, "open-drain");
                }
            } else {
                default_od = od_value;
            }

        } else {
            try helper.err("Expected one drive fuse but found none!", .{}, dev, .{ .pin_index = io.pin_index });
            return error.Think;
        }

        if (diff_iter.next()) |_| {
            try helper.err("Expected one drive fuse but found multiple!", .{}, dev, .{ .pin_index = io.pin_index });
            return error.Think;
        }

        try writer.close();
    }

    if (default_pp) |def| {
        try helper.writeValue(writer, def, "push-pull");
    }

    if (default_od) |def| {
        try helper.writeValue(writer, def, "open-drain");
    }

    try writer.done();

    _ = pa;
}
