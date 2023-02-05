const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const jedec = @import("jedec");
const common = @import("common");
const device_info = @import("device_info.zig");
const DeviceInfo = device_info.DeviceInfo;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JedecData = jedec.JedecData;

pub fn main() void {
    helper.main(0);
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, pin: common.PinInfo, inreg: bool) !toolchain.FitResults {
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
        var signal_name = try std.fmt.allocPrint(ta, "dum{}", .{ mc });
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

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev.device));
    try writer.expressionExpanded("xor");

    var pin_iter = helper.OutputIterator { .pins = dev.all_pins };
    while (pin_iter.next()) |pin| {
        if (dev.device == .LC4064ZC_csBGA56) {
            // These pins are connected to macrocells, but lpf4k thinks they're dedicated inputs, and won't allow them to be used as outputs.
            if (std.mem.eql(u8, pin.id, "F8")) continue;
            if (std.mem.eql(u8, pin.id, "E3")) continue;
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

    // TODO verify that these match the JEDEC data
    try helper.writeValue(writer, 1, "pt0_or_constant");
    try helper.writeValue(writer, 0, "input_buffer");

    try writer.done();

    _ = pa;
}
