const std = @import("std");
const toolchain = @import("toolchain.zig");
const jedec = @import("jedec.zig");
const core = @import("core.zig");
const devices = @import("devices.zig");
const TempAllocator = @import("temp_allocator");
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JedecData = jedec.JedecData;

pub fn main() !void {
    var temp_alloc = try TempAllocator.init(0x1000_00000);
    defer temp_alloc.deinit();

    var ta = temp_alloc.allocator();
    var tc = try Toolchain.init(ta);
    defer tc.deinit(true);

    const dev = DeviceType.LC4032ZE_TQFP48;
    var design = Design.init(ta, dev);

    try design.pinAssignment(.{ .signal = "d0", .pin_index = 22, });
    try design.pinAssignment(.{ .signal = "d1", .pin_index = 23, });
    try design.pinAssignment(.{ .signal = "d2", .pin_index = 25, });
    try design.pinAssignment(.{ .signal = "d3", .pin_index = 26, });
    try design.pinAssignment(.{ .signal = "d4", .pin_index = 27, });
    try design.pinAssignment(.{ .signal = "d5", .pin_index = 30, });
    try design.pinAssignment(.{ .signal = "d6", .pin_index = 31, });
    try design.pinAssignment(.{ .signal = "d7", .pin_index = 32, });

    try design.pinAssignment(.{ .signal = "s1", .pin_index = 18, });
    try design.pinAssignment(.{ .signal = "s2", .pin_index = 19, });
    try design.pinAssignment(.{ .signal = "s3", .pin_index = 20, });
    try design.pinAssignment(.{ .signal = "s4", .pin_index = 21, });

    try design.addPT("~s4", "d0.D");
    try design.addPT("~s3", "d1.D");
    try design.addPT("~s2", "d2.D");

    try design.addPT("s1", "d0.C");
    try design.addPT("s1", "d1.C");
    try design.addPT("s1", "d2.C");

    var results = try tc.runToolchain(design);
    try results.checkTerm();
}
