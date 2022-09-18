//[[!! include 'build_zig' !! 24 ]]
//[[ ################# !! GENERATED CODE -- DO NOT MODIFY !! ################# ]]
const std = @import("std");
const Pkg = std.build.Pkg;

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const temp_allocator = Pkg {
        .name = "temp_allocator",
        .source = .{ .path = "pkg/tempallocator/temp_allocator.zig" },
    };

    const clk_mux = b.addExecutable("clk_mux", "src/clk_mux.zig");
    clk_mux.addPackage(temp_allocator);
    clk_mux.linkLibC();
    clk_mux.setTarget(target);
    clk_mux.setBuildMode(mode);
    clk_mux.install();
    _ = makeRunStep(b, clk_mux, "clk_mux", "run clk_mux");

}
//[[ ######################### END OF GENERATED CODE ######################### ]]


fn makeRunStep(b: *std.build.Builder, exe: *std.build.LibExeObjStep, name: []const u8, desc: []const u8) *std.build.RunStep {
    var run = exe.run();
    run.step.dependOn(b.getInstallStep());
    b.step(name, desc).dependOn(&run.step);
    return run;
}
