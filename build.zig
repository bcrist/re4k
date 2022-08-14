//[[!! include 'build_zig' !! 31 ]]
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

    const fit = b.addExecutable("fit", "src/fit.zig");
    fit.linkLibC();
    fit.setTarget(target);
    fit.setBuildMode(mode);
    fit.install();
    _ = makeRunStep(b, fit, "fit", "run fit");

    const jeddiff = b.addExecutable("jeddiff", "src/jeddiff.zig");
    jeddiff.linkLibC();
    jeddiff.setTarget(target);
    jeddiff.setBuildMode(mode);
    jeddiff.install();
    _ = makeRunStep(b, jeddiff, "jeddiff", "run jeddiff");

    _ = temp_allocator;
}
//[[ ######################### END OF GENERATED CODE ######################### ]]


fn makeRunStep(b: *std.build.Builder, exe: *std.build.LibExeObjStep, name: []const u8, desc: []const u8) *std.build.RunStep {
    var run = exe.run();
    run.step.dependOn(b.getInstallStep());
    b.step(name, desc).dependOn(&run.step);
    return run;
}
