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

    const ce_mux = b.addExecutable("ce_mux", "src/ce_mux.zig");
    ce_mux.addPackage(temp_allocator);
    ce_mux.linkLibC();
    ce_mux.setTarget(target);
    ce_mux.setBuildMode(mode);
    ce_mux.install();
    _ = makeRunStep(b, ce_mux, "ce_mux", "run ce_mux");

}
//[[ ######################### END OF GENERATED CODE ######################### ]]


fn makeRunStep(b: *std.build.Builder, exe: *std.build.LibExeObjStep, name: []const u8, desc: []const u8) *std.build.RunStep {
    var run = exe.run();
    run.step.dependOn(b.getInstallStep());
    b.step(name, desc).dependOn(&run.step);
    return run;
}
