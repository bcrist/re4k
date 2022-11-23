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

pub fn main() void {
    helper.main(0);
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, pin_index: u16, inreg: bool) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    var io = dev.getPins()[pin_index].input_output;

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
    while (mc < io.mc) : (mc += 1) {
        var signal_name = try std.fmt.allocPrint(ta, "dum{}", .{ mc });
        try design.nodeAssignment(.{
            .signal = signal_name,
            .glb = io.glb,
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
        .pin_index = pin_index,
    });
    try design.nodeAssignment(.{
        .signal = "out",
        .glb = io.glb,
        .mc = io.mc,
        .input_register = inreg,
    });
    try design.addPT("in", "out.D");

    var results = try tc.runToolchain(design);
    try helper.logResults("input_reg_pin_{s}_{}", .{ io.pin_number, inreg }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("input_registers");

    var pin_iter = devices.pins.OutputIterator { .pins = dev.getPins() };
    while (pin_iter.next()) |io| {
        try tc.cleanTempDir();
        helper.resetTemp();

        const results_none = try runToolchain(ta, tc, dev, io.pin_index, false);
        const results_inreg = try runToolchain(ta, tc, dev, io.pin_index, true);

        var diff = try JedecData.initDiff(ta, results_none.jedec, results_inreg.jedec);

        diff.putRange(dev.getRoutingRange(), 0);

        try helper.writePin(writer, io);

        var n_fuses: usize = 0;

        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            if (results_none.jedec.isSet(fuse)) {
                try helper.writeFuse(writer, fuse);
                n_fuses += 1;
            }
        }

        if (n_fuses != 1) {
            try helper.err("Expected one input register fuse but found {}!", .{ n_fuses }, dev, .{ .pin_index = io.pin_index });
        }

        try writer.close();
    }

    // TODO verify that these match the JEDEC data
    try helper.writeValue(writer, 1, "normal");
    try helper.writeValue(writer, 0, "input_register");

    try writer.done();

    _ = pa;
}
