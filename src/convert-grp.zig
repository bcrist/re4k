const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const jedec = lc4k.jedec;
const device_info = @import("device_info.zig");
const Fuse = jedec.Fuse;
const DeviceInfo = device_info.DeviceInfo;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const GlbInputSignal = toolchain.GlbInputSignal;
const FitResults = toolchain.FitResults;

pub fn main() void {
    helper.main();
}

var report_number: usize = 0;
fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, pin: []const u8) !FitResults {
    var design = Design.init(ta, dev);

    try design.pinAssignment( .{
        .signal = "in",
        .pin = pin,
    });
    try design.nodeAssignment( .{
        .signal = "out",
        .glb = 0,
        .mc = 6,
    });
    try design.addPT("in", "out");

    var results = try tc.runToolchain(design);
    try helper.logResults(dev.device, "convert_grp_{}", .{ report_number }, results);
    report_number += 1;
    try results.checkTerm();
    return results;
}

fn getFuseToPinMap(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo) !std.AutoHashMapUnmanaged(Fuse, []const u8) {
    // Route input-only pins for this device type, since we can't know which signals in the reference device they correspond to.
    var fuse_to_pin_map = std.AutoHashMapUnmanaged(Fuse, []const u8) {};

    for (dev.input_pins) |pin| {
        try tc.cleanTempDir();
        helper.resetTemp();

        // We could try to run the toolchain with multiple/all input signals routed simultaneously to speed things up,
        // but then we'd have to rely on the GI mapping provided in the report to disambiguate which fuse corresponds
        // to which signal.  And there are several fitter bugs that cause problems with that:
        //    - For LC4064ZC_csBGA56; the second column (GIs 18-35) doesn't always show up.
        //    - For some devices, "input only" pins are incorrectly listed as sourced from a macrocell feedback signal.
        //      e.g. for LC4128ZC_TQFP100, pin 12's source is listed as "mc B-11", but the GI mux fuse that's set is
        //      one of the ones corresponding to pin 16 in LC4128V_TQFP144; which is MC B14 and ORP B^11 in that device.
        //      So it seems the fitter is writing the I/O cell's ID in this case, rather than the actual pin number.
        // There's not that many input-only pins to test, so just doing them one at a time avoids these issues.

        var results = try runToolchain(ta, tc, dev, pin.id);
        var fuses_set: usize = 0;
        var gi: u8 = 0;
        while (gi < 36) : (gi += 1) {
            var fuse_iter = dev.getGIRange(0, gi).iterator();
            while (fuse_iter.next()) |fuse| {
                if (!results.jedec.isSet(fuse)) {
                    try fuse_to_pin_map.put(pa, fuse, pin.id);
                    fuses_set += 1;
                }
            }
        }

        std.debug.assert(fuses_set == 1);
    }

    return fuse_to_pin_map;
}

const SignalRenaming = struct {
    old: GlbInputSignal,
    new: []const u8,
};


pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer) !void {
    var fuse_to_pin_map = try getFuseToPinMap(ta, pa, tc, dev);
    try tc.cleanTempDir();
    helper.resetTemp();

    var input_dev: DeviceInfo = undefined;
    var fuse_to_signal_map = try helper.parseGRP(ta, pa, &input_dev);
    std.debug.assert(input_dev.num_glbs == dev.num_glbs);
    std.debug.assert(input_dev.jedec_dimensions.eql(dev.jedec_dimensions));

    var renaming = try std.ArrayList(SignalRenaming).initCapacity(ta, fuse_to_pin_map.count());

    var entry_iter = fuse_to_pin_map.iterator();
    while (entry_iter.next()) |entry| {
        if (fuse_to_signal_map.get(entry.key_ptr.*)) |old| {
            try renaming.append(.{
                .old = old,
                .new = entry.value_ptr.*,
            });
        }
    }

    var signal_iter = fuse_to_signal_map.valueIterator();
    while (signal_iter.next()) |signal| {
        for (renaming.items) |rename| {
            if (rename.old.eql(signal.*)) {
                signal.* = GlbInputSignal { .pin = rename.new };
                break;
            }
        } else switch (signal.*) {
            .fb => {},
            .pin => |old_id| {
                const old_pin = input_dev.getPin(old_id).?;
                var new_id: []const u8 = "";
                switch (old_pin.func) {
                    .clock => |clk_index| {
                        if (dev.getClockPin(clk_index)) |new_pin| {
                            new_id = new_pin.id;
                        }
                    },
                    .io, .io_oe0, .io_oe1 => {
                        if (dev.getIOPin(old_pin.mcRef().?)) |new_pin| {
                            new_id = new_pin.id;
                        }
                    },
                    else => {},
                }
                signal.* = GlbInputSignal { .pin = new_id };
            },
        }
    }

    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("global_routing_pool");

    var glb: u8 = 0;
    while (glb < dev.num_glbs) : (glb += 1) {
        try helper.writeGlb(writer, glb);

        var gi: u8 = 0;
        while (gi < 36) : (gi += 1) {
            try writer.expression("gi");
            try writer.int(gi, 10);
            writer.set_compact(false);

            var fuse_iter = dev.getGIRange(glb, gi).iterator();
            while (fuse_iter.next()) |fuse| {
                const signal = fuse_to_signal_map.get(fuse).?;

                try writer.expression("fuse");
                try writer.int(fuse.row, 10);
                try writer.int(fuse.col, 10);

                switch (signal) {
                    .fb => |mcref| {
                        try helper.writeGlb(writer, mcref.glb);
                        writer.set_compact(true);
                        try writer.close();
                        try helper.writeMc(writer, mcref.mc);
                        try writer.close();
                    },
                    .pin => |id| {
                        if (id.len == 0) {
                            try writer.expression("unused");
                            try writer.close(); // unused
                        } else {
                            try helper.writePin(writer, dev.getPin(id).?);
                            try writer.close(); // pin
                        }
                    },
                }
                try writer.close(); // fuse
            }
            try writer.close(); // gi
        }
        try writer.close(); // glb
    }
    try writer.done();
}
