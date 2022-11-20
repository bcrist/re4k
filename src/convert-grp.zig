const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const jedec = @import("jedec.zig");
const devices = @import("devices.zig");
const Fuse = jedec.Fuse;
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const GlbInputSignal = toolchain.GlbInputSignal;
const FitResults = toolchain.FitResults;

pub fn main() void {
    helper.main(1);
}

var report_number: usize = 0;
fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, pin_index: u16) !FitResults {
    var design = Design.init(ta, dev);

    try design.pinAssignment( .{
        .signal = "in",
        .pin_index = pin_index,
    });
    try design.nodeAssignment( .{
        .signal = "out",
        .glb = 0,
        .mc = 6,
    });
    try design.addPT("in", "out");

    var results = try tc.runToolchain(design);
    try helper.logReport("convert_grp_{}", .{ report_number }, results);
    report_number += 1;
    try results.checkTerm();
    return results;
}

fn getFuseToPinMap(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType) !std.AutoHashMapUnmanaged(Fuse, u16) {
    // Route input-only pins for this device type, since we can't know which signals in the reference device they correspond to.
    var fuse_to_pin_map = std.AutoHashMapUnmanaged(Fuse, u16) {};

    var iter = devices.pins.InputIterator { .pins = dev.getPins() };
    while (iter.next()) |pin_info| {
        switch (pin_info) {
            .input => |info| {
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

                var results = try runToolchain(ta, tc, dev, info.pin_index);
                var fuses_set: usize = 0;
                var gi: u8 = 0;
                while (gi < 36) : (gi += 1) {
                    var fuse_iter = dev.getGIRange(0, gi).iterator();
                    while (fuse_iter.next()) |fuse| {
                        if (!results.jedec.isSet(fuse)) {
                            try fuse_to_pin_map.put(pa, fuse, info.pin_index);
                            fuses_set += 1;
                        }
                    }
                }

                std.debug.assert(fuses_set == 1);
            },
            else => {},
        }
    }

    return fuse_to_pin_map;
}


pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    var fuse_to_pin_map = try getFuseToPinMap(ta, pa, tc, dev);
    try tc.cleanTempDir();
    helper.resetTemp();

    var input_device: DeviceType = undefined;
    var fuse_to_signal_map = try helper.parseGRP(ta, pa, &input_device);
    std.debug.assert(input_device.getNumGlbs() == dev.getNumGlbs());
    std.debug.assert(input_device.getJedecWidth() == dev.getJedecWidth());
    std.debug.assert(input_device.getJedecHeight() == dev.getJedecHeight());

    var signal_to_pin_map = std.AutoHashMap(GlbInputSignal, u16).init(ta);
    try signal_to_pin_map.ensureTotalCapacity(fuse_to_pin_map.count());

    var entry_iter = fuse_to_signal_map.iterator();
    while (entry_iter.next()) |entry| {
        if (fuse_to_pin_map.get(entry.key_ptr.*)) |new_pin_index| {
            try signal_to_pin_map.put(entry.value_ptr.*, new_pin_index);
        }
    }

    const unused_pin: u16 = 65535;

    var signal_iter = fuse_to_signal_map.valueIterator();
    while (signal_iter.next()) |signal| {
        if (signal_to_pin_map.get(signal.*)) |new_pin_index| {
            signal.* = GlbInputSignal { .pin = new_pin_index };
        } else switch (signal.*) {
            .fb => {},
            .pin => |pin_index| {
                var new_pin_index: u16 = unused_pin;
                switch (input_device.getPins()[pin_index]) {
                    .clock_input => |info| {
                        if (dev.getClockPin(info.clock_index)) |new_info| {
                            new_pin_index = new_info.pin_index;
                        }
                    },
                    .input_output => |info| {
                        if (dev.getIOPin(info.glb, info.mc)) |new_info| {
                            new_pin_index = new_info.pin_index;
                        }
                    },
                    else => {},
                }
                signal.* = GlbInputSignal { .pin = new_pin_index };
            },
        }
    }

    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("global_routing_pool");

    var glb: u8 = 0;
    while (glb < dev.getNumGlbs()) : (glb += 1) {
        try writer.expression("glb");
        try writer.printRaw("{}", .{ glb });
        try writer.expression("name");
        try writer.printRaw("{s}", .{ devices.getGlbName(glb) });
        try writer.close();
        writer.setCompact(false);

        var gi: u8 = 0;
        while (gi < 36) : (gi += 1) {
            try writer.expression("gi");
            try writer.printRaw("{}", .{ gi });
            writer.setCompact(false);

            var fuse_iter = dev.getGIRange(glb, gi).iterator();
            while (fuse_iter.next()) |fuse| {
                var signal = fuse_to_signal_map.get(fuse).?;

                try writer.expression("fuse");
                try writer.printRaw("{} {}", .{ fuse.row, fuse.col });

                switch (signal) {
                    .fb => |mcref| {
                        try writer.expression("glb");
                        try writer.printRaw("{}", .{ mcref.glb });
                        try writer.expression("name");
                        try writer.printRaw("{s}", .{ devices.getGlbName(mcref.glb) });
                        try writer.close(); // name
                        try writer.close(); // glb
                        try writer.expression("mc");
                        try writer.printRaw("{}", .{ mcref.mc });
                        try writer.close(); // mc
                    },
                    .pin => |pin_index| {
                        if (pin_index == unused_pin) {
                            try writer.expression("unused");
                            try writer.close(); // unused
                        } else {
                            try writer.expression("pin");
                            try writer.printRaw("{s}", .{ dev.getPins()[pin_index].pin_number() });
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
