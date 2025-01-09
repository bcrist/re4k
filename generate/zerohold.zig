const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const Device_Info = @import("Device_Info.zig");
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JEDEC_Data = lc4k.JEDEC_Data;

pub fn main() void {
    helper.main();
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    var design = Design.init(ta, dev);
    try design.add_pt("in", "out");
    const results_without_zero_hold = try tc.run_toolchain(design);
    try results_without_zero_hold.check_term();
    try tc.clean_temp_dir();

    design.zero_hold_time = true;
    const results_with_zero_hold = try tc.run_toolchain(design);
    try results_with_zero_hold.check_term();

    const diff = try JEDEC_Data.init_diff(ta, results_without_zero_hold.jedec, results_with_zero_hold.jedec);

    var diff_iter = diff.iterator(.{});
    if (diff_iter.next()) |fuse| {
        try writer.expression_expanded(@tagName(dev.device));
        try writer.expression_expanded("zero_hold_time");

        try helper.write_fuse(writer, fuse);

        try helper.write_value(writer, results_without_zero_hold.jedec.get(fuse), "disabled");
        try helper.write_value(writer, results_with_zero_hold.jedec.get(fuse), "enabled");

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
