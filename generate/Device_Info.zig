device: Device_Type,
family: Device_Family,
package: Device_Package,
num_glbs: usize,
num_mcs: usize,
num_mcs_per_glb: usize,
num_gis_per_glb: usize,
gi_mux_size: usize,
jedec_dimensions: Fuse_Range,
all_pins: []const Pin_Info,
oe_pins: []const Pin_Info,
clock_pins: []const Pin_Info,
input_pins: []const Pin_Info,

pub fn init(device: Device_Type) Device_Info {
    switch (device) {
        inline else => |d| {
            const D = d.get();
            return .{
                .device = d,
                .family = D.family,
                .package = D.package,
                .num_glbs = D.num_glbs,
                .num_mcs = D.num_mcs,
                .num_mcs_per_glb = D.num_mcs_per_glb,
                .num_gis_per_glb = D.num_gis_per_glb,
                .gi_mux_size = D.gi_mux_size,
                .jedec_dimensions = D.jedec_dimensions,
                .all_pins = pin_infos(D.all_pins),
                .oe_pins = pin_infos(D.oe_pins),
                .clock_pins = pin_infos(D.clock_pins),
                .input_pins = pin_infos(D.input_pins),
            };
        }
    }
}

fn pin_infos(comptime pins: anytype) []const Pin_Info {
    comptime var infos: [pins.len]Pin_Info = undefined;
    inline for (pins, &infos) |in, *out| {
        out.* = in.info;
    }
    const final_infos: [pins.len]Pin_Info = infos;
    return &final_infos;
}

pub fn get_package_name(self: Device_Info) []const u8 {
    return switch (self.package) {
        .TQFP44 => "44TQFP",
        .TQFP48 => "48TQFP",
        .csBGA56 => "56csBGA",
        .csBGA64 => "64csBGA",
        .ucBGA64 => "64ucBGA",
        .TQFP100 => "100TQFP",
        .TQFP128 => "128TQFP",
        .csBGA132 => "132csBGA",
        .ucBGA132 => "132ucBGA",
        .TQFP144 => "144TQFP",
        .csBGA144 => "144csBGA",
    };
}

pub fn get_fitter_name(self: Device_Info) []const u8 {
    return switch (self.device) {
        .LC4032x_TQFP44    => "M4S_32_30",
        .LC4032x_TQFP48    => "M4S_32_32",
        .LC4032ZC_TQFP48   => "M4Z_32_32",
        .LC4032ZC_csBGA56  => "M4Z_32_32S",
        .LC4032ZE_TQFP48   => "M4E_32_32",
        .LC4032ZE_csBGA64  => "M4E_32_32S",
        .LC4064x_TQFP44    => "M4S_64_30",
        .LC4064x_TQFP48    => "M4S_64_32",
        .LC4064ZC_TQFP48   => "M4Z_64_32",
        .LC4064ZE_TQFP48   => "M4E_64_32",
        .LC4064ZC_csBGA56  => "M4Z_64_32S",
        .LC4064ZE_csBGA64  => "M4E_64_48S",
        .LC4064ZE_ucBGA64  => "M4E_64_48U",
        .LC4064x_TQFP100   => "M4S_64_64",
        .LC4064ZC_TQFP100  => "M4Z_64_64",
        .LC4064ZE_TQFP100  => "M4E_64_64",
        .LC4064ZC_csBGA132 => "M4Z_64_64S",
        .LC4064ZE_csBGA144 => "M4E_64_64S",
        .LC4128x_TQFP100   => "M4S_128_64",
        .LC4128ZC_TQFP100  => "M4Z_128_64",
        .LC4128ZE_TQFP100  => "M4E_128_64",
        .LC4128x_TQFP128   => "M4S_128_92",
        .LC4128V_TQFP144   => "M4S_128_96",
        .LC4128ZC_csBGA132 => "M4Z_128_96S",
        .LC4128ZE_TQFP144  => "M4E_128_96",
        .LC4128ZE_csBGA144 => "M4E_128_96S",
        .LC4128ZE_ucBGA132 => "M4E_128_96U",
    };
}

// The range at the beginning of the fusemap containing PT and GLB input mux fuses; row 0-71
pub fn get_routing_range(self: Device_Info) Fuse_Range {
    return Fuse_Range.init_from_dimensions(self.jedec_dimensions.width(), self.num_gis_per_glb * 2);
}

// The range at the end of the fusemap containing MC, I/O cell, and misc option fuses; row 72+
pub fn get_options_range(self: Device_Info) Fuse_Range {
    return Fuse_Range.between(
        Fuse.init(self.num_gis_per_glb * 2, 0),
        Fuse.init(self.jedec_dimensions.height() - 1, self.jedec_dimensions.width() - 1),
    );
}

pub fn get_row_range(self: Device_Info, min_row: usize, max_row: usize) Fuse_Range {
    const dim = self.jedec_dimensions;
    return Fuse_Range.between(
        Fuse.init(min_row, 0),
        Fuse.init(max_row, dim.width() - 1),
    );
}

pub fn get_column_range(self: Device_Info, min_col: usize, max_col: usize) Fuse_Range {
    const dim = self.jedec_dimensions;
    return Fuse_Range.between(
        Fuse.init(0, min_col),
        Fuse.init(dim.height() - 1, max_col),
    );
}

// TODO move this to LC4k?
pub fn get_gi_range(self: Device_Info, glb: usize, gi: usize) Fuse_Range {
    return switch (self.num_glbs) {
        2 => switch (glb) {
            0 => Fuse_Range.between(Fuse.init(gi*2, 86), Fuse.init(gi*2 + 1, 88)),
            1 => Fuse_Range.between(Fuse.init(gi*2,  0), Fuse.init(gi*2 + 1,  2)),
            else => unreachable,
        },
        4 => switch (self.device) {
            .LC4064x_TQFP44, .LC4064x_TQFP48 => switch (glb) {
                0 => Fuse_Range.between(Fuse.init(gi*2, 264), Fuse.init(gi*2 + 1, 268)),
                1 => Fuse_Range.between(Fuse.init(gi*2, 176), Fuse.init(gi*2 + 1, 180)),
                2 => Fuse_Range.between(Fuse.init(gi*2,  88), Fuse.init(gi*2 + 1,  92)),
                3 => Fuse_Range.between(Fuse.init(gi*2,   0), Fuse.init(gi*2 + 1,   4)),
                else => unreachable,
            },
            else => switch (glb) {
                0 => Fuse_Range.between(Fuse.init(gi*2, 267), Fuse.init(gi*2 + 1, 272)),
                1 => Fuse_Range.between(Fuse.init(gi*2, 178), Fuse.init(gi*2 + 1, 183)),
                2 => Fuse_Range.between(Fuse.init(gi*2,  89), Fuse.init(gi*2 + 1,  94)),
                3 => Fuse_Range.between(Fuse.init(gi*2,   0), Fuse.init(gi*2 + 1,   5)),
                else => unreachable,
            },
        },
        8 => switch (glb) {
            0 => Fuse_Range.between(Fuse.init(gi*2,   555), Fuse.init(gi*2,   573)),
            1 => Fuse_Range.between(Fuse.init(gi*2+1, 555), Fuse.init(gi*2+1, 573)),
            2 => Fuse_Range.between(Fuse.init(gi*2+1, 370), Fuse.init(gi*2+1, 388)),
            3 => Fuse_Range.between(Fuse.init(gi*2,   370), Fuse.init(gi*2,   388)),
            4 => Fuse_Range.between(Fuse.init(gi*2,   185), Fuse.init(gi*2,   203)),
            5 => Fuse_Range.between(Fuse.init(gi*2+1, 185), Fuse.init(gi*2+1, 203)),
            6 => Fuse_Range.between(Fuse.init(gi*2+1,   0), Fuse.init(gi*2+1,  18)),
            7 => Fuse_Range.between(Fuse.init(gi*2,     0), Fuse.init(gi*2,    18)),
            else => unreachable,
        },
        else => unreachable,
    };
}

pub fn get_base_part_number(self: Device_Info) []const u8 {
    return switch (self.num_glbs) {
        2 => "LC4032",
        4 => "LC4064",
        8 => "LC4128",
        else => "LC4xxx",
    };
}

pub fn get_part_number_suffix(self: Device_Info) []const u8 {
    return switch (self.family) {
        .low_power => "V",
        .zero_power => "ZC",
        .zero_power_enhanced => "ZE",
    };
}

pub fn write_part_number(self: Device_Info, writer: anytype, family_code: ?[]const u8, speed_code: ?[]const u8, temp_code: ?[]const u8) !void {
    const family_suffix = family_code orelse self.get_part_number_suffix();

    const speed = speed_code orelse switch (self.family) {
        .zero_power_enhanced => "7",
        else => "75",
    };

    const temp = temp_code orelse "C";

    const package_code = switch (self.package) {
        .TQFP44, .TQFP48, .TQFP100, .TQFP128, .TQFP144 => "T",
        .csBGA56, .csBGA64, .csBGA132, .csBGA144 => "M",
        .ucBGA64, .ucBGA132 => "UM",
    };

    try writer.print("{s}{s}-{s}{s}", .{ self.get_base_part_number(), family_suffix, speed, package_code });

    if (self.family == .zero_power_enhanced) {
        try writer.writeByte('N');
    }

    try writer.print("{}", .{ self.all_pins.len });

    try writer.writeAll(temp);
}

pub fn get_pin(self: Device_Info, id: []const u8) ?Pin_Info {
    for (self.all_pins) |pin| {
        if (std.mem.eql(u8, id, pin.id)) {
            return pin;
        }
    }
    return null;
}

pub fn get_io_pin(self: Device_Info, mcref: lc4k.MC_Ref) ?Pin_Info {
    for (self.all_pins) |pin| {
        switch (pin.func) {
            .io, .io_oe0, .io_oe1 => |mc| if (pin.glb.? == mcref.glb and mc == mcref.mc) return pin,
            else => {}
        }
    }
    return null;
}

pub fn get_clock_pin(self: Device_Info, clk_index: lc4k.Clock_Index) ?Pin_Info {
    for (self.clock_pins) |pin| {
        switch (pin.func) {
            .clock => |i| if (clk_index == i) return pin,
            else => {}
        }
    }
    return null;
}

const Device_Info = @This();

const Device_Type = lc4k.Device_Type;
const Device_Family = lc4k.Device_Family;
const Device_Package = lc4k.Device_Package;
const Pin_Info = lc4k.Pin_Info;
const JEDEC_Data = lc4k.JEDEC_Data;
const Fuse_Range = lc4k.Fuse_Range;
const Fuse = lc4k.Fuse;

const lc4k = @import("lc4k");
const std = @import("std");