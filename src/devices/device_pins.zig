
pub const InputPinInfo = struct {
    pin_index: u16,
    pin_number: []const u8,
    bank: u8,
    glb: u8,
};

pub const ClockInputPinInfo = struct {
    pin_index: u16,
    pin_number: []const u8,
    bank: u8,
    glb: u8,
    clock_index: u8,
};

pub const InputOutputPinInfo = struct {
    pin_index: u16,
    pin_number: []const u8,
    bank: u8,
    glb: u8,
    mc: u8,
    goe_index: ?u1,
};

pub const MiscPinInfo = struct {
    pin_index: u16,
    pin_number: []const u8,
    misc_type: Type,

    pub const Type = enum {
        no_connect,
        gnd,
        vcc_core,
        vcco_bank_0,
        vcco_bank_1,
        tck,
        tms,
        tdi,
        tdo,
    };
};

pub const PinInfo = union(enum) {
    input: InputPinInfo,
    clock_input: ClockInputPinInfo,
    input_output: InputOutputPinInfo,
    misc: MiscPinInfo,

    pub fn pin_index(self: PinInfo) u16 {
        return switch (self) {
            .input => |info| info.pin_index,
            .clock_input => |info| info.pin_index,
            .input_output => |info| info.pin_index,
            .misc => |info| info.pin_index,
        };
    }

    pub fn pin_number(self: PinInfo) []const u8 {
        return switch (self) {
            .input => |info| info.pin_number,
            .clock_input => |info| info.pin_number,
            .input_output => |info| info.pin_number,
            .misc => |info| info.pin_number,
        };
    }
};

pub const InputIterator = struct {
    pins: []const PinInfo,
    next_index: u16 = 0,
    single_glb: ?u8 = null,
    exclude_glb: ?u8 = null,
    exclude_goes: bool = false,
    exclude_clocks: bool = false,
    exclude_pin: ?u16 = null,

    pub fn next(self: *InputIterator) ?PinInfo {
        const len = self.pins.len;
        var i = self.next_index;
        while (i < len) : (i += 1) {
            if (self.exclude_pin) |pin| {
                if (i == pin) continue;
            }
            const pi = self.pins[i];
            switch (pi) {
                .input => {},
                .clock_input => {
                    if (self.exclude_clocks) continue;
                },
                .input_output => |info| {
                    if (self.single_glb) |glb| {
                        if (info.glb != glb) continue;
                    }
                    if (self.exclude_glb) |glb| {
                        if (info.glb == glb) continue;
                    }
                    if (self.exclude_goes and info.goe_index != null) {
                        continue;
                    }
                },
                .misc => continue,
            }
            self.next_index = i + 1;
            return pi;
        }
        return null;
    }
};

pub const ClockIterator = struct {
    pins: []const PinInfo,
    next_index: u16 = 0,
    exclude_pin: ?u16 = null,

    pub fn next(self: *ClockIterator) ?ClockInputPinInfo {
        const len = self.pins.len;
        var i = self.next_index;
        while (i < len) : (i += 1) {
            if (self.exclude_pin) |pin| {
                if (i == pin) continue;
            }
            switch (self.pins[i]) {
                .clock_input => |info| {
                    self.next_index = i + 1;
                    return info;
                },
                .input, .input_output, .misc => {},
            }
        }
        return null;
    }
};

pub const GoeIterator = struct {
    pins: []const PinInfo,
    next_index: u16 = 0,
    exclude_pin: ?u16 = null,

    pub fn next(self: *GoeIterator) ?InputOutputPinInfo {
        const len = self.pins.len;
        var i = self.next_index;
        while (i < len) : (i += 1) {
            if (self.exclude_pin) |pin| {
                if (i == pin) continue;
            }
            switch (self.pins[i]) {
                .input_output => |info| {
                    if (info.goe_index) |_| {
                        self.next_index = i + 1;
                        return info;
                    }
                },
                .input, .clock_input, .misc => {},
            }
        }
        return null;
    }
};

pub const OutputIterator = struct {
    pins: []const PinInfo,
    next_index: u16 = 0,
    single_glb: ?u8 = null,
    exclude_glb: ?u8 = null,
    exclude_goes: bool = false,
    exclude_pin: ?u16 = null,

    pub fn next(self: *OutputIterator) ?InputOutputPinInfo {
        const len = self.pins.len;
        var i = self.next_index;
        while (i < len) : (i += 1) {
            if (self.exclude_pin) |pin| {
                if (i == pin) continue;
            }
            switch (self.pins[i]) {
                .input_output => |info| {
                    if (self.single_glb) |glb| {
                        if (info.glb != glb) continue;
                    }
                    if (self.exclude_glb) |glb| {
                        if (info.glb == glb) continue;
                    }
                    if (self.exclude_goes and info.goe_index != null) {
                        continue;
                    }
                    self.next_index = i + 1;
                    return info;
                },
                .input, .clock_input, .misc => {},
            }
        }
        return null;
    }
};

pub const PinInfoBuilder = struct {
    next_index: u16 = 0,

    fn next(self: *PinInfoBuilder) u16 {
        const index = self.next_index;
        self.next_index += 1;
        return index;
    }

    pub fn clk(self: *PinInfoBuilder, pin_number: []const u8, bank: u8, glb: u8, clk_index: u8) PinInfo {
        return .{ .clock_input = .{
            .pin_index = self.next(),
            .pin_number = pin_number,
            .bank = bank,
            .glb = glb,
            .clock_index = clk_index,
        }};
    }

    pub fn in(self: *PinInfoBuilder, pin_number: []const u8, bank: u8, glb: u8) PinInfo {
        return .{ .input = .{
            .pin_index = self.next(),
            .pin_number = pin_number,
            .bank = bank,
            .glb = glb,
        }};
    }

    pub fn io(self: *PinInfoBuilder, pin_number: []const u8, bank: u8, glb: u8, mc: u8) PinInfo {
        return .{ .input_output = .{
            .pin_index = self.next(),
            .pin_number = pin_number,
            .bank = bank,
            .glb = glb,
            .mc = mc,
            .goe_index = null,
        }};
    }

    pub fn goe(self: *PinInfoBuilder, pin_number: []const u8, bank: u8, glb: u8, mc: u8, goe_index: u1) PinInfo {
        return .{ .input_output = .{
            .pin_index = self.next(),
            .pin_number = pin_number,
            .bank = bank,
            .glb = glb,
            .mc = mc,
            .goe_index = goe_index,
        }};
    }

    pub fn misc(self: *PinInfoBuilder, pin_number: []const u8, misc_type: MiscPinInfo.Type) PinInfo {
        return .{ .misc = .{
            .pin_index = self.next(),
            .pin_number = pin_number,
            .misc_type = misc_type,
        }};
    }
};
