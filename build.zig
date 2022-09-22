//[[!! include 'build_zig' !! 128 ]]
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

    const clk_mux = b.addExecutable("clk_mux", "src/clk_mux.zig");
    clk_mux.addPackage(temp_allocator);
    clk_mux.linkLibC();
    clk_mux.setTarget(target);
    clk_mux.setBuildMode(mode);
    clk_mux.install();
    _ = makeRunStep(b, clk_mux, "clk_mux", "run clk_mux");

    const drive = b.addExecutable("drive", "src/drive.zig");
    drive.addPackage(temp_allocator);
    drive.linkLibC();
    drive.setTarget(target);
    drive.setBuildMode(mode);
    drive.install();
    _ = makeRunStep(b, drive, "drive", "run drive");

    const grp = b.addExecutable("grp", "src/grp.zig");
    grp.addPackage(temp_allocator);
    grp.linkLibC();
    grp.setTarget(target);
    grp.setBuildMode(mode);
    grp.install();
    _ = makeRunStep(b, grp, "grp", "run grp");

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

    const powerup_state = b.addExecutable("powerup_state", "src/powerup_state.zig");
    powerup_state.addPackage(temp_allocator);
    powerup_state.linkLibC();
    powerup_state.setTarget(target);
    powerup_state.setBuildMode(mode);
    powerup_state.install();
    _ = makeRunStep(b, powerup_state, "powerup_state", "run powerup_state");

    const pt2_reset = b.addExecutable("pt2_reset", "src/pt2_reset.zig");
    pt2_reset.addPackage(temp_allocator);
    pt2_reset.linkLibC();
    pt2_reset.setTarget(target);
    pt2_reset.setBuildMode(mode);
    pt2_reset.install();
    _ = makeRunStep(b, pt2_reset, "pt2_reset", "run pt2_reset");

    const pt3_reset = b.addExecutable("pt3_reset", "src/pt3_reset.zig");
    pt3_reset.addPackage(temp_allocator);
    pt3_reset.linkLibC();
    pt3_reset.setTarget(target);
    pt3_reset.setBuildMode(mode);
    pt3_reset.install();
    _ = makeRunStep(b, pt3_reset, "pt3_reset", "run pt3_reset");

    const pull = b.addExecutable("pull", "src/pull.zig");
    pull.addPackage(temp_allocator);
    pull.linkLibC();
    pull.setTarget(target);
    pull.setBuildMode(mode);
    pull.install();
    _ = makeRunStep(b, pull, "pull", "run pull");

    const reg_type = b.addExecutable("reg_type", "src/reg_type.zig");
    reg_type.addPackage(temp_allocator);
    reg_type.linkLibC();
    reg_type.setTarget(target);
    reg_type.setBuildMode(mode);
    reg_type.install();
    _ = makeRunStep(b, reg_type, "reg_type", "run reg_type");

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
