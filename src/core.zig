const std = @import("std");

const DeviceType = @import("device.zig").DeviceType;

pub const MacrocellRef = struct {
    glb: u8,
    mc: u8,
};

pub const MacrocellIterator = struct {
    device: DeviceType,
    _last: ?MacrocellRef = null,
    pub fn next(self: *MacrocellIterator) ?MacrocellRef {
        if (self._last) |*ref| {
            if (ref.mc < self.device.getMcsPerGlb()) {
                ref.mc += 1;
                return ref.*;
            } else if (ref.glb < self.device.getNumGlbs()) {
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
    d_ff,
    t_ff,
};

pub const GlbInputSignal = union {
    mc_fb: struct {
        glb: u8,
        mc: u8,
    },
    pin: u16,
};

pub const FuseFileFormat = enum {
    jed,
    svf,
};

pub const FuseFileWriteOptions = struct {
    format: FuseFileFormat = .jed,
    jed_compact: bool = false,
    svf_erase: bool = true,
    svf_verify: bool = true,
    line_ending: []const u8 = "\n",
};