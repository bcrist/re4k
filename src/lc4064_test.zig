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

    const dev = DeviceType.LC4064ZC_TQFP100;
    var design = Design.init(ta, dev);

    try design.pinAssignment(.{ .signal = "a0", .pin_index = 90, .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "a1", .pin_index = 91, .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "a2", .pin_index = 92, .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "a3", .pin_index = 93, .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "a4", .pin_index = 96, .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "a5", .pin_index = 97, .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "a6", .pin_index = 98, .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "a7", .pin_index = 99, .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "a8", .pin_index = 2,   .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "a9", .pin_index = 3,   .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "a10", .pin_index = 4,  .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "a11", .pin_index = 5,  .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "a12", .pin_index = 7,  .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "a13", .pin_index = 8,  .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "a14", .pin_index = 9,  .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "a15", .pin_index = 10, .powerup_state = 0 });

    try design.pinAssignment(.{ .signal = "b0", .pin_index = 36, .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "b1", .pin_index = 35, .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "b2", .pin_index = 34, .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "b3", .pin_index = 33, .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "b4", .pin_index = 30, .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "b5", .pin_index = 29, .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "b6", .pin_index = 28, .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "b7", .pin_index = 27, .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "b8", .pin_index = 21,   .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "b9", .pin_index = 20,   .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "b10", .pin_index = 19,  .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "b11", .pin_index = 18,  .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "b12", .pin_index = 16,  .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "b13", .pin_index = 15,  .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "b14", .pin_index = 14,  .powerup_state = 0 });
    try design.pinAssignment(.{ .signal = "b15", .pin_index = 13, .powerup_state = 0 });

    try design.pinAssignment(.{ .signal = "clk", .pin_index = 11, });
    try design.pinAssignment(.{ .signal = "dir", .pin_index = 40, .powerup_state = 1 });
    try design.pinAssignment(.{ .signal = "none", .pin_index = 60 });


    try design.addPT(.{
        "~a0.Q", "~a3.Q", "~a6.Q", "~a9.Q", "~a12.Q", "~a15.Q",
        "~b0.Q", "~b3.Q", "~b6.Q", "~b9.Q", "~b12.Q", "~b15.Q",
    }, "none");

    try design.addPT("clk", .{ "dir.C",
        "a0.C", "a1.C", "a2.C",  "a3.C",  "a4.C",  "a5.C",  "a6.C",  "a7.C",
        "a8.C", "a9.C", "a10.C", "a11.C", "a12.C", "a13.C", "a14.C", "a15.C",
        "b0.C", "b1.C", "b2.C",  "b3.C",  "b4.C",  "b5.C",  "b6.C",  "b7.C",
        "b8.C", "b9.C", "b10.C", "b11.C", "b12.C", "b13.C", "b14.C", "b15.C",
    });

    try design.addPT(.{"~dir.Q", "none"}, "dir.D");
    try design.addPT(.{"dir.Q", "~none"}, "dir.D");

    try design.addPT(.{"dir.Q", "none"}, "a0.D");
    try design.addPT(.{"~dir.Q", "a0.Q", "~a3.Q", "~a6.Q", "~a9.Q", "~a12.Q", "~a15.Q", "~b12.Q", "~b9.Q", "~b6.Q", "~b3.Q", "~b0.Q"}, "a0.D");
    try design.addPT(.{"~dir.Q", "a0.Q"}, "a1.D");
    try design.addPT(.{"~dir.Q", "a1.Q"}, "a2.D");
    try design.addPT(.{"~dir.Q", "a2.Q"}, "a3.D");
    try design.addPT(.{"~dir.Q", "a3.Q"}, "a4.D");
    try design.addPT(.{"~dir.Q", "a4.Q"}, "a5.D");
    try design.addPT(.{"~dir.Q", "a5.Q"}, "a6.D");
    try design.addPT(.{"~dir.Q", "a6.Q"}, "a7.D");
    try design.addPT(.{"~dir.Q", "a7.Q"}, "a8.D");
    try design.addPT(.{"~dir.Q", "a8.Q"}, "a9.D");
    try design.addPT(.{"~dir.Q", "a9.Q"}, "a10.D");
    try design.addPT(.{"~dir.Q", "a10.Q"}, "a11.D");
    try design.addPT(.{"~dir.Q", "a11.Q"}, "a12.D");
    try design.addPT(.{"~dir.Q", "a12.Q"}, "a13.D");
    try design.addPT(.{"~dir.Q", "a13.Q"}, "a14.D");
    try design.addPT(.{"~dir.Q", "a14.Q"}, "a15.D");
    try design.addPT(.{"~dir.Q", "a15.Q"}, "b15.D");
    try design.addPT(.{"~dir.Q", "b15.Q"}, "b14.D");
    try design.addPT(.{"~dir.Q", "b14.Q"}, "b13.D");
    try design.addPT(.{"~dir.Q", "b13.Q"}, "b12.D");
    try design.addPT(.{"~dir.Q", "b12.Q"}, "b11.D");
    try design.addPT(.{"~dir.Q", "b11.Q"}, "b10.D");
    try design.addPT(.{"~dir.Q", "b10.Q"}, "b9.D");
    try design.addPT(.{"~dir.Q", "b9.Q"}, "b8.D");
    try design.addPT(.{"~dir.Q", "b8.Q"}, "b7.D");
    try design.addPT(.{"~dir.Q", "b7.Q"}, "b6.D");
    try design.addPT(.{"~dir.Q", "b6.Q"}, "b5.D");
    try design.addPT(.{"~dir.Q", "b5.Q"}, "b4.D");
    try design.addPT(.{"~dir.Q", "b4.Q"}, "b3.D");
    try design.addPT(.{"~dir.Q", "b3.Q"}, "b2.D");
    try design.addPT(.{"~dir.Q", "b2.Q"}, "b1.D");
    try design.addPT(.{"~dir.Q", "b1.Q"}, "b0.D");

    try design.addPT(.{"~dir.Q", "none"}, "b0.D");
    try design.addPT(.{"dir.Q", "b0.Q", "~b3.Q", "~b6.Q", "~b9.Q", "~b12.Q", "~b15.Q", "~a12.Q", "~a9.Q", "~a6.Q", "~a3.Q", "~a0.Q"}, "b0.D");
    try design.addPT(.{"dir.Q", "b0.Q"}, "b1.D");
    try design.addPT(.{"dir.Q", "b1.Q"}, "b2.D");
    try design.addPT(.{"dir.Q", "b2.Q"}, "b3.D");
    try design.addPT(.{"dir.Q", "b3.Q"}, "b4.D");
    try design.addPT(.{"dir.Q", "b4.Q"}, "b5.D");
    try design.addPT(.{"dir.Q", "b5.Q"}, "b6.D");
    try design.addPT(.{"dir.Q", "b6.Q"}, "b7.D");
    try design.addPT(.{"dir.Q", "b7.Q"}, "b8.D");
    try design.addPT(.{"dir.Q", "b8.Q"}, "b9.D");
    try design.addPT(.{"dir.Q", "b9.Q"}, "b10.D");
    try design.addPT(.{"dir.Q", "b10.Q"}, "b11.D");
    try design.addPT(.{"dir.Q", "b11.Q"}, "b12.D");
    try design.addPT(.{"dir.Q", "b12.Q"}, "b13.D");
    try design.addPT(.{"dir.Q", "b13.Q"}, "b14.D");
    try design.addPT(.{"dir.Q", "b14.Q"}, "b15.D");
    try design.addPT(.{"dir.Q", "b15.Q"}, "a15.D");
    try design.addPT(.{"dir.Q", "a15.Q"}, "a14.D");
    try design.addPT(.{"dir.Q", "a14.Q"}, "a13.D");
    try design.addPT(.{"dir.Q", "a13.Q"}, "a12.D");
    try design.addPT(.{"dir.Q", "a12.Q"}, "a11.D");
    try design.addPT(.{"dir.Q", "a11.Q"}, "a10.D");
    try design.addPT(.{"dir.Q", "a10.Q"}, "a9.D");
    try design.addPT(.{"dir.Q", "a9.Q"}, "a8.D");
    try design.addPT(.{"dir.Q", "a8.Q"}, "a7.D");
    try design.addPT(.{"dir.Q", "a7.Q"}, "a6.D");
    try design.addPT(.{"dir.Q", "a6.Q"}, "a5.D");
    try design.addPT(.{"dir.Q", "a5.Q"}, "a4.D");
    try design.addPT(.{"dir.Q", "a4.Q"}, "a3.D");
    try design.addPT(.{"dir.Q", "a3.Q"}, "a2.D");
    try design.addPT(.{"dir.Q", "a2.Q"}, "a1.D");
    try design.addPT(.{"dir.Q", "a1.Q"}, "a0.D");


    var results = try tc.runToolchain(design);
    try results.checkTerm();
}
