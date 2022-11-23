const std = @import("std");

const devices = @import("devices.zig");
const DeviceType = devices.DeviceType;

pub const MacrocellRef = struct {
    glb: u8,
    mc: u8,
};

pub const MacrocellIterator = struct {
    device: DeviceType,
    _last: ?MacrocellRef = null,

    pub fn next(self: *MacrocellIterator) ?MacrocellRef {
        if (self._last) |*ref| {
            if (ref.mc + 1 < self.device.getNumMcsPerGlb()) {
                ref.mc += 1;
                return ref.*;
            } else if (ref.glb + 1 < self.device.getNumGlbs()) {
                ref.glb += 1;
                ref.mc = 0;
                return ref.*;
            } else {
                return null;
            }
        } else {
            const ref = MacrocellRef {
                .glb = 0,
                .mc = 0,
            };
            self._last = ref;
            return ref;
        }
    }
};

pub const SignalType = enum {
    buried,
    input,
    output,
    bidirectional,
};

pub const LogicLevels = enum {
    PCI,
    LVTTL,
    LVCMOS15,
    LVCMOS18,
    LVCMOS25,
    LVCMOS33,
};

pub const DriveType = enum {
    push_pull,
    open_drain,
};

pub const BusMaintenanceType = enum {
    float,
    pulldown,
    pullup,
    keeper,
};

pub const SlewRate = enum {
    slow,
    fast,
};

pub const MacrocellType = enum {
    combinational,
    latch,
    t_ff,
    d_ff,
};

pub const OutputEnableMode = enum {
    goe0,
    goe1,
    goe2,
    goe3,
    from_orm_active_low,
    from_orm_active_high,
    output_only,
    input_only,
};

pub const GlbInputSignal = union {
    mc_fb: struct {
        glb: u8,
        mc: u8,
    },
    pin: u16,
};

pub const TimerDivisor = enum(u32) {
    div128 = 128,
    div1024 = 1024,
    div1048576 = 1048576,
};

pub const FuseFileFormat = enum {
    jed,
    svf,
};

pub const FuseFileWriteOptions = struct {
    format: FuseFileFormat = .jed,
    jed_compact: bool = false,
    jed_zero_char: u8 = '0',
    jed_one_char: u8 = '1',
    svf_erase: bool = true,
    svf_verify: bool = true,
    line_ending: []const u8 = "\n",

};
