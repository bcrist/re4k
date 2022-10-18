const std = @import("std");
const microzig = @import("pkg/microzig/src/main.zig");
const hw_tests_lc4032ze = @import("hardware-tests/firmware/lc4032ze.zig");
const hw_tests_lc4064zc = @import("hardware-tests/firmware/lc4064zc.zig");

const Pkg = std.build.Pkg;

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    if (b.option(bool, "firmware", "Build firmware for hardware-tests boards")) |o| {
        if (o) {
            var lc4032ze = microzig.addEmbeddedExecutable(b,
                "hw-test-firmware-lc4032ze.bin",
                "hardware-tests/firmware/lc4032ze.zig",
                .{ .chip = microzig.chips.stm32g030x8 },
                .{}
            );
            lc4032ze.setBuildMode(mode);
            lc4032ze.install();

            var lc4064zc = microzig.addEmbeddedExecutable(b,
                "hw-test-firmware-lc4064zc.bin",
                "hardware-tests/firmware/lc4064zc.zig",
                .{ .chip = microzig.chips.stm32g030x8 },
                .{}
            );
            lc4064zc.setBuildMode(mode);
            lc4064zc.install();
        }
    } else {
        //[[!! include 'build_zig' !! 16 ]]
        //[[ ################# !! GENERATED CODE -- DO NOT MODIFY !! ################# ]]
        const temp_allocator = Pkg {
            .name = "temp_allocator",
            .source = .{ .path = "pkg/tempallocator/temp_allocator.zig" },
        };

        const output_routing_mode = b.addExecutable("output_routing_mode", "src/output_routing_mode.zig");
        output_routing_mode.addPackage(temp_allocator);
        output_routing_mode.linkLibC();
        output_routing_mode.setTarget(target);
        output_routing_mode.setBuildMode(mode);
        output_routing_mode.install();
        _ = makeRunStep(b, output_routing_mode, "output_routing_mode", "run output_routing_mode");

        //[[ ######################### END OF GENERATED CODE ######################### ]]
    }
}

fn makeRunStep(b: *std.build.Builder, exe: *std.build.LibExeObjStep, name: []const u8, desc: []const u8) *std.build.RunStep {
    var run = exe.run();
    run.step.dependOn(b.getInstallStep());
    b.step(name, desc).dependOn(&run.step);
    return run;
}
