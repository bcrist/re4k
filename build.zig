const std = @import("std");
const microbe = @import("pkg/microbe/src/microbe.zig");

const Pkg = std.build.Pkg;

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const FirmwareType = enum {
        lc4032ze,
        lc4064zc,
    };
    if (b.option(FirmwareType, "firmware", "Build firmware for hardware-tests boards")) |firmware_type| switch (firmware_type) {
        inline else => |fw| {
            var firmware = microbe.addEmbeddedExecutable(b,
                "hw-test-firmware-" ++ @tagName(fw) ++ ".elf",
                "hardware-tests/firmware/" ++ @tagName(fw) ++ ".zig",
                microbe.chips.stm32g030k8,
                microbe.defaultSections(2048),
            );
            firmware.addPackagePath("svf", "src/svf.zig");
            firmware.addPackagePath("devices", "src/devices.zig");
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
        //[[!! include 'build_zig' !! 255 ]]
        //[[ ################# !! GENERATED CODE -- DO NOT MODIFY !! ################# ]]
        const sx = Pkg {
            .name = "sx",
            .source = .{ .path = "pkg/sx/sx.zig" },
        };
        const temp_allocator = Pkg {
            .name = "temp_allocator",
            .source = .{ .path = "pkg/tempallocator/temp_allocator.zig" },
        };

        const bclk_polarity = b.addExecutable("bclk_polarity", "src/bclk_polarity.zig");
        bclk_polarity.addPackage(sx);
        bclk_polarity.addPackage(temp_allocator);
        bclk_polarity.linkLibC();
        bclk_polarity.setTarget(target);
        bclk_polarity.setBuildMode(mode);
        bclk_polarity.install();
        _ = makeRunStep(b, bclk_polarity, "bclk_polarity", "run bclk_polarity");

        const ce_mux = b.addExecutable("ce_mux", "src/ce_mux.zig");
        ce_mux.addPackage(sx);
        ce_mux.addPackage(temp_allocator);
        ce_mux.linkLibC();
        ce_mux.setTarget(target);
        ce_mux.setBuildMode(mode);
        ce_mux.install();
        _ = makeRunStep(b, ce_mux, "ce_mux", "run ce_mux");

        const clk_mux = b.addExecutable("clk_mux", "src/clk_mux.zig");
        clk_mux.addPackage(sx);
        clk_mux.addPackage(temp_allocator);
        clk_mux.linkLibC();
        clk_mux.setTarget(target);
        clk_mux.setBuildMode(mode);
        clk_mux.install();
        _ = makeRunStep(b, clk_mux, "clk_mux", "run clk_mux");

        const cluster_steering = b.addExecutable("cluster_steering", "src/cluster_steering.zig");
        cluster_steering.addPackage(sx);
        cluster_steering.addPackage(temp_allocator);
        cluster_steering.linkLibC();
        cluster_steering.setTarget(target);
        cluster_steering.setBuildMode(mode);
        cluster_steering.install();
        _ = makeRunStep(b, cluster_steering, "cluster_steering", "run cluster_steering");

        const convert_bclk_polarity = b.addExecutable("convert-bclk_polarity", "src/convert-bclk_polarity.zig");
        convert_bclk_polarity.addPackage(sx);
        convert_bclk_polarity.addPackage(temp_allocator);
        convert_bclk_polarity.linkLibC();
        convert_bclk_polarity.setTarget(target);
        convert_bclk_polarity.setBuildMode(mode);
        convert_bclk_polarity.install();
        _ = makeRunStep(b, convert_bclk_polarity, "convert-bclk_polarity", "run convert-bclk_polarity");

        const convert_grp = b.addExecutable("convert-grp", "src/convert-grp.zig");
        convert_grp.addPackage(sx);
        convert_grp.addPackage(temp_allocator);
        convert_grp.linkLibC();
        convert_grp.setTarget(target);
        convert_grp.setBuildMode(mode);
        convert_grp.install();
        _ = makeRunStep(b, convert_grp, "convert-grp", "run convert-grp");

        const drive = b.addExecutable("drive", "src/drive.zig");
        drive.addPackage(sx);
        drive.addPackage(temp_allocator);
        drive.linkLibC();
        drive.setTarget(target);
        drive.setBuildMode(mode);
        drive.install();
        _ = makeRunStep(b, drive, "drive", "run drive");

        const grp = b.addExecutable("grp", "src/grp.zig");
        grp.addPackage(sx);
        grp.addPackage(temp_allocator);
        grp.linkLibC();
        grp.setTarget(target);
        grp.setBuildMode(mode);
        grp.install();
        _ = makeRunStep(b, grp, "grp", "run grp");

        const input_reg = b.addExecutable("input_reg", "src/input_reg.zig");
        input_reg.addPackage(sx);
        input_reg.addPackage(temp_allocator);
        input_reg.linkLibC();
        input_reg.setTarget(target);
        input_reg.setBuildMode(mode);
        input_reg.install();
        _ = makeRunStep(b, input_reg, "input_reg", "run input_reg");

        const invert = b.addExecutable("invert", "src/invert.zig");
        invert.addPackage(sx);
        invert.addPackage(temp_allocator);
        invert.linkLibC();
        invert.setTarget(target);
        invert.setBuildMode(mode);
        invert.install();
        _ = makeRunStep(b, invert, "invert", "run invert");

        const lc4032_test = b.addExecutable("lc4032_test", "src/lc4032_test.zig");
        lc4032_test.addPackage(sx);
        lc4032_test.addPackage(temp_allocator);
        lc4032_test.linkLibC();
        lc4032_test.setTarget(target);
        lc4032_test.setBuildMode(mode);
        lc4032_test.install();
        _ = makeRunStep(b, lc4032_test, "lc4032_test", "run lc4032_test");

        const lc4064_test = b.addExecutable("lc4064_test", "src/lc4064_test.zig");
        lc4064_test.addPackage(sx);
        lc4064_test.addPackage(temp_allocator);
        lc4064_test.linkLibC();
        lc4064_test.setTarget(target);
        lc4064_test.setBuildMode(mode);
        lc4064_test.install();
        _ = makeRunStep(b, lc4064_test, "lc4064_test", "run lc4064_test");

        const oe_mux = b.addExecutable("oe_mux", "src/oe_mux.zig");
        oe_mux.addPackage(sx);
        oe_mux.addPackage(temp_allocator);
        oe_mux.linkLibC();
        oe_mux.setTarget(target);
        oe_mux.setBuildMode(mode);
        oe_mux.install();
        _ = makeRunStep(b, oe_mux, "oe_mux", "run oe_mux");

        const orm = b.addExecutable("orm", "src/orm.zig");
        orm.addPackage(sx);
        orm.addPackage(temp_allocator);
        orm.linkLibC();
        orm.setTarget(target);
        orm.setBuildMode(mode);
        orm.install();
        _ = makeRunStep(b, orm, "orm", "run orm");

        const output_routing_mode = b.addExecutable("output_routing_mode", "src/output_routing_mode.zig");
        output_routing_mode.addPackage(sx);
        output_routing_mode.addPackage(temp_allocator);
        output_routing_mode.linkLibC();
        output_routing_mode.setTarget(target);
        output_routing_mode.setBuildMode(mode);
        output_routing_mode.install();
        _ = makeRunStep(b, output_routing_mode, "output_routing_mode", "run output_routing_mode");

        const powerup_state = b.addExecutable("powerup_state", "src/powerup_state.zig");
        powerup_state.addPackage(sx);
        powerup_state.addPackage(temp_allocator);
        powerup_state.linkLibC();
        powerup_state.setTarget(target);
        powerup_state.setBuildMode(mode);
        powerup_state.install();
        _ = makeRunStep(b, powerup_state, "powerup_state", "run powerup_state");

        const pt0_xor = b.addExecutable("pt0_xor", "src/pt0_xor.zig");
        pt0_xor.addPackage(sx);
        pt0_xor.addPackage(temp_allocator);
        pt0_xor.linkLibC();
        pt0_xor.setTarget(target);
        pt0_xor.setBuildMode(mode);
        pt0_xor.install();
        _ = makeRunStep(b, pt0_xor, "pt0_xor", "run pt0_xor");

        const pt2_reset = b.addExecutable("pt2_reset", "src/pt2_reset.zig");
        pt2_reset.addPackage(sx);
        pt2_reset.addPackage(temp_allocator);
        pt2_reset.linkLibC();
        pt2_reset.setTarget(target);
        pt2_reset.setBuildMode(mode);
        pt2_reset.install();
        _ = makeRunStep(b, pt2_reset, "pt2_reset", "run pt2_reset");

        const pt3_reset = b.addExecutable("pt3_reset", "src/pt3_reset.zig");
        pt3_reset.addPackage(sx);
        pt3_reset.addPackage(temp_allocator);
        pt3_reset.linkLibC();
        pt3_reset.setTarget(target);
        pt3_reset.setBuildMode(mode);
        pt3_reset.install();
        _ = makeRunStep(b, pt3_reset, "pt3_reset", "run pt3_reset");

        const pt4_oe = b.addExecutable("pt4_oe", "src/pt4_oe.zig");
        pt4_oe.addPackage(sx);
        pt4_oe.addPackage(temp_allocator);
        pt4_oe.linkLibC();
        pt4_oe.setTarget(target);
        pt4_oe.setBuildMode(mode);
        pt4_oe.install();
        _ = makeRunStep(b, pt4_oe, "pt4_oe", "run pt4_oe");

        const pterms = b.addExecutable("pterms", "src/pterms.zig");
        pterms.addPackage(sx);
        pterms.addPackage(temp_allocator);
        pterms.linkLibC();
        pterms.setTarget(target);
        pterms.setBuildMode(mode);
        pterms.install();
        _ = makeRunStep(b, pterms, "pterms", "run pterms");

        const pull = b.addExecutable("pull", "src/pull.zig");
        pull.addPackage(sx);
        pull.addPackage(temp_allocator);
        pull.linkLibC();
        pull.setTarget(target);
        pull.setBuildMode(mode);
        pull.install();
        _ = makeRunStep(b, pull, "pull", "run pull");

        const reg_type = b.addExecutable("reg_type", "src/reg_type.zig");
        reg_type.addPackage(sx);
        reg_type.addPackage(temp_allocator);
        reg_type.linkLibC();
        reg_type.setTarget(target);
        reg_type.setBuildMode(mode);
        reg_type.install();
        _ = makeRunStep(b, reg_type, "reg_type", "run reg_type");

        const slew = b.addExecutable("slew", "src/slew.zig");
        slew.addPackage(sx);
        slew.addPackage(temp_allocator);
        slew.linkLibC();
        slew.setTarget(target);
        slew.setBuildMode(mode);
        slew.install();
        _ = makeRunStep(b, slew, "slew", "run slew");

        const threshold = b.addExecutable("threshold", "src/threshold.zig");
        threshold.addPackage(sx);
        threshold.addPackage(temp_allocator);
        threshold.linkLibC();
        threshold.setTarget(target);
        threshold.setBuildMode(mode);
        threshold.install();
        _ = makeRunStep(b, threshold, "threshold", "run threshold");

        const wide_steering = b.addExecutable("wide_steering", "src/wide_steering.zig");
        wide_steering.addPackage(sx);
        wide_steering.addPackage(temp_allocator);
        wide_steering.linkLibC();
        wide_steering.setTarget(target);
        wide_steering.setBuildMode(mode);
        wide_steering.install();
        _ = makeRunStep(b, wide_steering, "wide_steering", "run wide_steering");

        const zerohold = b.addExecutable("zerohold", "src/zerohold.zig");
        zerohold.addPackage(sx);
        zerohold.addPackage(temp_allocator);
        zerohold.linkLibC();
        zerohold.setTarget(target);
        zerohold.setBuildMode(mode);
        zerohold.install();
        _ = makeRunStep(b, zerohold, "zerohold", "run zerohold");

        //[[ ######################### END OF GENERATED CODE ######################### ]]
    }
}

fn makeRunStep(b: *std.build.Builder, exe: *std.build.LibExeObjStep, name: []const u8, desc: []const u8) *std.build.RunStep {
    var run = exe.run();
    run.step.dependOn(b.getInstallStep());
    b.step(name, desc).dependOn(&run.step);
    return run;
}
