//[[!! include 'build_zig' !! 72 ]]
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

    const drive = b.addExecutable("drive", "src/drive.zig");
    drive.addPackage(temp_allocator);
    drive.linkLibC();
    drive.setTarget(target);
    drive.setBuildMode(mode);
    drive.install();
    _ = makeRunStep(b, drive, "drive", "run drive");

    const oe_mux = b.addExecutable("oe_mux", "src/oe_mux.zig");
    oe_mux.addPackage(temp_allocator);
    oe_mux.linkLibC();
    oe_mux.setTarget(target);
    oe_mux.setBuildMode(mode);
    oe_mux.install();
    _ = makeRunStep(b, oe_mux, "oe_mux", "run oe_mux");

    const orm = b.addExecutable("orm", "src/orm.zig");
    orm.addPackage(temp_allocator);
    orm.linkLibC();
    orm.setTarget(target);
    orm.setBuildMode(mode);
    orm.install();
    _ = makeRunStep(b, orm, "orm", "run orm");

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
