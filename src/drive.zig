const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const common = @import("common");
const device_info = @import("device_info.zig");
const jedec = @import("jedec");
const DeviceInfo = device_info.DeviceInfo;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JedecData = jedec.JedecData;
const OutputIterator = helper.OutputIterator;
const MacrocellRef = common.MacrocellRef;
const PinInfo = common.PinInfo;
const Fuse = jedec.Fuse;
const DriveType = common.DriveType;

pub fn main() void {
    helper.main();
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, pin: PinInfo, drive: DriveType) !toolchain.FitResults {
    var design = Design.init(ta, dev);
    try design.pinAssignment(.{
        .signal = "out",
        .pin = pin.id,
        .drive = drive,
    });
    try design.addPT("in", "out");

    var results = try tc.runToolchain(design);
    try helper.logResults(dev.device, "drive_pin_{s}", .{ pin.id }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer(std.fs.File.Writer)) !void {
    var maybe_fallback_fuses: ?std.AutoHashMap(MacrocellRef, []const helper.FuseAndValue) = null;
    if (helper.getInputFile("drive.sx")) |_| {
        maybe_fallback_fuses = try helper.parseFusesForOutputPins(ta, pa, "drive.sx", "drive_type", null);
    }

    try writer.expressionExpanded(@tagName(dev.device));
    try writer.expressionExpanded("drive_type");

    var default_pp: ?u1 = null;
    var default_od: ?u1 = null;

    var pin_iter = OutputIterator { .pins = dev.all_pins };
    while (pin_iter.next()) |pin| {
        if (maybe_fallback_fuses) |fallback_fuses| {
            if (std.mem.eql(u8, pin.id, "F8") or std.mem.eql(u8, pin.id, "E3")) {
                // These pins are connected to macrocells, but lpf4k thinks they're dedicated inputs, and won't allow them to be used as outputs.
                const mcref = MacrocellRef.init(pin.glb.?, switch (pin.func) {
                    .io, .io_oe0, .io_oe1 => |mc| mc,
                    else => unreachable,
                });

                if (fallback_fuses.get(mcref)) |fuses| {
                    try helper.writePin(writer, pin);
                    for (fuses) |fuse_and_value| {
                        try helper.writeFuseOptValue(writer, fuse_and_value.fuse, fuse_and_value.value);
                    }
                    try writer.close();
                    continue;
                }
            }
        }

        try tc.cleanTempDir();
        helper.resetTemp();

        const results_pp = try runToolchain(ta, tc, dev, pin, .push_pull);
        const results_od = try runToolchain(ta, tc, dev, pin, .open_drain);

        try helper.writePin(writer, pin);

        var diff = try JedecData.initDiff(ta, results_pp.jedec, results_od.jedec);
        var diff_iter = diff.iterator(.{});
        if (diff_iter.next()) |fuse| {
            try helper.writeFuse(writer, fuse);

            const pp_value = results_pp.jedec.get(fuse);
            if (default_pp) |def| {
                if (pp_value != def) {
                    try helper.writeValue(writer, pp_value, "push_pull");
                }
            } else {
                default_pp = pp_value;
            }

            const od_value = results_od.jedec.get(fuse);
            if (default_od) |def| {
                if (od_value != def) {
                    try helper.writeValue(writer, od_value, "open_drain");
                }
            } else {
                default_od = od_value;
            }

        } else {
            try helper.err("Expected one drive fuse but found none!", .{}, dev, .{ .pin = pin.id });
            return error.Think;
        }

        if (diff_iter.next()) |_| {
            try helper.err("Expected one drive fuse but found multiple!", .{}, dev, .{ .pin = pin.id });
            return error.Think;
        }

        try writer.close();
    }

    if (default_pp) |def| {
        try helper.writeValue(writer, def, "push_pull");
    }

    if (default_od) |def| {
        try helper.writeValue(writer, def, "open_drain");
    }

    try writer.done();
}
