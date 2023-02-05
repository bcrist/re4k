const std = @import("std");
const common = @import("common");
const jedec = @import("jedec");

const DeviceType = common.DeviceType;
const DeviceFamily = common.DeviceFamily;
const DevicePackage = common.DevicePackage;
const PinInfo = common.PinInfo;
const JedecData = jedec.JedecData;
const FuseRange = jedec.FuseRange;
const Fuse = jedec.Fuse;

pub const DeviceInfo = struct {
    device: DeviceType,
    family: DeviceFamily,
    package: DevicePackage,
    num_glbs: usize,
    num_mcs: usize,
    num_mcs_per_glb: usize,
    num_gis_per_glb: usize,
    gi_mux_size: usize,
    jedec_dimensions: FuseRange,
    all_pins: []const PinInfo,
    oe_pins: []const PinInfo,
    clock_pins: []const PinInfo,
    input_pins: []const PinInfo,

    pub fn init(device: DeviceType) DeviceInfo {
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
                    .all_pins = &D.all_pins,
                    .oe_pins = &D.oe_pins,
                    .clock_pins = &D.clock_pins,
                    .input_pins = &D.input_pins,
                };
            }
        }
    }

    pub fn getPackageName(self: DeviceInfo) []const u8 {
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

    pub fn getFitterName(self: DeviceInfo) []const u8 {
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
    pub fn getRoutingRange(self: DeviceInfo) FuseRange {
        return FuseRange.init(self.jedec_dimensions.width(), self.num_gis_per_glb * 2);
    }

    // The range at the end of the fusemap containing MC, I/O cell, and misc option fuses; row 72+
    pub fn getOptionsRange(self: DeviceInfo) FuseRange {
        return FuseRange.between(
            Fuse.init(self.num_gis_per_glb * 2, 0),
            Fuse.init(self.jedec_dimensions.height() - 1, self.jedec_dimensions.width() - 1),
        );
    }

    pub fn getRowRange(self: DeviceInfo, min_row: usize, max_row: usize) FuseRange {
        const dim = self.jedec_dimensions;
        return FuseRange.between(
            Fuse.init(min_row, 0),
            Fuse.init(max_row, dim.width() - 1),
        );
    }

    pub fn getColumnRange(self: DeviceInfo, min_col: usize, max_col: usize) FuseRange {
        const dim = self.jedec_dimensions;
        return FuseRange.between(
            Fuse.init(0, min_col),
            Fuse.init(dim.height() - 1, max_col),
        );
    }

    // TODO move this to LC4k?
    pub fn getGIRange(self: DeviceInfo, glb: usize, gi: usize) FuseRange {
        return switch (self.num_glbs) {
            2 => switch (glb) {
                0 => FuseRange.between(Fuse.init(gi*2, 86), Fuse.init(gi*2 + 1, 88)),
                1 => FuseRange.between(Fuse.init(gi*2,  0), Fuse.init(gi*2 + 1,  2)),
                else => unreachable,
            },
            4 => switch (self.device) {
                .LC4064x_TQFP44, .LC4064x_TQFP48 => switch (glb) {
                    0 => FuseRange.between(Fuse.init(gi*2, 264), Fuse.init(gi*2 + 1, 268)),
                    1 => FuseRange.between(Fuse.init(gi*2, 176), Fuse.init(gi*2 + 1, 180)),
                    2 => FuseRange.between(Fuse.init(gi*2,  88), Fuse.init(gi*2 + 1,  92)),
                    3 => FuseRange.between(Fuse.init(gi*2,   0), Fuse.init(gi*2 + 1,   4)),
                    else => unreachable,
                },
                else => switch (glb) {
                    0 => FuseRange.between(Fuse.init(gi*2, 267), Fuse.init(gi*2 + 1, 272)),
                    1 => FuseRange.between(Fuse.init(gi*2, 178), Fuse.init(gi*2 + 1, 183)),
                    2 => FuseRange.between(Fuse.init(gi*2,  89), Fuse.init(gi*2 + 1,  94)),
                    3 => FuseRange.between(Fuse.init(gi*2,   0), Fuse.init(gi*2 + 1,   5)),
                    else => unreachable,
                },
            },
            8 => switch (glb) {
                0 => FuseRange.between(Fuse.init(gi*2,   555), Fuse.init(gi*2,   573)),
                1 => FuseRange.between(Fuse.init(gi*2+1, 555), Fuse.init(gi*2+1, 573)),
                2 => FuseRange.between(Fuse.init(gi*2+1, 370), Fuse.init(gi*2+1, 388)),
                3 => FuseRange.between(Fuse.init(gi*2,   370), Fuse.init(gi*2,   388)),
                4 => FuseRange.between(Fuse.init(gi*2,   185), Fuse.init(gi*2,   203)),
                5 => FuseRange.between(Fuse.init(gi*2+1, 185), Fuse.init(gi*2+1, 203)),
                6 => FuseRange.between(Fuse.init(gi*2+1,   0), Fuse.init(gi*2+1,  18)),
                7 => FuseRange.between(Fuse.init(gi*2,     0), Fuse.init(gi*2,    18)),
                else => unreachable,
            },
            else => unreachable,
        };
    }

    pub fn getBasePartNumber(self: DeviceInfo) []const u8 {
        return switch (self.num_glbs) {
            2 => "LC4032",
            4 => "LC4064",
            8 => "LC4128",
            else => "LC4xxx",
        };
    }

    pub fn getPartNumberSuffix(self: DeviceInfo) []const u8 {
        return switch (self.family) {
            .low_power => "V",
            .zero_power => "ZC",
            .zero_power_enhanced => "ZE",
        };
    }

    pub fn writePartNumber(self: DeviceInfo, writer: anytype, family_code: ?[]const u8, speed_code: ?[]const u8, temp_code: ?[]const u8) !void {
        const family_suffix = family_code orelse self.getPartNumberSuffix();

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

        try writer.print("{s}{s}-{s}{s}", .{ self.getBasePartNumber(), family_suffix, speed, package_code });

        if (self.family == .zero_power_enhanced) {
            try writer.writeByte('N');
        }

        try writer.print("{}", .{ self.all_pins.len });

        try writer.writeAll(temp);
    }

    pub fn getPin(self: DeviceInfo, id: []const u8) ?PinInfo {
        for (self.all_pins) |pin| {
            if (std.mem.eql(u8, id, pin.id)) {
                return pin;
            }
        }
        return null;
    }

    pub fn getIOPin(self: DeviceInfo, mcref: common.MacrocellRef) ?PinInfo {
        for (self.all_pins) |pin| {
            switch (pin.func) {
                .io, .io_oe0, .io_oe1 => |mc| if (pin.glb.? == mcref.glb and mc == mcref.mc) return pin,
                else => {}
            }
        }
        return null;
    }

    pub fn getClockPin(self: DeviceInfo, clk_index: common.ClockIndex) ?PinInfo {
        for (self.clock_pins) |pin| {
            switch (pin.func) {
                .clock => |i| if (clk_index == i) return pin,
                else => {}
            }
        }
        return null;
    }

};
