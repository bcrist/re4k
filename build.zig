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

    const pt0_xor = b.addExecutable("pt0_xor", "src/pt0_xor.zig");
    pt0_xor.addPackage(temp_allocator);
    pt0_xor.linkLibC();
    pt0_xor.setTarget(target);
    pt0_xor.setBuildMode(mode);
    pt0_xor.install();
    _ = makeRunStep(b, pt0_xor, "pt0_xor", "run pt0_xor");

}
//[[ ######################### END OF GENERATED CODE ######################### ]]


fn makeRunStep(b: *std.build.Builder, exe: *std.build.LibExeObjStep, name: []const u8, desc: []const u8) *std.build.RunStep {
    var run = exe.run();
    run.step.dependOn(b.getInstallStep());
    b.step(name, desc).dependOn(&run.step);
    return run;
}
