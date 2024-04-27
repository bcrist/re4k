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
const MacrocellRef = lc4k.MacrocellRef;

pub fn main() void {
    helper.main();
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, pin: lc4k.PinInfo, inreg: bool) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    try design.pinAssignment(.{
        .signal = "x0",
    });
    try design.pinAssignment(.{
        .signal = "x1",
    });
    try design.pinAssignment(.{
        .signal = "x2",
    });
    try design.pinAssignment(.{
        .signal = "x3",
    });
    try design.pinAssignment(.{
        .signal = "x4",
    });

    var mc: u8 = 0;
    while (mc < pin.mcRef().?.mc) : (mc += 1) {
        const signal_name = try std.fmt.allocPrint(ta, "dum{}", .{ mc });
        try design.nodeAssignment(.{
            .signal = signal_name,
            .glb = pin.glb.?,
            .mc = mc,
        });
        try design.addPT("x0", signal_name);
        try design.addPT("x1", signal_name);
        try design.addPT("x2", signal_name);
        try design.addPT("x3", signal_name);
        try design.addPT("x4", signal_name);
    }

    try design.pinAssignment(.{
        .signal = "in",
        .pin = pin.id,
    });
    try design.nodeAssignment(.{
        .signal = "out",
        .glb = pin.glb.?,
        .mc = pin.mcRef().?.mc,
        .input_register = inreg,
    });
    try design.addPT("in", "out.D");

    var results = try tc.runToolchain(design);
    try helper.logResults(dev.device, "input_reg_pin_{s}_{}", .{ pin.id, inreg }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer) !void {
    var maybe_fallback_fuses: ?std.AutoHashMap(MacrocellRef, []const helper.FuseAndValue) = null;
    if (helper.getInputFile("input_bypass.sx")) |_| {
        maybe_fallback_fuses = try helper.parseFusesForOutputPins(ta, pa, "input_bypass.sx", "macrocell_data", null);
    }

    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("macrocell_data");

    var pin_iter = helper.OutputIterator { .pins = dev.all_pins };
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

        const results_none = try runToolchain(ta, tc, dev, pin, false);
        const results_inreg = try runToolchain(ta, tc, dev, pin, true);

        var diff = try JedecData.initDiff(ta, results_none.jedec, results_inreg.jedec);

        diff.putRange(dev.getRoutingRange(), 0);

        try helper.writePin(writer, pin);

        var n_fuses: usize = 0;

        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            if (results_none.jedec.isSet(fuse)) {
                try helper.writeFuse(writer, fuse);
                n_fuses += 1;
            }
        }

        if (n_fuses != 1) {
            try helper.err("Expected one input register fuse but found {}!", .{ n_fuses }, dev, .{ .pin = pin.id });
        }

        try writer.close();
    }

    try helper.writeValue(writer, 1, "normal");
    try helper.writeValue(writer, 0, "input_bypass");

    try writer.done();
}
