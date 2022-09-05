const std = @import("std");
const TempAllocator = @import("temp_allocator");
const toolchain = @import("toolchain.zig");
const DeviceType = @import("device.zig").DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;

pub fn main() !void {
    var temp_alloc = try TempAllocator.init(0x100_00000);
    var alloc = temp_alloc.allocator();
    var args = try std.process.ArgIterator.initWithAllocator(alloc);
    _ = args.next() orelse std.os.exit(255);

    var device_str = args.next() orelse std.os.exit(1);
    const device = DeviceType.parse(device_str) orelse std.os.exit(1);

    var tc = try Toolchain.init(alloc);
    //defer tc.deinit();


    var design = Design.init(alloc, device);

    try design.addPT("a", "out");

    _ = try tc.runToolchain(design);
}
