const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const jedec = lc4k.jedec;
const device_info = @import("device_info.zig");
const DeviceInfo = device_info.DeviceInfo;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JedecData = jedec.JedecData;
const MacrocellRef = lc4k.MacrocellRef;

pub fn main() void {
    helper.main();
}

fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, pin: lc4k.PinInfo, offset: u3) !toolchain.FitResults {
    var design = Design.init(ta, dev);

    try design.pinAssignment(.{
        .signal = "in",
        .pin = dev.getClockPin(0).?.id,
    });
    try design.pinAssignment(.{
        .signal = "out",
        .pin = pin.id,
    });
    // making the main output registered should prevent the use of the ORM bypass,
    // except in the case where offset == 0.
    // We'll test the ORM bypass mux separately, for families that have it.
    // (see output_routing_mode.zig)
    try design.addPT("in", "out.D");

    const out_mc = (pin.mcRef().?.mc + offset) & 0xF;

    var mc: u8 = 0;
    while (mc < 16) : (mc += 1) {
        if (mc != out_mc) {
            const signal_d = try std.fmt.allocPrint(ta, "node{}.D", .{ mc });
            const signal = signal_d[0..signal_d.len-2];
            try design.nodeAssignment(.{
                .signal = signal,
                .glb = pin.glb.?,
                .mc = mc,
            });
            try design.addPT("in", signal_d);
        }
    }

    var results = try tc.runToolchain(design);
    try helper.logResults(dev.device, "orm_{s}_plus{}", .{ pin.id, offset }, results);
    try results.checkTerm();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer) !void {
    var maybe_fallback_fuses: ?std.AutoHashMap(MacrocellRef, []const helper.FuseAndValue) = null;
    if (helper.getInputFile("output_routing.sx")) |_| {
        maybe_fallback_fuses = try helper.parseFusesForOutputPins(ta, pa, "output_routing.sx", "output_routing", null);
    }

    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("output_routing");

    var pin_iter = helper.OutputIterator { .pins = dev.all_pins };
    while (pin_iter.next()) |pin| {
        if (maybe_fallback_fuses) |fallback_fuses| {
            if (std.mem.eql(u8, pin.id, "F8") or std.mem.eql(u8, pin.id, "E3")) {
                // These pins are connected to macrocells, but lpf4k thinks they're dedicated inputs, and won't allow them to be used as outputs.
                const mcref = MacrocellRef.init(pin.glb.?, switch (pin.func) {
                    .io, .io_oe0, .io_oe1 => |mc| mc,
                    else => unreachable,
                });

                if (fallback_fuses.get(mcref)) |fuses| {
                    try helper.writePin(writer, pin);
                    for (fuses) |fuse_and_value| {
                        try helper.writeFuseOptValue(writer, fuse_and_value.fuse, fuse_and_value.value);
                    }
                    try writer.close();
                    continue;
                }
            }
        }

        try tc.cleanTempDir();
        helper.resetTemp();

        const results_1 = try runToolchain(ta, tc, dev, pin, 1);
        const results_2 = try runToolchain(ta, tc, dev, pin, 2);
        const results_4 = try runToolchain(ta, tc, dev, pin, 4);

        var diff = try JedecData.initDiff(ta, results_1.jedec, results_2.jedec);
        diff.unionDiff(results_1.jedec, results_4.jedec);

        try helper.writePin(writer, pin);

        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            var value: u32 = 0;
            if (results_1.jedec.isSet(fuse)) {
                value += 1;
            }
            if (results_2.jedec.isSet(fuse)) {
                value += 2;
            }
            if (results_4.jedec.isSet(fuse)) {
                value += 4;
            }

            switch (value) {
                1, 2, 4 => {},
                else => {
                    try helper.err("Expected ORM fuse {}:{} to have a value of 1, 2, or 4, but found {}",
                        .{ fuse.row, fuse.col, value }, dev, .{ .pin = pin.id });
                },
            }

            try helper.writeFuseOptValue(writer, fuse, value);
        }

        if (diff.countSet() != 3) {
            try helper.err("Expected exactly 3 ORM fuses but found {}!", .{ diff.countSet() }, dev, .{ .pin = pin.id });
        }

        try writer.close();
    }

    try helper.writeValue(writer, 0, "from_mc");
    try helper.writeValue(writer, 1, "from_mc_plus_1");
    try helper.writeValue(writer, 2, "from_mc_plus_2");
    try helper.writeValue(writer, 3, "from_mc_plus_3");
    try helper.writeValue(writer, 4, "from_mc_plus_4");
    try helper.writeValue(writer, 5, "from_mc_plus_5");
    try helper.writeValue(writer, 6, "from_mc_plus_6");
    try helper.writeValue(writer, 7, "from_mc_plus_7");

    try writer.done();
}
