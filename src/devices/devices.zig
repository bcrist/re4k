const std = @import("std");
const device_pins = @import("device_pins.zig");

// Most data in this file (and the files imported here) comes from:
// "ispMACH 4000V/B/C/Z Family Data Sheet"
// "ispMACH 4000ZE Family Data Sheet"

//[[!! devices = {
//    'LC4032x_TQFP44',
//    'LC4032x_TQFP48',
//    'LC4032ZC_TQFP48',
//    'LC4032ZC_csBGA56',
//    'LC4032ZE_TQFP48',
//    'LC4032ZE_csBGA64',
//    'LC4064x_TQFP44',
//    'LC4064x_TQFP48',
//    'LC4064x_TQFP100',
//    'LC4064ZC_TQFP48',
//    'LC4064ZC_csBGA56',
//    'LC4064ZC_TQFP100',
//    'LC4064ZC_csBGA132',
//    'LC4064ZE_TQFP48',
//    'LC4064ZE_csBGA64',
//    'LC4064ZE_ucBGA64',
//    'LC4064ZE_TQFP100',
//    'LC4064ZE_csBGA144',
//    'LC4128x_TQFP100',
//    'LC4128x_TQFP128',
//    'LC4128V_TQFP144',
//    'LC4128ZC_TQFP100',
//    'LC4128ZC_csBGA132',
//    'LC4128ZE_TQFP100',
//    'LC4128ZE_TQFP144',
//    'LC4128ZE_ucBGA144',
//    'LC4128ZE_csBGA144',
//    'LC4256x_TQFP100',
//    'LC4256V_TQFP144',
//    'LC4256ZC_TQFP100',
//    'LC4256ZC_csBGA132',
//    'LC4256ZE_TQFP100',
//    'LC4256ZE_TQFP144',
//    'LC4256ZE_csBGA144',
// }
//
// for _, device in ipairs(devices) do
//     writeln('const ', device, ' = @import("', device, '.zig");')
// end
// !! 38 ]]
//[[ ################# !! GENERATED CODE -- DO NOT MODIFY !! ################# ]]
const LC4032x_TQFP44 = @import("LC4032x_TQFP44.zig");
const LC4032x_TQFP48 = @import("LC4032x_TQFP48.zig");
const LC4032ZC_TQFP48 = @import("LC4032ZC_TQFP48.zig");
const LC4032ZC_csBGA56 = @import("LC4032ZC_csBGA56.zig");
const LC4032ZE_TQFP48 = @import("LC4032ZE_TQFP48.zig");
const LC4032ZE_csBGA64 = @import("LC4032ZE_csBGA64.zig");
const LC4064x_TQFP44 = @import("LC4064x_TQFP44.zig");
const LC4064x_TQFP48 = @import("LC4064x_TQFP48.zig");
const LC4064x_TQFP100 = @import("LC4064x_TQFP100.zig");
const LC4064ZC_TQFP48 = @import("LC4064ZC_TQFP48.zig");
const LC4064ZC_csBGA56 = @import("LC4064ZC_csBGA56.zig");
const LC4064ZC_TQFP100 = @import("LC4064ZC_TQFP100.zig");
const LC4064ZC_csBGA132 = @import("LC4064ZC_csBGA132.zig");
const LC4064ZE_TQFP48 = @import("LC4064ZE_TQFP48.zig");
const LC4064ZE_csBGA64 = @import("LC4064ZE_csBGA64.zig");
const LC4064ZE_ucBGA64 = @import("LC4064ZE_ucBGA64.zig");
const LC4064ZE_TQFP100 = @import("LC4064ZE_TQFP100.zig");
const LC4064ZE_csBGA144 = @import("LC4064ZE_csBGA144.zig");
const LC4128x_TQFP100 = @import("LC4128x_TQFP100.zig");
const LC4128x_TQFP128 = @import("LC4128x_TQFP128.zig");
const LC4128V_TQFP144 = @import("LC4128V_TQFP144.zig");
const LC4128ZC_TQFP100 = @import("LC4128ZC_TQFP100.zig");
const LC4128ZC_csBGA132 = @import("LC4128ZC_csBGA132.zig");
const LC4128ZE_TQFP100 = @import("LC4128ZE_TQFP100.zig");
const LC4128ZE_TQFP144 = @import("LC4128ZE_TQFP144.zig");
const LC4128ZE_ucBGA144 = @import("LC4128ZE_ucBGA144.zig");
const LC4128ZE_csBGA144 = @import("LC4128ZE_csBGA144.zig");
const LC4256x_TQFP100 = @import("LC4256x_TQFP100.zig");
const LC4256V_TQFP144 = @import("LC4256V_TQFP144.zig");
const LC4256ZC_TQFP100 = @import("LC4256ZC_TQFP100.zig");
const LC4256ZC_csBGA132 = @import("LC4256ZC_csBGA132.zig");
const LC4256ZE_TQFP100 = @import("LC4256ZE_TQFP100.zig");
const LC4256ZE_TQFP144 = @import("LC4256ZE_TQFP144.zig");
const LC4256ZE_csBGA144 = @import("LC4256ZE_csBGA144.zig");

//[[ ######################### END OF GENERATED CODE ######################### ]]

pub const DeviceFamily = enum {
    low_power, // V/B/C suffix
    zero_power, // ZC suffix
    zero_power_enhanced, // ZE suffix

    pub fn getPartNumberSuffix(self: DeviceFamily) []const u8 {
        return switch (self) {
            .low_power => "V", // or C or B
            .zero_power => "ZC",
            .zero_power_enhanced => "ZE",
        };
    }
};

pub const PackageType = enum {
    TQFP,
    csBGA,
    ucBGA,
};

pub const DevicePackage = enum {
    TQFP_44,
    TQFP_48,
    csBGA_56,
    csBGA_64,
    ucBGA_64,
    TQFP_100,
    TQFP_128,
    csBGA_132,
    ucBGA_132,
    TQFP_144,
    csBGA_144,

    pub fn getNumPins(self: DevicePackage) u16 {
        return switch (self) {
            .TQFP_44 => 44,
            .TQFP_48 => 48,
            .csBGA_56 => 56,
            .csBGA_64, .ucBGA_64 => 64,
            .TQFP_100 => 100,
            .TQFP_128 => 128,
            .csBGA_132, .ucBGA_132 => 132,
            .TQFP_144, .csBGA_144 => 144,
        };
    }

    pub fn getName(self: DevicePackage) []const u8 {
        return switch (self) {
            .TQFP_44 => "44TQFP",
            .TQFP_48 => "48TQFP",
            .csBGA_56 => "56csBGA",
            .csBGA_64 => "64csBGA",
            .ucBGA_64 => "64ucBGA",
            .TQFP_100 => "100TQFP",
            .TQFP_128 => "128TQFP",
            .csBGA_132 => "132csBGA",
            .ucBGA_132 => "132ucBGA",
            .TQFP_144 => "144TQFP",
            .csBGA_144 => "144csBGA",
        };
    }

    pub fn getType(self: DevicePackage) PackageType {
        return switch (self) {
            .TQFP_44,
            .TQFP_48,
            .TQFP_100,
            .TQFP_128,
            .TQFP_144,
                => .TQFP,

            .csBGA_56,
            .csBGA_64,
            .csBGA_132,
            .csBGA_144,
                => .csBGA,

            .ucBGA_64,
            .ucBGA_132,
                => .ucBGA,
        };
    }
};

pub const DeviceType = enum {
    //[[!! for _, device in ipairs(devices) do write(device, ',', nl) end !! 38 ]]
    //[[ ################# !! GENERATED CODE -- DO NOT MODIFY !! ################# ]]
    LC4032x_TQFP44,
    LC4032x_TQFP48,
    LC4032ZC_TQFP48,
    LC4032ZC_csBGA56,
    LC4032ZE_TQFP48,
    LC4032ZE_csBGA64,
    LC4064x_TQFP44,
    LC4064x_TQFP48,
    LC4064x_TQFP100,
    LC4064ZC_TQFP48,
    LC4064ZC_csBGA56,
    LC4064ZC_TQFP100,
    LC4064ZC_csBGA132,
    LC4064ZE_TQFP48,
    LC4064ZE_csBGA64,
    LC4064ZE_ucBGA64,
    LC4064ZE_TQFP100,
    LC4064ZE_csBGA144,
    LC4128x_TQFP100,
    LC4128x_TQFP128,
    LC4128V_TQFP144,
    LC4128ZC_TQFP100,
    LC4128ZC_csBGA132,
    LC4128ZE_TQFP100,
    LC4128ZE_TQFP144,
    LC4128ZE_ucBGA144,
    LC4128ZE_csBGA144,
    LC4256x_TQFP100,
    LC4256V_TQFP144,
    LC4256ZC_TQFP100,
    LC4256ZC_csBGA132,
    LC4256ZE_TQFP100,
    LC4256ZE_TQFP144,
    LC4256ZE_csBGA144,

    //[[ ######################### END OF GENERATED CODE ######################### ]]

    pub fn parse(name: []const u8) ?DeviceType {
        for (std.enums.values(DeviceType)) |e| {
            if (std.mem.eql(u8, name, @tagName(e))) {
                return e;
            }
        }
        return null;
    }

    pub fn getFamily(self: DeviceType) DeviceFamily {
        return switch (self) {
            .LC4032x_TQFP44,
            .LC4032x_TQFP48,
            .LC4064x_TQFP44,
            .LC4064x_TQFP48,
            .LC4064x_TQFP100,
            .LC4128x_TQFP100,
            .LC4128x_TQFP128,
            .LC4128V_TQFP144,
            .LC4256x_TQFP100,
            .LC4256V_TQFP144,
                => .low_power,

            .LC4032ZC_TQFP48,
            .LC4032ZC_csBGA56,
            .LC4064ZC_TQFP48,
            .LC4064ZC_csBGA56,
            .LC4064ZC_TQFP100,
            .LC4064ZC_csBGA132,
            .LC4128ZC_TQFP100,
            .LC4128ZC_csBGA132,
            .LC4256ZC_TQFP100,
            .LC4256ZC_csBGA132,
                => .zero_power,

            .LC4032ZE_TQFP48,
            .LC4032ZE_csBGA64,
            .LC4064ZE_TQFP48,
            .LC4064ZE_csBGA64,
            .LC4064ZE_ucBGA64,
            .LC4064ZE_TQFP100,
            .LC4064ZE_csBGA144,
            .LC4128ZE_TQFP100,
            .LC4128ZE_TQFP144,
            .LC4128ZE_ucBGA144,
            .LC4128ZE_csBGA144,
            .LC4256ZE_TQFP100,
            .LC4256ZE_TQFP144,
            .LC4256ZE_csBGA144,
                => .zero_power_enhanced,
        };
    }

    pub fn getPackage(self: DeviceType) DevicePackage {
        return switch (self) {
            .LC4032x_TQFP44,
            .LC4064x_TQFP44,
                => .TQFP_44,

            .LC4032x_TQFP48,
            .LC4032ZC_TQFP48,
            .LC4032ZE_TQFP48,
            .LC4064x_TQFP48,
            .LC4064ZC_TQFP48,
            .LC4064ZE_TQFP48,
                => .TQFP_48,

            .LC4032ZC_csBGA56,
            .LC4064ZC_csBGA56,
                => .csBGA_56,

            .LC4032ZE_csBGA64,
            .LC4064ZE_csBGA64,
                => .csBGA_64,

            .LC4064ZC_csBGA132,
            .LC4128ZC_csBGA132,
            .LC4256ZC_csBGA132,
                => .csBGA_132,

            .LC4064ZE_csBGA144,
            .LC4128ZE_csBGA144,
            .LC4256ZE_csBGA144,
                => .csBGA_144,

            .LC4064ZE_ucBGA64,
                => .ucBGA_64,

            .LC4128ZE_ucBGA144,
                => .ucBGA_132,

            .LC4064x_TQFP100,
            .LC4064ZC_TQFP100,
            .LC4064ZE_TQFP100,
            .LC4128x_TQFP100,
            .LC4128ZC_TQFP100,
            .LC4128ZE_TQFP100,
            .LC4256x_TQFP100,
            .LC4256ZC_TQFP100,
            .LC4256ZE_TQFP100,
                => .TQFP_100,

            .LC4128x_TQFP128,
                => .TQFP_128,

            .LC4128V_TQFP144,
            .LC4128ZE_TQFP144,
            .LC4256V_TQFP144,
            .LC4256ZE_TQFP144,
                => .TQFP_144,
        };
    }

    pub fn getNumPins(self: DeviceType) u16 {
        return self.getPackage().getNumPins();
    }

    pub fn getNumGlbs(self: DeviceType) u8 {
        return switch (self) {
            .LC4032x_TQFP44,
            .LC4032x_TQFP48,
            .LC4032ZC_TQFP48,
            .LC4032ZC_csBGA56,
            .LC4032ZE_TQFP48,
            .LC4032ZE_csBGA64,
                => 2,

            .LC4064x_TQFP44,
            .LC4064x_TQFP48,
            .LC4064ZC_TQFP48,
            .LC4064ZE_TQFP48,
            .LC4064ZC_csBGA56,
            .LC4064ZE_csBGA64,
            .LC4064ZE_ucBGA64,
            .LC4064x_TQFP100,
            .LC4064ZC_TQFP100,
            .LC4064ZC_csBGA132,
            .LC4064ZE_TQFP100,
            .LC4064ZE_csBGA144,
                => 4,

            .LC4128x_TQFP100,
            .LC4128ZC_TQFP100,
            .LC4128ZE_TQFP100,
            .LC4128x_TQFP128,
            .LC4128V_TQFP144,
            .LC4128ZC_csBGA132,
            .LC4128ZE_TQFP144,
            .LC4128ZE_ucBGA144,
            .LC4128ZE_csBGA144,
                => 8,

            .LC4256x_TQFP100,
            .LC4256ZC_TQFP100,
            .LC4256ZE_TQFP100,
            .LC4256ZC_csBGA132,
            .LC4256V_TQFP144,
            .LC4256ZE_TQFP144,
            .LC4256ZE_csBGA144,
                => 16,
        };
    }

    pub fn getNumMcsPerGlb(self: DeviceType) u8 {
        _ = self;
        return 16;
    }

    pub fn getNumMcs(self: DeviceType) u16 {
        return self.getNumGlbs() * @as(u16, self.getNumMcsPerGlb());
    }

    pub fn getNumGlbInputs(self: DeviceType) u8 {
        _ = self;
        return 36;
    }

    pub fn getJedecWidth(self: DeviceType) u16 {
        return switch (self) {
            .LC4032x_TQFP44,
            .LC4032x_TQFP48,
            .LC4032ZC_TQFP48,
            .LC4032ZC_csBGA56,
            .LC4032ZE_TQFP48,
            .LC4032ZE_csBGA64,
                => 172,

            .LC4064x_TQFP44,
            .LC4064x_TQFP48,
                => 352,

            .LC4064ZC_TQFP48,
            .LC4064ZE_TQFP48,
            .LC4064ZC_csBGA56,
            .LC4064ZE_csBGA64,
            .LC4064ZE_ucBGA64,
            .LC4064x_TQFP100,
            .LC4064ZC_TQFP100,
            .LC4064ZE_TQFP100,
            .LC4064ZC_csBGA132,
            .LC4064ZE_csBGA144,
                => 356,

            .LC4128x_TQFP100,
            .LC4128ZC_TQFP100,
            .LC4128ZE_TQFP100,
            .LC4128x_TQFP128,
            .LC4128V_TQFP144,
            .LC4128ZC_csBGA132,
            .LC4128ZE_TQFP144,
            .LC4128ZE_ucBGA144,
            .LC4128ZE_csBGA144,
                => 740,

            .LC4256x_TQFP100,
            .LC4256ZC_TQFP100,
            .LC4256ZE_TQFP100,
            .LC4256ZC_csBGA132,
            .LC4256V_TQFP144,
            .LC4256ZE_TQFP144,
            .LC4256ZE_csBGA144,
                => 1592,
        };
    }

    pub fn getJedecHeight(self: DeviceType) u16 {
        return switch (self) {
            .LC4064x_TQFP44,
            .LC4064x_TQFP48,
            .LC4256x_TQFP100,
            .LC4256ZC_TQFP100,
            .LC4256ZE_TQFP100,
            .LC4256ZC_csBGA132,
            .LC4256V_TQFP144,
            .LC4256ZE_TQFP144,
            .LC4256ZE_csBGA144,
                => 95,

            else => 100,
        };
    }

    pub fn getBasePartNumber(self: DeviceType) []const u8 {
        return switch (self.getNumGlbs()) {
            2 => "LC4032",
            4 => "LC4064",
            8 => "LC4128",
            16 => "LC4256",
            else => "LC4xxx",
        };
    }

    pub fn writePartNumber(self: DeviceType, writer: anytype, family_code: ?[]const u8, speed_code: ?[]const u8, temp_code: ?[]const u8) !void {
        const family = self.getFamily();
        const family_suffix = family_code orelse family.getPartNumberSuffix();

        const speed = speed_code orelse switch (family) {
            .zero_power_enhanced => "7",
            else => "75",
        };

        const temp = temp_code orelse "C";

        const package = switch (self.getPackage().getType()) {
            .TQFP => "T",
            .csBGA => "M",
            .ucBGA => "UM",
        };

        try writer.print("{s}{s}-{s}{s}", .{ self.getBasePartNumber(), family_suffix, speed, package });

        if (family == .zero_power_enhanced) {
            try writer.writeByte('N');
        }

        try writer.print("{}", .{ self.getNumPins() });

        try writer.writeAll(temp);
    }

    pub fn getPins(self: DeviceType) []const device_pins.PinInfo {
        return switch (self) {
            //[[!! for _, device in ipairs(devices) do write('.', device, ' => &', device, '.pins,', nl) end !! 38 ]]
            //[[ ################# !! GENERATED CODE -- DO NOT MODIFY !! ################# ]]
            .LC4032x_TQFP44 => &LC4032x_TQFP44.pins,
            .LC4032x_TQFP48 => &LC4032x_TQFP48.pins,
            .LC4032ZC_TQFP48 => &LC4032ZC_TQFP48.pins,
            .LC4032ZC_csBGA56 => &LC4032ZC_csBGA56.pins,
            .LC4032ZE_TQFP48 => &LC4032ZE_TQFP48.pins,
            .LC4032ZE_csBGA64 => &LC4032ZE_csBGA64.pins,
            .LC4064x_TQFP44 => &LC4064x_TQFP44.pins,
            .LC4064x_TQFP48 => &LC4064x_TQFP48.pins,
            .LC4064x_TQFP100 => &LC4064x_TQFP100.pins,
            .LC4064ZC_TQFP48 => &LC4064ZC_TQFP48.pins,
            .LC4064ZC_csBGA56 => &LC4064ZC_csBGA56.pins,
            .LC4064ZC_TQFP100 => &LC4064ZC_TQFP100.pins,
            .LC4064ZC_csBGA132 => &LC4064ZC_csBGA132.pins,
            .LC4064ZE_TQFP48 => &LC4064ZE_TQFP48.pins,
            .LC4064ZE_csBGA64 => &LC4064ZE_csBGA64.pins,
            .LC4064ZE_ucBGA64 => &LC4064ZE_ucBGA64.pins,
            .LC4064ZE_TQFP100 => &LC4064ZE_TQFP100.pins,
            .LC4064ZE_csBGA144 => &LC4064ZE_csBGA144.pins,
            .LC4128x_TQFP100 => &LC4128x_TQFP100.pins,
            .LC4128x_TQFP128 => &LC4128x_TQFP128.pins,
            .LC4128V_TQFP144 => &LC4128V_TQFP144.pins,
            .LC4128ZC_TQFP100 => &LC4128ZC_TQFP100.pins,
            .LC4128ZC_csBGA132 => &LC4128ZC_csBGA132.pins,
            .LC4128ZE_TQFP100 => &LC4128ZE_TQFP100.pins,
            .LC4128ZE_TQFP144 => &LC4128ZE_TQFP144.pins,
            .LC4128ZE_ucBGA144 => &LC4128ZE_ucBGA144.pins,
            .LC4128ZE_csBGA144 => &LC4128ZE_csBGA144.pins,
            .LC4256x_TQFP100 => &LC4256x_TQFP100.pins,
            .LC4256V_TQFP144 => &LC4256V_TQFP144.pins,
            .LC4256ZC_TQFP100 => &LC4256ZC_TQFP100.pins,
            .LC4256ZC_csBGA132 => &LC4256ZC_csBGA132.pins,
            .LC4256ZE_TQFP100 => &LC4256ZE_TQFP100.pins,
            .LC4256ZE_TQFP144 => &LC4256ZE_TQFP144.pins,
            .LC4256ZE_csBGA144 => &LC4256ZE_csBGA144.pins,

            //[[ ######################### END OF GENERATED CODE ######################### ]]
        };
    }

    pub fn getGOEPin(self: DeviceType, goe_index: u1) device_pins.InputOutputPinInfo {
        var iter = device_pins.GoeIterator {
            .pins = self.getPins(),
        };
        while (iter.next()) |goe| {
            if (goe.goe_index.? == goe_index) return goe;
        }
        unreachable;
    }

    pub fn getClockPin(self: DeviceType, clock_index: u8) device_pins.ClockInputPinInfo {
        var iter = device_pins.ClockIterator {
            .pins = self.getPins(),
        };
        while (iter.next()) |clk| {
            if (clk.clock_index == clock_index) return clk;
        }
        unreachable;
    }
};

pub fn getGlbName(glb: u8) []const u8 {
    return "ABCDEFGHIJKLMNOP"[glb..glb+1];
}
