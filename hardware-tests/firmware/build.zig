const std = @import("std");

pub fn build(b: *std.Build) void {
    var firmware = microbe.addEmbeddedExecutable(b,
        "hw-test-firmware-" ++ @tagName(fw) ++ ".elf",
        "hardware-tests/firmware/" ++ @tagName(fw) ++ ".zig",
        microbe.chips.stm32g030k8,
        microbe.defaultSections(2048),
    );
    firmware.addPackagePath("svf_file", "pkg/lc4k/src/svf_file.zig");
    firmware.addPackagePath("common", "pkg/lc4k/src/common.zig");
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
}
