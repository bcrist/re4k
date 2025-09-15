const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const Device_Info = @import("Device_Info.zig");
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JEDEC_Data = lc4k.JEDEC_Data;
const Output_Iterator = helper.Output_Iterator;
const MC_Ref = lc4k.MC_Ref;
const Pin_Info = lc4k.Pin_Info;
const Fuse = lc4k.Fuse;
const Drive_Type = lc4k.Drive_Type;

pub const main = helper.main;

fn run_toolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, pin: Pin_Info, drive: Drive_Type) !toolchain.Fit_Results {
    var design = Design.init(ta, dev);
    try design.pin_assignment(.{
        .signal = "out",
        .pin = pin.id,
        .drive = drive,
    });
    try design.add_pt("in", "out");

    var results = try tc.run_toolchain(design);
    try helper.log_results(dev.device, "drive_pin_{s}", .{ pin.id }, results);
    try results.check_term();
    return results;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    var maybe_fallback_fuses: ?std.AutoHashMap(MC_Ref, []const helper.Fuse_And_Value) = null;
    if (helper.get_input_file("drive.sx")) |_| {
        maybe_fallback_fuses = try helper.parse_fuses_for_output_pins(ta, pa, "drive.sx", "drive_type", null);
    }

    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("drive_type");

    var default_pp: ?u1 = null;
    var default_od: ?u1 = null;

    var pin_iter = Output_Iterator { .pins = dev.all_pins };
    while (pin_iter.next()) |pin| {
        if (maybe_fallback_fuses) |fallback_fuses| {
            if (std.mem.eql(u8, pin.id, "F8") or std.mem.eql(u8, pin.id, "E3")) {
                // These pins are connected to macrocells, but lpf4k thinks they're dedicated inputs, and won't allow them to be used as outputs.
                const mcref = MC_Ref.init(pin.glb.?, switch (pin.func) {
                    .io, .io_oe0, .io_oe1 => |mc| mc,
                    else => unreachable,
                });

                if (fallback_fuses.get(mcref)) |fuses| {
                    try helper.write_pin(writer, pin);
                    for (fuses) |fuse_and_value| {
                        try helper.write_fuse_opt_value(writer, fuse_and_value.fuse, fuse_and_value.value);
                    }
                    try writer.close();
                    continue;
                }
            }
        }

        try tc.clean_temp_dir();
        helper.reset_temp();

        const results_pp = try run_toolchain(ta, tc, dev, pin, .push_pull);
        const results_od = try run_toolchain(ta, tc, dev, pin, .open_drain);

        try helper.write_pin(writer, pin);

        var diff = try JEDEC_Data.init_diff(ta, results_pp.jedec, results_od.jedec);
        var diff_iter = diff.iterator(.{});
        if (diff_iter.next()) |fuse| {
            try helper.write_fuse(writer, fuse);

            const pp_value = results_pp.jedec.get(fuse);
            if (default_pp) |def| {
                if (pp_value != def) {
                    try helper.write_value(writer, pp_value, "push_pull");
                }
            } else {
                default_pp = pp_value;
            }

            const od_value = results_od.jedec.get(fuse);
            if (default_od) |def| {
                if (od_value != def) {
                    try helper.write_value(writer, od_value, "open_drain");
                }
            } else {
                default_od = od_value;
            }

        } else {
            try helper.err("Expected one drive fuse but found none!", .{}, dev, .{ .pin = pin.id });
            return error.Think;
        }

        if (diff_iter.next()) |_| {
            try helper.err("Expected one drive fuse but found multiple!", .{}, dev, .{ .pin = pin.id });
            return error.Think;
        }

        try writer.close();
    }

    if (default_pp) |def| {
        try helper.write_value(writer, def, "push_pull");
    }

    if (default_od) |def| {
        try helper.write_value(writer, def, "open_drain");
    }

    try writer.done();
}
