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
        },
    } else {
        //[[!! include 'build_zig' !! 387 ]]
        //[[ ################# !! GENERATED CODE -- DO NOT MODIFY !! ################# ]]
        const common = Pkg {
            .name = "common",
            .source = .{ .path = "pkg/lc4k/src/common.zig" },
        };
        const jed_file = Pkg {
            .name = "jed_file",
            .source = .{ .path = "pkg/lc4k/src/jed_file.zig" },
        };
        const jedec = Pkg {
            .name = "jedec",
            .source = .{ .path = "pkg/lc4k/src/jedec.zig" },
        };
        const sx = Pkg {
            .name = "sx",
            .source = .{ .path = "pkg/sx/sx.zig" },
        };
        const temp_allocator = Pkg {
            .name = "temp_allocator",
            .source = .{ .path = "pkg/tempallocator/temp_allocator.zig" },
        };

        const async_source = b.addExecutable("async_source", "src/async_source.zig");
        async_source.addPackage(common);
        async_source.addPackage(jed_file);
        async_source.addPackage(jedec);
        async_source.addPackage(sx);
        async_source.addPackage(temp_allocator);
        async_source.setTarget(target);
        async_source.setBuildMode(mode);
        async_source.install();
        _ = makeRunStep(b, async_source, "async_source", "run async_source");

        const bclk_polarity = b.addExecutable("bclk_polarity", "src/bclk_polarity.zig");
        bclk_polarity.addPackage(common);
        bclk_polarity.addPackage(jed_file);
        bclk_polarity.addPackage(jedec);
        bclk_polarity.addPackage(sx);
        bclk_polarity.addPackage(temp_allocator);
        bclk_polarity.setTarget(target);
        bclk_polarity.setBuildMode(mode);
        bclk_polarity.install();
        _ = makeRunStep(b, bclk_polarity, "bclk_polarity", "run bclk_polarity");

        const ce_source = b.addExecutable("ce_source", "src/ce_source.zig");
        ce_source.addPackage(common);
        ce_source.addPackage(jed_file);
        ce_source.addPackage(jedec);
        ce_source.addPackage(sx);
        ce_source.addPackage(temp_allocator);
        ce_source.setTarget(target);
        ce_source.setBuildMode(mode);
        ce_source.install();
        _ = makeRunStep(b, ce_source, "ce_source", "run ce_source");

        const clock_source = b.addExecutable("clock_source", "src/clock_source.zig");
        clock_source.addPackage(common);
        clock_source.addPackage(jed_file);
        clock_source.addPackage(jedec);
        clock_source.addPackage(sx);
        clock_source.addPackage(temp_allocator);
        clock_source.setTarget(target);
        clock_source.setBuildMode(mode);
        clock_source.install();
        _ = makeRunStep(b, clock_source, "clock_source", "run clock_source");

        const cluster_routing = b.addExecutable("cluster_routing", "src/cluster_routing.zig");
        cluster_routing.addPackage(common);
        cluster_routing.addPackage(jed_file);
        cluster_routing.addPackage(jedec);
        cluster_routing.addPackage(sx);
        cluster_routing.addPackage(temp_allocator);
        cluster_routing.setTarget(target);
        cluster_routing.setBuildMode(mode);
        cluster_routing.install();
        _ = makeRunStep(b, cluster_routing, "cluster_routing", "run cluster_routing");

        const combine = b.addExecutable("combine", "src/combine.zig");
        combine.addPackage(common);
        combine.addPackage(jed_file);
        combine.addPackage(jedec);
        combine.addPackage(sx);
        combine.addPackage(temp_allocator);
        combine.setTarget(target);
        combine.setBuildMode(mode);
        combine.install();
        _ = makeRunStep(b, combine, "combine", "run combine");

        const convert_bclk_polarity = b.addExecutable("convert-bclk_polarity", "src/convert-bclk_polarity.zig");
        convert_bclk_polarity.addPackage(common);
        convert_bclk_polarity.addPackage(jed_file);
        convert_bclk_polarity.addPackage(jedec);
        convert_bclk_polarity.addPackage(sx);
        convert_bclk_polarity.addPackage(temp_allocator);
        convert_bclk_polarity.setTarget(target);
        convert_bclk_polarity.setBuildMode(mode);
        convert_bclk_polarity.install();
        _ = makeRunStep(b, convert_bclk_polarity, "convert-bclk_polarity", "run convert-bclk_polarity");

        const convert_grp = b.addExecutable("convert-grp", "src/convert-grp.zig");
        convert_grp.addPackage(common);
        convert_grp.addPackage(jed_file);
        convert_grp.addPackage(jedec);
        convert_grp.addPackage(sx);
        convert_grp.addPackage(temp_allocator);
        convert_grp.setTarget(target);
        convert_grp.setBuildMode(mode);
        convert_grp.install();
        _ = makeRunStep(b, convert_grp, "convert-grp", "run convert-grp");

        const drive = b.addExecutable("drive", "src/drive.zig");
        drive.addPackage(common);
        drive.addPackage(jed_file);
        drive.addPackage(jedec);
        drive.addPackage(sx);
        drive.addPackage(temp_allocator);
        drive.setTarget(target);
        drive.setBuildMode(mode);
        drive.install();
        _ = makeRunStep(b, drive, "drive", "run drive");

        const goes = b.addExecutable("goes", "src/goes.zig");
        goes.addPackage(common);
        goes.addPackage(jed_file);
        goes.addPackage(jedec);
        goes.addPackage(sx);
        goes.addPackage(temp_allocator);
        goes.setTarget(target);
        goes.setBuildMode(mode);
        goes.install();
        _ = makeRunStep(b, goes, "goes", "run goes");

        const grp = b.addExecutable("grp", "src/grp.zig");
        grp.addPackage(common);
        grp.addPackage(jed_file);
        grp.addPackage(jedec);
        grp.addPackage(sx);
        grp.addPackage(temp_allocator);
        grp.setTarget(target);
        grp.setBuildMode(mode);
        grp.install();
        _ = makeRunStep(b, grp, "grp", "run grp");

        const init_source = b.addExecutable("init_source", "src/init_source.zig");
        init_source.addPackage(common);
        init_source.addPackage(jed_file);
        init_source.addPackage(jedec);
        init_source.addPackage(sx);
        init_source.addPackage(temp_allocator);
        init_source.setTarget(target);
        init_source.setBuildMode(mode);
        init_source.install();
        _ = makeRunStep(b, init_source, "init_source", "run init_source");

        const init_state = b.addExecutable("init_state", "src/init_state.zig");
        init_state.addPackage(common);
        init_state.addPackage(jed_file);
        init_state.addPackage(jedec);
        init_state.addPackage(sx);
        init_state.addPackage(temp_allocator);
        init_state.setTarget(target);
        init_state.setBuildMode(mode);
        init_state.install();
        _ = makeRunStep(b, init_state, "init_state", "run init_state");

        const invert = b.addExecutable("invert", "src/invert.zig");
        invert.addPackage(common);
        invert.addPackage(jed_file);
        invert.addPackage(jedec);
        invert.addPackage(sx);
        invert.addPackage(temp_allocator);
        invert.setTarget(target);
        invert.setBuildMode(mode);
        invert.install();
        _ = makeRunStep(b, invert, "invert", "run invert");

        const lc4032_test = b.addExecutable("lc4032_test", "src/lc4032_test.zig");
        lc4032_test.addPackage(common);
        lc4032_test.addPackage(jed_file);
        lc4032_test.addPackage(jedec);
        lc4032_test.addPackage(sx);
        lc4032_test.addPackage(temp_allocator);
        lc4032_test.setTarget(target);
        lc4032_test.setBuildMode(mode);
        lc4032_test.install();
        _ = makeRunStep(b, lc4032_test, "lc4032_test", "run lc4032_test");

        const lc4064_test = b.addExecutable("lc4064_test", "src/lc4064_test.zig");
        lc4064_test.addPackage(common);
        lc4064_test.addPackage(jed_file);
        lc4064_test.addPackage(jedec);
        lc4064_test.addPackage(sx);
        lc4064_test.addPackage(temp_allocator);
        lc4064_test.setTarget(target);
        lc4064_test.setBuildMode(mode);
        lc4064_test.install();
        _ = makeRunStep(b, lc4064_test, "lc4064_test", "run lc4064_test");

        const oe_source = b.addExecutable("oe_source", "src/oe_source.zig");
        oe_source.addPackage(common);
        oe_source.addPackage(jed_file);
        oe_source.addPackage(jedec);
        oe_source.addPackage(sx);
        oe_source.addPackage(temp_allocator);
        oe_source.setTarget(target);
        oe_source.setBuildMode(mode);
        oe_source.install();
        _ = makeRunStep(b, oe_source, "oe_source", "run oe_source");

        const osctimer = b.addExecutable("osctimer", "src/osctimer.zig");
        osctimer.addPackage(common);
        osctimer.addPackage(jed_file);
        osctimer.addPackage(jedec);
        osctimer.addPackage(sx);
        osctimer.addPackage(temp_allocator);
        osctimer.setTarget(target);
        osctimer.setBuildMode(mode);
        osctimer.install();
        _ = makeRunStep(b, osctimer, "osctimer", "run osctimer");

        const output_routing = b.addExecutable("output_routing", "src/output_routing.zig");
        output_routing.addPackage(common);
        output_routing.addPackage(jed_file);
        output_routing.addPackage(jedec);
        output_routing.addPackage(sx);
        output_routing.addPackage(temp_allocator);
        output_routing.setTarget(target);
        output_routing.setBuildMode(mode);
        output_routing.install();
        _ = makeRunStep(b, output_routing, "output_routing", "run output_routing");

        const output_routing_mode = b.addExecutable("output_routing_mode", "src/output_routing_mode.zig");
        output_routing_mode.addPackage(common);
        output_routing_mode.addPackage(jed_file);
        output_routing_mode.addPackage(jedec);
        output_routing_mode.addPackage(sx);
        output_routing_mode.addPackage(temp_allocator);
        output_routing_mode.setTarget(target);
        output_routing_mode.setBuildMode(mode);
        output_routing_mode.install();
        _ = makeRunStep(b, output_routing_mode, "output_routing_mode", "run output_routing_mode");

        const power_guard = b.addExecutable("power_guard", "src/power_guard.zig");
        power_guard.addPackage(common);
        power_guard.addPackage(jed_file);
        power_guard.addPackage(jedec);
        power_guard.addPackage(sx);
        power_guard.addPackage(temp_allocator);
        power_guard.setTarget(target);
        power_guard.setBuildMode(mode);
        power_guard.install();
        _ = makeRunStep(b, power_guard, "power_guard", "run power_guard");

        const pt0_xor = b.addExecutable("pt0_xor", "src/pt0_xor.zig");
        pt0_xor.addPackage(common);
        pt0_xor.addPackage(jed_file);
        pt0_xor.addPackage(jedec);
        pt0_xor.addPackage(sx);
        pt0_xor.addPackage(temp_allocator);
        pt0_xor.setTarget(target);
        pt0_xor.setBuildMode(mode);
        pt0_xor.install();
        _ = makeRunStep(b, pt0_xor, "pt0_xor", "run pt0_xor");

        const pt4_oe = b.addExecutable("pt4_oe", "src/pt4_oe.zig");
        pt4_oe.addPackage(common);
        pt4_oe.addPackage(jed_file);
        pt4_oe.addPackage(jedec);
        pt4_oe.addPackage(sx);
        pt4_oe.addPackage(temp_allocator);
        pt4_oe.setTarget(target);
        pt4_oe.setBuildMode(mode);
        pt4_oe.install();
        _ = makeRunStep(b, pt4_oe, "pt4_oe", "run pt4_oe");

        const pterms = b.addExecutable("pterms", "src/pterms.zig");
        pterms.addPackage(common);
        pterms.addPackage(jed_file);
        pterms.addPackage(jedec);
        pterms.addPackage(sx);
        pterms.addPackage(temp_allocator);
        pterms.setTarget(target);
        pterms.setBuildMode(mode);
        pterms.install();
        _ = makeRunStep(b, pterms, "pterms", "run pterms");

        const pull = b.addExecutable("pull", "src/pull.zig");
        pull.addPackage(common);
        pull.addPackage(jed_file);
        pull.addPackage(jedec);
        pull.addPackage(sx);
        pull.addPackage(temp_allocator);
        pull.setTarget(target);
        pull.setBuildMode(mode);
        pull.install();
        _ = makeRunStep(b, pull, "pull", "run pull");

        const reg_type = b.addExecutable("reg_type", "src/reg_type.zig");
        reg_type.addPackage(common);
        reg_type.addPackage(jed_file);
        reg_type.addPackage(jedec);
        reg_type.addPackage(sx);
        reg_type.addPackage(temp_allocator);
        reg_type.setTarget(target);
        reg_type.setBuildMode(mode);
        reg_type.install();
        _ = makeRunStep(b, reg_type, "reg_type", "run reg_type");

        const shared_pt_clk_polarity = b.addExecutable("shared_pt_clk_polarity", "src/shared_pt_clk_polarity.zig");
        shared_pt_clk_polarity.addPackage(common);
        shared_pt_clk_polarity.addPackage(jed_file);
        shared_pt_clk_polarity.addPackage(jedec);
        shared_pt_clk_polarity.addPackage(sx);
        shared_pt_clk_polarity.addPackage(temp_allocator);
        shared_pt_clk_polarity.setTarget(target);
        shared_pt_clk_polarity.setBuildMode(mode);
        shared_pt_clk_polarity.install();
        _ = makeRunStep(b, shared_pt_clk_polarity, "shared_pt_clk_polarity", "run shared_pt_clk_polarity");

        const shared_pt_init_polarity = b.addExecutable("shared_pt_init_polarity", "src/shared_pt_init_polarity.zig");
        shared_pt_init_polarity.addPackage(common);
        shared_pt_init_polarity.addPackage(jed_file);
        shared_pt_init_polarity.addPackage(jedec);
        shared_pt_init_polarity.addPackage(sx);
        shared_pt_init_polarity.addPackage(temp_allocator);
        shared_pt_init_polarity.setTarget(target);
        shared_pt_init_polarity.setBuildMode(mode);
        shared_pt_init_polarity.install();
        _ = makeRunStep(b, shared_pt_init_polarity, "shared_pt_init_polarity", "run shared_pt_init_polarity");

        const slew = b.addExecutable("slew", "src/slew.zig");
        slew.addPackage(common);
        slew.addPackage(jed_file);
        slew.addPackage(jedec);
        slew.addPackage(sx);
        slew.addPackage(temp_allocator);
        slew.setTarget(target);
        slew.setBuildMode(mode);
        slew.install();
        _ = makeRunStep(b, slew, "slew", "run slew");

        const threshold = b.addExecutable("threshold", "src/threshold.zig");
        threshold.addPackage(common);
        threshold.addPackage(jed_file);
        threshold.addPackage(jedec);
        threshold.addPackage(sx);
        threshold.addPackage(temp_allocator);
        threshold.setTarget(target);
        threshold.setBuildMode(mode);
        threshold.install();
        _ = makeRunStep(b, threshold, "threshold", "run threshold");

        const wide_routing = b.addExecutable("wide_routing", "src/wide_routing.zig");
        wide_routing.addPackage(common);
        wide_routing.addPackage(jed_file);
        wide_routing.addPackage(jedec);
        wide_routing.addPackage(sx);
        wide_routing.addPackage(temp_allocator);
        wide_routing.setTarget(target);
        wide_routing.setBuildMode(mode);
        wide_routing.install();
        _ = makeRunStep(b, wide_routing, "wide_routing", "run wide_routing");

        const xor = b.addExecutable("xor", "src/xor.zig");
        xor.addPackage(common);
        xor.addPackage(jed_file);
        xor.addPackage(jedec);
        xor.addPackage(sx);
        xor.addPackage(temp_allocator);
        xor.setTarget(target);
        xor.setBuildMode(mode);
        xor.install();
        _ = makeRunStep(b, xor, "xor", "run xor");

        const zerohold = b.addExecutable("zerohold", "src/zerohold.zig");
        zerohold.addPackage(common);
        zerohold.addPackage(jed_file);
        zerohold.addPackage(jedec);
        zerohold.addPackage(sx);
        zerohold.addPackage(temp_allocator);
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
