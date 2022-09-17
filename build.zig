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

    const pt2_reset = b.addExecutable("pt2_reset", "src/pt2_reset.zig");
    pt2_reset.addPackage(temp_allocator);
    pt2_reset.linkLibC();
    pt2_reset.setTarget(target);
    pt2_reset.setBuildMode(mode);
    pt2_reset.install();
    _ = makeRunStep(b, pt2_reset, "pt2_reset", "run pt2_reset");

}
//[[ ######################### END OF GENERATED CODE ######################### ]]


fn makeRunStep(b: *std.build.Builder, exe: *std.build.LibExeObjStep, name: []const u8, desc: []const u8) *std.build.RunStep {
    var run = exe.run();
    run.step.dependOn(b.getInstallStep());
    b.step(name, desc).dependOn(&run.step);
    return run;
}
