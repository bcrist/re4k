const std = @import("std");

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



pub const DeviceInfo = struct {
    jedec_width: u16,
    jedec_height: u16,
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
