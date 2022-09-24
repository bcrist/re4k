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

    const input_reg = b.addExecutable("input_reg", "src/input_reg.zig");
    input_reg.addPackage(temp_allocator);
    input_reg.linkLibC();
    input_reg.setTarget(target);
    input_reg.setBuildMode(mode);
    input_reg.install();
    _ = makeRunStep(b, input_reg, "input_reg", "run input_reg");

}
//[[ ######################### END OF GENERATED CODE ######################### ]]


fn makeRunStep(b: *std.build.Builder, exe: *std.build.LibExeObjStep, name: []const u8, desc: []const u8) *std.build.RunStep {
    var run = exe.run();
    run.step.dependOn(b.getInstallStep());
    b.step(name, desc).dependOn(&run.step);
    return run;
}
