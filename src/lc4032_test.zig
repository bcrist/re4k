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

    // counter bit 0
    try design.addPT("~d3.Q", "d3.D");

    // counter bit 1
    try design.addPT(.{"d3.Q", "~d4.Q"}, "d4.D");
    try design.addPT(.{"~d3.Q", "d4.Q"}, "d4.D");

    // counter bit 2
    try design.addPT(.{"d3.Q", "d4.Q", "~d5.Q"}, "d5.D");
    try design.addPT(.{"d5.Q", "~d4.Q"}, "d5.D");
    try design.addPT(.{"d5.Q", "~d3.Q"}, "d5.D");

    // counter bit 3
    try design.addPT(.{"d3.Q", "d4.Q", "d5.Q", "~d6.Q"}, "d6.D");
    try design.addPT(.{"d6.Q", "~d5.Q"}, "d6.D");
    try design.addPT(.{"d6.Q", "~d4.Q"}, "d6.D");
    try design.addPT(.{"d6.Q", "~d3.Q"}, "d6.D");

    // counter bit 4
    try design.addPT(.{"d3.Q", "d4.Q", "d5.Q", "d6.Q", "~d7.Q"}, "d7.D");
    try design.addPT(.{"d7.Q", "~d6.Q"}, "d7.D");
    try design.addPT(.{"d7.Q", "~d5.Q"}, "d7.D");
    try design.addPT(.{"d7.Q", "~d4.Q"}, "d7.D");
    try design.addPT(.{"d7.Q", "~d3.Q"}, "d7.D");

    // register S2/3/4 directly
    try design.addPT("~s4", "d0.D");
    try design.addPT("~s3", "d1.D");
    try design.addPT("~s2", "d2.D");

    // clock from S1
    try design.addPT("s1", "d0.C");
    try design.addPT("s1", "d1.C");
    try design.addPT("s1", "d2.C");
    try design.addPT("s1", "d3.C");
    try design.addPT("s1", "d4.C");
    try design.addPT("s1", "d5.C");
    try design.addPT("s1", "d6.C");
    try design.addPT("s1", "d7.C");

    var results = try tc.runToolchain(design);
    try results.checkTerm();
}
