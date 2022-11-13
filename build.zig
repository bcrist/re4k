const std = @import("std");
const microbe = @import("pkg/microbe/src/microbe.zig");
const hw_tests_lc4032ze = @import("hardware-tests/firmware/lc4032ze.zig");
const hw_tests_lc4064zc = @import("hardware-tests/firmware/lc4064zc.zig");

const Pkg = std.build.Pkg;

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const FirmwareType = enum {
        lc4032ze,
        lc4032zc,
    };
    if (b.option(FirmwareType, "firmware", "Build firmware for hardware-tests boards")) |firmware_type| switch (firmware_type) {
        inline else => |fw| {
            var firmware = microbe.addEmbeddedExecutable(b,
                "hw-test-firmware-" ++ @tagName(fw) ++ ".elf",
                "hardware-tests/firmware/" ++ @tagName(fw) ++ ".zig",
                microbe.chips.stm32g030k8,
                microbe.defaultSections(2048),
            );
            firmware.setBuildMode(mode);
            firmware.install();
            var raw = firmware.installRaw("hw-test-firmware-" ++ @tagName(fw) ++ ".bin", .{});

            const raw_step = b.step("bin", "Convert ELF to bin file");
            raw_step.dependOn(&raw.step);

            var flash = b.addSystemCommand(&.{
                "C:\\Program Files (x86)\\STMicroelectronics\\STM32 ST-LINK Utility\\ST-LINK Utility\\ST-LINK_CLI.exe",
                "-c", "SWD", "UR", "LPM",
                "-P", b.getInstallPath(.bin, "hw-test-firmware-" ++ @tagName(fw) ++ ".bin"), "0x08000000",
                "-V", "after_programming",
                "-HardRst", "PULSE=100",
            });
            flash.step.dependOn(&raw.step);
            const flash_step = b.step("flash", "Flash firmware with ST-LINK");
            flash_step.dependOn(&flash.step);
        },
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
