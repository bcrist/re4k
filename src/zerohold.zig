const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const jedec = lc4k.jedec;
const device_info = @import("device_info.zig");
const DeviceInfo = device_info.DeviceInfo;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JedecData = jedec.JedecData;

pub fn main() void {
    helper.main();
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer) !void {
    var design = Design.init(ta, dev);
    try design.addPT("in", "out");
    const results_without_zero_hold = try tc.runToolchain(design);
    try results_without_zero_hold.checkTerm();
    try tc.cleanTempDir();

    design.zero_hold_time = true;
    const results_with_zero_hold = try tc.runToolchain(design);
    try results_with_zero_hold.checkTerm();

    const diff = try JedecData.initDiff(ta, results_without_zero_hold.jedec, results_with_zero_hold.jedec);

    var diff_iter = diff.iterator(.{});
    if (diff_iter.next()) |fuse| {
        try writer.expression_expanded(@tagName(dev.device));
        try writer.expression_expanded("zero_hold_time");

        try helper.writeFuse(writer, fuse);

        try helper.writeValue(writer, results_without_zero_hold.jedec.get(fuse), "disabled");
        try helper.writeValue(writer, results_with_zero_hold.jedec.get(fuse), "enabled");

        try writer.done();
    } else {
        try std.io.getStdErr().writer().print("Expected one zerohold fuse for device {} but found none!\n", .{ dev });
        return error.Think;
    }

    if (diff_iter.next()) |_| {
        try std.io.getStdErr().writer().print("Expected one zerohold fuse for device {} but found multiple!\n", .{ dev });
        return error.Think;
    }

    _ = pa;
}
