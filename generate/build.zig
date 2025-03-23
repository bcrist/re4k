const std = @import("std");

pub fn build(b: *std.Build) void {
    const ctx = .{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
        .lc4k = b.dependency("lc4k", .{}),
        .Temp_Allocator = b.dependency("Temp_Allocator", .{}),
        .sx = b.dependency("sx", .{}),
    };

    make_exe(b, ctx, "async_source");
    make_exe(b, ctx, "bclk_polarity");
    make_exe(b, ctx, "bus_maintenance");
    make_exe(b, ctx, "ce_source");
    make_exe(b, ctx, "clock_source");
    make_exe(b, ctx, "cluster_routing");
    make_exe(b, ctx, "combine");
    make_exe(b, ctx, "convert-bclk_polarity");
    make_exe(b, ctx, "convert-grp");
    make_exe(b, ctx, "drive");
    make_exe(b, ctx, "goes");
    make_exe(b, ctx, "grp");
    make_exe(b, ctx, "init_source");
    make_exe(b, ctx, "init_state");
    make_exe(b, ctx, "input_bypass");
    make_exe(b, ctx, "invert");
    make_exe(b, ctx, "mc_func");
    make_exe(b, ctx, "oe_source");
    make_exe(b, ctx, "osctimer");
    make_exe(b, ctx, "output_routing");
    make_exe(b, ctx, "output_routing_mode");
    make_exe(b, ctx, "power_guard");
    make_exe(b, ctx, "pt0_xor");
    make_exe(b, ctx, "pt4_oe");
    make_exe(b, ctx, "pterms");
    make_exe(b, ctx, "shared_pt_clk_polarity");
    make_exe(b, ctx, "shared_pt_init_polarity");
    make_exe(b, ctx, "slew");
    make_exe(b, ctx, "threshold");
    make_exe(b, ctx, "wide_routing");
    make_exe(b, ctx, "zerohold");
}

fn make_exe(b: *std.Build, ctx: anytype, comptime name: []const u8) void {
    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path(name ++ ".zig"),
        .target = ctx.target,
        .optimize = ctx.optimize,
    });
    exe.root_module.addImport("lc4k", ctx.lc4k.module("lc4k"));
    exe.root_module.addImport("sx", ctx.sx.module("sx"));
    exe.root_module.addImport("Temp_Allocator", ctx.Temp_Allocator.module("Temp_Allocator"));
    b.installArtifact(exe);
}
