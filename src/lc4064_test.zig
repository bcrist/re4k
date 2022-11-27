const std = @import("std");
const toolchain = @import("toolchain.zig");
const jedec = @import("jedec");
const common = @import("common");
const device_info = @import("device_info.zig");
const TempAllocator = @import("temp_allocator");
const DeviceInfo = device_info.DeviceInfo;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JedecData = jedec.JedecData;

pub fn main() !void {
    var temp_alloc = try TempAllocator.init(0x1000_00000);
    defer temp_alloc.deinit();

    var ta = temp_alloc.allocator();
    var tc = try Toolchain.init(ta);
    defer tc.deinit(true);

    const dev = DeviceInfo.init(.LC4064ZC_TQFP100);
    var design = Design.init(ta, &dev);

    try design.pinAssignment(.{ .signal = "a0", .pin = "91",  .init_state = 0 });
    try design.pinAssignment(.{ .signal = "a1", .pin = "92",  .init_state = 0 });
    try design.pinAssignment(.{ .signal = "a2", .pin = "93",  .init_state = 0 });
    try design.pinAssignment(.{ .signal = "a3", .pin = "94",  .init_state = 0 });
    try design.pinAssignment(.{ .signal = "a4", .pin = "97",  .init_state = 0 });
    try design.pinAssignment(.{ .signal = "a5", .pin = "98",  .init_state = 0 });
    try design.pinAssignment(.{ .signal = "a6", .pin = "99",  .init_state = 0 });
    try design.pinAssignment(.{ .signal = "a7", .pin = "100", .init_state = 0 });
    try design.pinAssignment(.{ .signal = "a8", .pin = "3",   .init_state = 0 });
    try design.pinAssignment(.{ .signal = "a9", .pin = "4",   .init_state = 0 });
    try design.pinAssignment(.{ .signal = "a10", .pin = "5",  .init_state = 0 });
    try design.pinAssignment(.{ .signal = "a11", .pin = "6",  .init_state = 0 });
    try design.pinAssignment(.{ .signal = "a12", .pin = "8",  .init_state = 0 });
    try design.pinAssignment(.{ .signal = "a13", .pin = "9",  .init_state = 0 });
    try design.pinAssignment(.{ .signal = "a14", .pin = "10", .init_state = 0 });
    try design.pinAssignment(.{ .signal = "a15", .pin = "11", .init_state = 0 });

    try design.pinAssignment(.{ .signal = "b0", .pin = "37",  .init_state = 0 });
    try design.pinAssignment(.{ .signal = "b1", .pin = "36",  .init_state = 0 });
    try design.pinAssignment(.{ .signal = "b2", .pin = "35",  .init_state = 0 });
    try design.pinAssignment(.{ .signal = "b3", .pin = "34",  .init_state = 0 });
    try design.pinAssignment(.{ .signal = "b4", .pin = "31",  .init_state = 0 });
    try design.pinAssignment(.{ .signal = "b5", .pin = "30",  .init_state = 0 });
    try design.pinAssignment(.{ .signal = "b6", .pin = "29",  .init_state = 0 });
    try design.pinAssignment(.{ .signal = "b7", .pin = "28",  .init_state = 0 });
    try design.pinAssignment(.{ .signal = "b8", .pin = "22",  .init_state = 0 });
    try design.pinAssignment(.{ .signal = "b9", .pin = "21",  .init_state = 0 });
    try design.pinAssignment(.{ .signal = "b10", .pin = "20", .init_state = 0 });
    try design.pinAssignment(.{ .signal = "b11", .pin = "19", .init_state = 0 });
    try design.pinAssignment(.{ .signal = "b12", .pin = "17", .init_state = 0 });
    try design.pinAssignment(.{ .signal = "b13", .pin = "16", .init_state = 0 });
    try design.pinAssignment(.{ .signal = "b14", .pin = "15", .init_state = 0 });
    try design.pinAssignment(.{ .signal = "b15", .pin = "14", .init_state = 0 });

    try design.pinAssignment(.{ .signal = "clk", .pin = "12", });
    try design.pinAssignment(.{ .signal = "dir", .pin = "41", .init_state = 1 });
    try design.pinAssignment(.{ .signal = "none", .pin = "61" });


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
