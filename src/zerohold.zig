const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx.zig");
const devices = @import("devices/devices.zig");
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

pub fn main() void {
    helper.main();
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    var design = Design.init(ta, dev);
    try design.addPT("in", "out");
    const results_without_zero_hold = try tc.runToolchain(design);
    try results_without_zero_hold.checkTerm();
    try tc.cleanTempDir();

    design.zero_hold_time = true;
    const results_with_zero_hold = try tc.runToolchain(design);
    try results_with_zero_hold.checkTerm();

    var diff = try results_without_zero_hold.jedec.clone(ta);
    try diff.xor(results_with_zero_hold.jedec);

    var diff_iter = diff.raw.iterator(.{});
    if (diff_iter.next()) |fuse| {
        const row = diff.getRow(@intCast(u32, fuse));
        const col = diff.getColumn(@intCast(u32, fuse));

        try writer.expressionExpanded(@tagName(dev));
        try writer.expressionExpanded("zero_hold_time");
        try writer.expression("fuse");
        try writer.printRaw("{}", .{ row });
        try writer.printRaw("{}", .{ col });
        try writer.close();
        try writer.expression("value");
        try writer.printRaw("{} disabled", .{ results_without_zero_hold.jedec.get(row, col) });
        try writer.close();
        try writer.expression("value");
        try writer.printRaw("{} enabled", .{ results_with_zero_hold.jedec.get(row, col) });
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
