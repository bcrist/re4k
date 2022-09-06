//[[!! include 'build_zig' !! 48 ]]
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

    const pull = b.addExecutable("pull", "src/pull.zig");
    pull.addPackage(temp_allocator);
    pull.linkLibC();
    pull.setTarget(target);
    pull.setBuildMode(mode);
    pull.install();
    _ = makeRunStep(b, pull, "pull", "run pull");

    const slew = b.addExecutable("slew", "src/slew.zig");
    slew.addPackage(temp_allocator);
    slew.linkLibC();
    slew.setTarget(target);
    slew.setBuildMode(mode);
    slew.install();
    _ = makeRunStep(b, slew, "slew", "run slew");

    const threshold = b.addExecutable("threshold", "src/threshold.zig");
    threshold.addPackage(temp_allocator);
    threshold.linkLibC();
    threshold.setTarget(target);
    threshold.setBuildMode(mode);
    threshold.install();
    _ = makeRunStep(b, threshold, "threshold", "run threshold");

    const zerohold = b.addExecutable("zerohold", "src/zerohold.zig");
    zerohold.addPackage(temp_allocator);
    zerohold.linkLibC();
    zerohold.setTarget(target);
    zerohold.setBuildMode(mode);
    zerohold.install();
    _ = makeRunStep(b, zerohold, "zerohold", "run zerohold");

}
//[[ ######################### END OF GENERATED CODE ######################### ]]


fn makeRunStep(b: *std.build.Builder, exe: *std.build.LibExeObjStep, name: []const u8, desc: []const u8) *std.build.RunStep {
    var run = exe.run();
    run.step.dependOn(b.getInstallStep());
    b.step(name, desc).dependOn(&run.step);
    return run;
}
