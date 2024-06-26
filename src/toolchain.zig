const std = @import("std");
const builtin = @import("builtin");
const lc4k = @import("lc4k");
const jedec = lc4k.jedec;
const jed_file = lc4k.jed_file;
const helper = @import("helper.zig");
const device_info = @import("device_info.zig");
const DeviceInfo = device_info.DeviceInfo;
const JedecData = jedec.JedecData;

pub const PinAssignment = struct {
    signal: []const u8,
    pin: ?[]const u8 = null,
    iostd: ?LogicLevels = null,
    drive: ?lc4k.DriveType = null,
    bus_maintenance: ?lc4k.BusMaintenance = null,
    slew_rate: ?lc4k.SlewRate = null,
    power_guard_signal: ?[]const u8 = null,
    init_state: ?u1 = null,
    orm_bypass: ?bool = null,
    fast_bypass: ?bool = null,
};

pub const LogicLevels = enum {
    PCI,
    LVTTL,
    LVCMOS15,
    LVCMOS18,
    LVCMOS25,
    LVCMOS33,
};

pub const NodeAssignment = struct {
    signal: []const u8,
    glb: ?u8 = null,
    mc: ?u8 = null,
    input_register: ?bool = null,
    init_state: ?u1 = null,
};

pub const ProductTerm = struct {
    inputs: std.ArrayListUnmanaged([]const u8),
    outputs: std.ArrayListUnmanaged([]const u8),

    pub fn inputsEql(self: *ProductTerm, other_inputs: []const[]const u8) bool {
        if (self.inputs.items.len != other_inputs.len) {
            return false;
        }
        for (self.inputs.items, 0..) |input, i| {
            if (!std.mem.eql(u8, input, other_inputs[i])) {
                return false;
            }
        }
        return true;
    }

    pub fn addOutput(self: *ProductTerm, alloc: std.mem.Allocator, signal: []const u8) !bool {
        if (self.hasOutput(signal)) {
            return false;
        }

        try self.outputs.append(alloc, signal);
        return true;
    }

    pub fn hasInput(self: ProductTerm, signal: []const u8) bool {
        for (self.inputs.items) |input| {
            if (std.mem.eql(u8, input, signal)) {
                return true;
            }
        }
        return false;
    }

    pub fn hasNegatedInput(self: ProductTerm, signal: []const u8) bool {
        for (self.inputs.items) |input| {
            if (input[0] == '~' and std.mem.eql(u8, input[1..], signal)) {
                return true;
            }
        }
        return false;
    }

    pub fn hasOutput(self: ProductTerm, signal: []const u8) bool {
        for (self.outputs.items) |output| {
            if (std.mem.eql(u8, output, signal)) {
                return true;
            }
        }
        return false;
    }
};

fn stripSignalSuffix(signal: []const u8) []const u8 {
    if (std.mem.lastIndexOf(u8, signal, ".")) |dot| {
        return signal[0..dot];
    } else {
        return signal;
    }
}

fn stringSort(ctx: void, a: []const u8, b: []const u8) bool {
    _ = ctx;
    return std.mem.lessThan(u8, a, b);
}

pub const Design = struct {
    alloc: std.mem.Allocator,
    dev: *const DeviceInfo,
    pins: std.ArrayListUnmanaged(PinAssignment),
    nodes: std.ArrayListUnmanaged(NodeAssignment),
    inputs: std.ArrayListUnmanaged([]const u8),
    outputs: std.ArrayListUnmanaged([]const u8),
    pts: std.ArrayListUnmanaged(ProductTerm),
    zero_hold_time: bool,
    adjust_input_assignments: bool,
    parse_glb_inputs: bool,
    max_fit_time_ms: u32,
    uses_power_guard: bool,
    osctimer_div: ?lc4k.TimerDivisor,

    pub fn init(alloc: std.mem.Allocator, dev: *const DeviceInfo) Design {
        return .{
            .alloc = alloc,
            .dev = dev,
            .pins = .{},
            .nodes = .{},
            .inputs = .{},
            .outputs = .{},
            .pts = .{},
            .zero_hold_time = false,
            .adjust_input_assignments = false,
            .parse_glb_inputs = false,
            .max_fit_time_ms = 0, // unlimited
            .uses_power_guard = false,
            .osctimer_div = null,
        };
    }

    pub fn pinAssignment(self: *Design, pa: PinAssignment) !void {
        for (self.pins.items) |*existing| {
            if (std.mem.eql(u8, pa.signal, existing.signal)) {
                if (pa.pin) |pin| existing.pin = pin;
                if (pa.iostd) |iostd| existing.iostd = iostd;
                if (pa.drive) |drive| existing.drive = drive;
                if (pa.bus_maintenance) |pull| existing.bus_maintenance = pull;
                if (pa.slew_rate) |slew| existing.slew_rate = slew;
                if (pa.init_state) |init_state| existing.init_state = init_state;
                if (pa.power_guard_signal) |pg_enable| {
                    self.uses_power_guard = true;
                    existing.power_guard_signal = pg_enable;
                    try self.addPinIfNotNode(pg_enable);
                    try self.nodeAssignment(.{
                        .signal = try std.fmt.allocPrint(self.alloc, "{s}_PG", .{ pa.signal }),
                    });
                }
                if (pa.orm_bypass) |bypass| existing.orm_bypass = bypass;
                if (pa.fast_bypass) |bypass| existing.fast_bypass = bypass;
                return;
            }
        }

        for (self.nodes.items) |existing| {
            if (std.mem.eql(u8, pa.signal, existing.signal)) {
                try std.io.getStdOut().writer().print("Signal `{s}` already exists as a node; can't be redefined as a pin!\n", .{ pa.signal });
                return;
            }
        }

        try self.pins.append(self.alloc, pa);
        if (pa.power_guard_signal) |pg_enable| {
            self.uses_power_guard = true;
            try self.addPinIfNotNode(pg_enable);
            try self.nodeAssignment(.{
                .signal = try std.fmt.allocPrint(self.alloc, "{s}_PG", .{ pa.signal }),
            });
        }
    }

    pub fn addPinIfNotNode(self: *Design, signal: []const u8) !void {
        for (self.pins.items) |existing| {
            if (std.mem.eql(u8, signal, existing.signal)) {
                return;
            }
        }

        for (self.nodes.items) |existing| {
            if (std.mem.eql(u8, signal, existing.signal)) {
                return;
            }
        }

        try self.pins.append(self.alloc, .{
            .signal = signal,
        });
    }

    pub fn nodeAssignment(self: *Design, na: NodeAssignment) !void {
        for (self.nodes.items) |*existing| {
            if (std.mem.eql(u8, na.signal, existing.signal)) {
                if (na.glb) |glb| existing.glb = glb;
                if (na.mc) |mc| existing.mc = mc;
                if (na.input_register) |inreg| existing.input_register = inreg;
                if (na.init_state) |init_state| existing.init_state = init_state;
                return;
            }
        }

        for (self.pins.items) |existing| {
            if (std.mem.eql(u8, na.signal, existing.signal)) {
                try std.io.getStdOut().writer().print("Signal `{s}` already exists as a pin; can't be redefined as a node!\n", .{ na.signal });
                return;
            }
        }

        try self.nodes.append(self.alloc, na);
    }

    pub fn addNodeIfNotPin(self: *Design, signal: []const u8) !void {
        for (self.pins.items) |existing| {
            if (std.mem.eql(u8, signal, existing.signal)) {
                return;
            }
        }

        for (self.nodes.items) |existing| {
            if (std.mem.eql(u8, signal, existing.signal)) {
                return;
            }
        }

        try self.nodes.append(self.alloc, .{
            .signal = signal,
        });
    }

    pub fn addInput(self: *Design, signal: []const u8) !void {
        const sig = if (signal[0] == '~') signal[1..] else signal;

        for (self.inputs.items) |input| {
            if (std.mem.eql(u8, input, sig)) {
                return;
            }
        }

        try self.inputs.append(self.alloc, sig);
        try self.addPinIfNotNode(stripSignalSuffix(sig));
    }

    pub fn addOutput(self: *Design, signal: []const u8) !void {
        for (self.outputs.items) |output| {
            if (std.mem.eql(u8, output, signal)) {
                return;
            }
        }

        try self.outputs.append(self.alloc, signal);
        try self.addNodeIfNotPin(stripSignalSuffix(signal));
    }

    pub fn addPT(self: *Design, inputs: anytype, outputs: anytype) !void {
        var pt_inputs = std.ArrayList([]const u8).init(self.alloc);

        const inputs_type_info = @typeInfo(@TypeOf(inputs));
        switch (inputs_type_info) {
            .Struct => {
                // e.g. tuple containing strings
                inline for (inputs) |input| {
                    try pt_inputs.append(input);
                }
            },
            .Pointer => |info| {
                const child_type_info = @typeInfo(info.child);
                switch (child_type_info) {
                    .Pointer => {
                        // e.g. slice of array containing strings
                        for (inputs) |input| {
                            try pt_inputs.append(input);
                        }
                    },
                    else => {
                        // e.g. string
                        try pt_inputs.append(inputs);
                    },
                }
            },
            .Null => {}, // no inputs
            else => {
                @compileError("Expected inputs to be a string or tuple of strings!");
            },
        }

        for (pt_inputs.items) |input| {
            try self.addInput(input);
        }

        std.sort.pdq([]const u8, pt_inputs.items, {}, stringSort);

        var pt: *ProductTerm = blk: {
            for (self.pts.items) |*pt| {
                if (pt.inputsEql(pt_inputs.items)) {
                    pt_inputs.deinit();
                    break :blk pt;
                }
            }

            const new_pt = try self.pts.addOne(self.alloc);
            new_pt.* = .{
                .inputs = pt_inputs.moveToUnmanaged(),
                .outputs = .{},
            };
            break :blk new_pt;
        };

        const outputs_type_info = @typeInfo(@TypeOf(outputs));
        switch (outputs_type_info) {
            .Struct => {
                // e.g. tuple containing strings
                inline for (outputs) |output| {
                    if(try pt.addOutput(self.alloc, output)) {
                        try self.addOutput(output);
                    }
                }
            },
            .Pointer => |info| {
                const child_type_info = @typeInfo(info.child);
                switch (child_type_info) {
                    .Pointer => {
                        // e.g. slice of array containing strings
                        for (outputs) |output| {
                            if(try pt.addOutput(self.alloc, output)) {
                                try self.addOutput(output);
                            }
                        }
                    },
                    else => {
                        // e.g. string
                        if (try pt.addOutput(self.alloc, outputs)) {
                            try self.addOutput(outputs);
                        }
                    },
                }
            },
            else => {
                @compileError("Expected outputs to be a string or tuple of strings!");
            },
        }
    }

    pub fn oscillator(self: *Design, div: lc4k.TimerDivisor) !void {
        self.osctimer_div = div;
        try self.nodeAssignment(.{
            .signal = "OSC_disable",
        });
        try self.nodeAssignment(.{
            .signal = "OSC_reset",
        });
        try self.nodeAssignment(.{
            .signal = "OSC_out",
        });
        try self.nodeAssignment(.{
            .signal = "OSC_tout",
        });
    }

    pub fn writeLci(self: Design, writer: anytype) !void {
        const series_suffix: []const u8 = switch (self.dev.family) {
            .low_power => "v",
            .zero_power => "c",
            .zero_power_enhanced => "e",
        };

        try writer.writeAll("[Revision]\n");
        try writer.print("Parent = lc4k{}{s}.lci;\n", .{ self.dev.num_mcs, series_suffix });

        try writer.writeAll("\n[Fitter Report Format]\n");
        try writer.writeAll("Detailed = yes;\n");

        try writer.writeAll("\n[Constraint Version]\n");
        try writer.writeAll("version = 1.0;\n");

        try writer.writeAll("\n[Device]\n");
        try writer.writeAll("Family = lc4k;\n");
        try writer.writeAll("PartNumber = ");
        try self.dev.writePartNumber(writer, null, null, null);
        try writer.writeAll(";\n");
        try writer.print("Package = {s};\n", .{ self.dev.getPackageName() });
        try writer.print("PartType = {s}{s};\n", .{ self.dev.getBasePartNumber(), self.dev.getPartNumberSuffix() });
        try writer.writeAll("Speed = -7.5;\n");
        try writer.writeAll("Operating_condition = COM;\n");
        try writer.writeAll("Status = Production;\n");
        try writer.writeAll("Default_Device_Io_Types=LVCMOS33,-;\n");

        try writer.writeAll("\n[Global Constraints]\n");
        try writer.writeAll("Spread_Placement=No;\n");
        try writer.writeAll("Routing_Attempts=2;\n");

        const zerohold = if (self.zero_hold_time) "yes" else "no";
        try writer.print("Zero_hold_time={s};\n", .{ zerohold });

        const adjust_inputs = if (self.adjust_input_assignments) "on" else "off";
        try writer.print("Adjust_input_assignments={s};\n", .{ adjust_inputs });

        try writer.writeAll("\n[Location Assignments]\n");
        for (self.pins.items) |pin_assignment| {
            if (pin_assignment.pin) |pin_name| {
                if (self.dev.getPin(pin_name)) |pin| switch (pin.func) {
                    .io, .io_oe0, .io_oe1 => |mc| {
                        const glb_name = lc4k.getGlbName(pin.glb.?);
                        try writer.print("{s}=pin,{s},-,{s},{};\n", .{ pin_assignment.signal, pin.id, glb_name, mc });
                    },
                    .input => {
                        try writer.print("{s}=pin,{s},-,-,-;\n", .{ pin_assignment.signal, pin.id });
                    },
                    .clock => {
                        try writer.print("{s}=pin,{s},-,-,-;\n", .{ pin_assignment.signal, pin.id });
                    },
                    else => return error.InvalidPinAssignment,
                } else return error.InvalidPinAssignment;
            }
        }

        for (self.nodes.items) |node_assignment| {
            if (node_assignment.glb) |glb| {
                const glb_name = lc4k.getGlbName(glb);
                if (node_assignment.mc) |mc| {
                    try writer.print("{s}=node,-,-,{s},{};\n", .{ node_assignment.signal, glb_name, mc });
                } else {
                    try writer.print("{s}=node,-,-,{s},-;\n", .{ node_assignment.signal, glb_name });
                }
            } else if (node_assignment.mc) |_| {
                return error.InvalidNodeAssignment;
            }
        }

        try writer.writeAll("\n[IO Types]\n");
        for (self.pins.items) |pin_assignment| {
            if (pin_assignment.iostd) |iostd| {
                const tag = switch (pin_assignment.drive orelse .push_pull) {
                    .push_pull => switch (iostd) {
                        .PCI => "PCI",
                        .LVTTL => "LVTTL",
                        .LVCMOS15 => "LVCMOS15",
                        .LVCMOS18 => "LVCMOS18",
                        .LVCMOS25 => "LVCMOS25",
                        .LVCMOS33 => "LVCMOS33",
                    },
                    .open_drain => switch (iostd) {
                        .PCI => "PCI_OD",
                        .LVTTL => "LVTTL_OD",
                        .LVCMOS15 => "LVCMOS15_OD",
                        .LVCMOS18 => "LVCMOS18_OD",
                        .LVCMOS25 => "LVCMOS25_OD",
                        .LVCMOS33 => "LVCMOS33_OD",
                    },
                };
                try writer.print("{s}={s},pin,-,-;\n", .{ pin_assignment.signal, tag });
            } else if (pin_assignment.drive) |drive| {
                const tag = switch (drive) {
                    .push_pull => "LVCMOS33",
                    .open_drain => "LVCMOS33_OD",
                };
                try writer.print("{s}={s},pin,-,-;\n", .{ pin_assignment.signal, tag });
            }
        }

        try writer.writeAll("\n[Pullup]\n");

        if (self.dev.family == .zero_power_enhanced) {
            try writer.writeAll("Default=down;\n");
            for ([_]lc4k.BusMaintenance { .float, .pulldown, .pullup, .keeper }) |pull| {
                const tag = switch (pull) {
                    .float => "OFF",
                    .pulldown => "DOWN",
                    .pullup => "UP",
                    .keeper => "HOLD",
                };
                try writer.print("{s}=", .{ tag });
                var first = true;
                for (self.pins.items) |pin_assignment| {
                    if (pin_assignment.bus_maintenance) |pin_pull| {
                        if (pull == pin_pull) {
                            if (first) {
                                first = false;
                            } else {
                                try writer.writeByte(',');
                            }
                            try writer.writeAll(pin_assignment.signal);
                        }
                    }
                }
                try writer.writeAll(";\n");
            }
        } else {
            var default: ?lc4k.BusMaintenance = null;
            for (self.pins.items) |pin_assignment| {
                if (pin_assignment.bus_maintenance) |pin_pull| {
                    if (default) |default_pull| {
                        if (pin_pull != default_pull) {
                            return error.MultipleBusMaintenanceTypes;
                        }
                    } else {
                        default = pin_pull;
                    }
                }
            }

            if (default) |pull| {
                const tag = switch (pull) {
                    .float => "OFF",
                    .pulldown => "DOWN",
                    .pullup => "UP",
                    .keeper => "HOLD",
                };
                try writer.print("Default={s};\n", .{ tag });
            } else {
                try writer.writeAll("Default=down;\n");
            }
        }

        try writer.writeAll("\n[Slewrate]\n");
        try writer.writeAll("Default=fast;\n");

        for ([_]lc4k.SlewRate { .slow, .fast }) |slew| {
            try writer.print("{s}=", .{ @tagName(slew) });
            var first = true;
            for (self.pins.items) |pin_assignment| {
                if (pin_assignment.slew_rate) |pin_slew| {
                    if (slew == pin_slew) {
                        if (first) {
                            first = false;
                        } else {
                            try writer.writeByte(',');
                        }
                        try writer.writeAll(pin_assignment.signal);
                    }
                }
            }
            try writer.writeAll(";\n");
        }

        try writer.writeAll("\n[Register Powerup]\n");
        for ([_]u1 { 0, 1 }) |state| {
            const name = switch (state) {
                0 => "RESET",
                1 => "SET",
            };
            try writer.print("{s}=", .{ name });
            var first = true;
            for (self.pins.items) |pin_assignment| {
                if (pin_assignment.init_state) |mc_state| {
                    if (state == mc_state) {
                        if (first) {
                            first = false;
                        } else {
                            try writer.writeByte(',');
                        }
                        try writer.writeAll(pin_assignment.signal);
                    }
                }
            }
            for (self.nodes.items) |node_assignment| {
                if (node_assignment.init_state) |mc_state| {
                    if (state == mc_state) {
                        if (first) {
                            first = false;
                        } else {
                            try writer.writeByte(',');
                        }
                        try writer.writeAll(node_assignment.signal);
                    }
                }
            }
            try writer.writeAll(";\n");
        }

        try writer.writeAll("\n[Input Registers]\n");
        for ([_]bool { false, true }) |state| {
            const name = switch (state) {
                false => "NONE",
                true => "INREG",
            };
            try writer.print("{s}=", .{ name });
            var first = true;
            for (self.nodes.items) |node_assignment| {
                if (node_assignment.input_register) |inreg| {
                    if (state == inreg) {
                        if (first) {
                            first = false;
                        } else {
                            try writer.writeByte(',');
                        }
                        try writer.writeAll(node_assignment.signal);
                    }
                }
            }
            try writer.writeAll(";\n");
        }

        if (self.dev.family == .zero_power_enhanced) {
            if (self.osctimer_div) |divisor| {
                try writer.writeAll("\n[OSCTIMER Assignments]\n");
                try writer.writeAll("layer = OFF;\n");
                try writer.print("OSCTIMER = OSC_disable, OSC_reset, OSC_out, OSC_tout, {s};\n", .{ @tagName(divisor)[3..] });
            }
        } else {
            try writer.writeAll("\n[Fast Bypass]\n");
            for ([_]bool { false, true }) |state| {
                const name = switch (state) {
                    false => "NONE",
                    true => "FORCED",
                };
                try writer.print("{s}=", .{ name });
                var first = true;
                for (self.pins.items) |pin_assignment| {
                    if (pin_assignment.fast_bypass) |bypass| {
                        if (state == bypass) {
                            if (first) {
                                first = false;
                            } else {
                                try writer.writeByte(',');
                            }
                            try writer.writeAll(pin_assignment.signal);
                        }
                    }
                }
                try writer.writeAll(";\n");
            }

            try writer.writeAll("\n[ORP Bypass]\n");
            for ([_]bool { false, true }) |state| {
                const name = switch (state) {
                    false => "NONE",
                    true => "BYPASS",
                };
                try writer.print("{s}=", .{ name });
                var first = true;
                for (self.pins.items) |pin_assignment| {
                    if (pin_assignment.orm_bypass) |bypass| {
                        if (state == bypass) {
                            if (first) {
                                first = false;
                            } else {
                                try writer.writeByte(',');
                            }
                            try writer.writeAll(pin_assignment.signal);
                        }
                    }
                }
                try writer.writeAll(";\n");
            }
        }
    }

    pub fn writePla(self: Design, writer: anytype) !void {
        try writer.writeAll("#$ MODULE x\n");
        try writer.print("#$ PINS {}", .{ self.pins.items.len });
        for (self.pins.items) |pin| {
            try writer.print(" {s}", .{ pin.signal });
        }
        try writer.print("\n#$ NODES {}", .{ self.nodes.items.len });
        for (self.nodes.items) |node| {
            try writer.print(" {s}", .{ node.signal });
        }
        try writer.writeAll("\n");

        if (self.osctimer_div) |divisor| {
            try writer.print("#$ PROPERTY LATTICE OSCTIMER osc= OSC_disable, OSC_reset, OSC_out, OSC_tout, {s};\n", .{ @tagName(divisor)[3..] });
            try writer.writeAll("#$ EXTERNAL OSCTIMER 4 DYNOSCDIS'i' TIMERRES'i' OSCOUT'o' TIMEROUT'o'\n");
            try writer.writeAll("#$ INSTANCE osc OSCTIMER 4 OSC_disable OSC_reset OSC_out OSC_tout\n");
        }

        if (self.uses_power_guard) {
            try writer.writeAll("#$ EXTERNAL PG 3 D'i' E'i' Q'o'\n");
            var n: usize = 0;
            for (self.pins.items) |pin| {
                if (pin.power_guard_signal) |pg_enable| {
                    try writer.print("#$ INSTANCE I{} PG 3 {s} {s} {s}_PG\n", .{ n, pin.signal, pg_enable, pin.signal });
                    n += 1;
                }
            }
        }

        try writer.writeAll(".type f\n");
        try writer.print(".i {}\n", .{ self.inputs.items.len });
        try writer.print(".o {}\n", .{ self.outputs.items.len });
        try writer.writeAll(".ilb");
        for (self.inputs.items) |input| {
            try writer.print(" {s}", .{ input });
        }
        try writer.writeAll("\n.ob");
        for (self.outputs.items) |output| {
            try writer.print(" {s}", .{ output });
        }
        try writer.writeAll("\n.phase ");
        try writer.writeByteNTimes('1', self.outputs.items.len);
        try writer.print("\n.p {}\n", .{ self.pts.items.len });
        for (self.pts.items) |pt| {
            for (self.inputs.items) |input| {
                if (pt.hasInput(input)) {
                    try writer.writeByte('1');
                } else if (pt.hasNegatedInput(input)) {
                    try writer.writeByte('0');
                } else {
                    try writer.writeByte('-');
                }
            }
            try writer.writeByte(' ');
            for (self.outputs.items) |output| {
                try writer.writeByte(if (pt.hasOutput(output)) '1' else '-');
            }
            try writer.writeByte('\n');
        }
        try writer.writeAll(".end\n");
    }

};

pub const GlbInputSignal = union(enum) {
    fb: lc4k.MacrocellRef,
    pin: []const u8,

    pub fn eql (a: GlbInputSignal, b: GlbInputSignal) bool {
        return switch (a) {
            .fb => |afb| switch (b) {
                .fb => |bfb| std.meta.eql(afb, bfb),
                .pin => false,
            },
            .pin => |aid| switch (b) {
                .fb => false,
                .pin => |bid| std.mem.eql(u8, aid, bid),
            },
        };
    }

    pub const HashContext = struct {
        pub fn hash(_: HashContext, x: GlbInputSignal) u64 {
            var h = std.hash.Wyhash.init(12345);
            // We don't actually include the FB/pin distinction in the hash.
            // The pin ID will be alphanumeric ASCII, and the FB will be two small bytes, which shouldn't overlap with ASCII.
            switch (x) {
                .fb => |mcref| h.update(std.mem.asBytes(&mcref)),
                .pin => |id| h.update(id),
            }
            return h.final();
        }
        pub fn eql(_: HashContext, a: GlbInputSignal, b: GlbInputSignal) bool {
            return a.eql(b);
        }
    };
};

pub const GlbInputFitSignal = struct {
    name: []const u8,
    source: GlbInputSignal,
};


pub const GISet = struct {
    raw: std.StaticBitSet(36),

    pub fn initSingle(gi: usize) GISet {
        var self = .{
            .raw = std.StaticBitSet(36).initEmpty(),
        };
        self.raw.set(gi);
        return self;
    }

    pub fn initEmpty() GISet {
        return .{
            .raw = std.StaticBitSet(36).initEmpty(),
        };
    }

    pub fn initFull() GISet {
        return .{
            .raw = std.StaticBitSet(36).initFull(),
        };
    }

    pub fn add(self: *GISet, gi: usize) void {
        self.raw.set(gi);
    }

    pub fn removeAll(self: *GISet, other: GISet) void {
        var inverted = other;
        inverted.raw.toggleAll();
        self.raw.setIntersection(inverted.raw);
    }

    pub fn count(self: GISet) usize {
        return self.raw.count();
    }

    pub fn pickRandom(self: GISet, rnd: std.rand.Random) usize {
        var skip = rnd.intRangeLessThan(usize, 0, self.count());
        var iter = self.raw.iterator(.{});
        while (skip > 0) : (skip -= 1) {
            _ = iter.next();
        }
        return iter.next().?;
    }

    pub fn iterator(self: *const GISet) Iterator {
        return self.raw.iterator(.{});
    }

    const Iterator = std.StaticBitSet(36).Iterator(.{});
};

pub const GlbInputSet = struct {
    const BitSet = std.StaticBitSet(16*16*2+10);

    raw: BitSet,

    pub fn initEmpty() GlbInputSet {
        return .{
            .raw = BitSet.initEmpty(),
        };
    }

    pub fn initFull(signals: []const GlbInputFitSignal) GlbInputSet {
        var self = .{
            .raw = BitSet.initEmpty(),
        };
        self.raw.setRangeValue(.{ .start = 0, .end = signals.len }, true);
        return self;
    }

    pub fn add(self: *GlbInputSet, s: GlbInputSignal, signals: []const GlbInputFitSignal) void {
        if (indexOf(s, signals)) |i| {
            return self.raw.set(i);
        } else {
            var buf: [1024]u8 = undefined;
            const msg = switch (s) {
                .fb => |mcref| std.fmt.bufPrint(&buf, "Can't add feedback signal {any}", .{ mcref }),
                .pin => |id| std.fmt.bufPrint(&buf, "Can't add pin signal {s}", .{ id }),
            } catch unreachable;
            @panic(msg);
        }
    }

    pub fn addAll(self: *GlbInputSet, other: GlbInputSet) void {
        self.raw.setUnion(other.raw);
    }

    pub fn remove(self: *GlbInputSet, s: GlbInputSignal, signals: []const GlbInputFitSignal) void {
        if (indexOf(s, signals)) |i| {
            return self.raw.unset(i);
        }
    }

    pub fn removeAll(self: *GlbInputSet, other: GlbInputSet) void {
        var inverted = other;
        inverted.raw.toggleAll();
        self.raw.setIntersection(inverted.raw);
    }

    fn pickRandomRaw(self: GlbInputSet, rnd: std.rand.Random) usize {
        var skip = rnd.intRangeLessThan(usize, 0, self.count());
        var iter = self.raw.iterator(.{});
        while (skip > 0) : (skip -= 1) {
            _ = iter.next();
        }
        return iter.next().?;
    }

    pub fn removeRandom(self: *GlbInputSet, rnd: std.rand.Random, count_to_remove: usize) GlbInputSet {
        var removed = GlbInputSet.initEmpty();
        var n: usize = 0;
        while (n < count_to_remove) : (n += 1) {
            const to_remove = self.pickRandomRaw(rnd);
            removed.raw.set(to_remove);
            self.raw.unset(to_remove);
        }
        return removed;
    }

    pub fn contains(self: GlbInputSet, s: GlbInputSignal, signals: []const GlbInputFitSignal) bool {
        if (indexOf(s, signals)) |i| {
            return self.raw.isSet(i);
        } else {
            return false;
        }
    }

    pub fn count(self: GlbInputSet) usize {
        return self.raw.count();
    }

    pub fn iterator(self: *const GlbInputSet, signals: []const GlbInputFitSignal) Iterator {
        return .{
            .raw = self.raw.iterator(.{}),
            .signals = signals,
        };
    }

    const Iterator = struct {
        raw: GlbInputSet.BitSet.Iterator(.{}),
        signals: []const GlbInputFitSignal,

        pub fn next(self: *Iterator) ?GlbInputFitSignal {
            if (self.raw.next()) |index| {
                return self.signals[index];
            } else {
                return null;
            }
        }
    };

    fn indexOf(signal: GlbInputSignal, signals: []const GlbInputFitSignal) ?usize {
        for (signals, 0..) |s, i| {
            if (signal.eql(s.source)) {
                return i;
            }
        }
        return null;
    }
};

pub const GlbFitData = struct {
    glb: u8,
    inputs: [36]?GlbInputFitSignal = [_]?GlbInputFitSignal { null } ** 36,
};

pub const FitResults = struct {
    term: std.ChildProcess.Term,
    failed: bool,
    report: []const u8,
    jedec: JedecData,
    glbs: []GlbFitData,

    pub fn checkTerm(self: FitResults) !void {
        switch (self.term) {
            .Exited => |code| {
                if (code != 0) {
                    try std.io.getStdErr().writer().print("lpf4k returned code {}", .{ code });
                    return error.FitterError;
                }
            },
            .Signal => |s| {
                try std.io.getStdErr().writer().print("lpf4k signalled {}", .{ s });
                return error.FitterError;
            },
            .Stopped => |s| {
                try std.io.getStdErr().writer().print("lpf4k stopped with {}", .{ s });
                return error.FitterError;
            },
            .Unknown => |s| {
                try std.io.getStdErr().writer().print("lpf4k terminated unexpectedly with {}", .{ s });
                return error.FitterError;
            },
        }
        if (self.failed) {
            try std.io.getStdErr().writer().writeAll("Fitter failed to generate a valid device configuration!\n");
            return error.FitterError;
        }
    }
};

pub const Toolchain = struct {

    alloc: std.mem.Allocator,
    dir: std.fs.Dir,

    pub fn init(allocator: std.mem.Allocator) !Toolchain {
        var parent_dir = try std.fs.cwd().makeOpenPath("temp", .{});
        try std.posix.chdir("temp");

        var random_bytes: [6]u8 = undefined;
        std.crypto.random.bytes(&random_bytes);
        var sub_path: [8]u8 = undefined;
        _ = std.fs.base64_encoder.encode(&sub_path, &random_bytes);

        const dir = try parent_dir.makeOpenPath(&sub_path, .{ .iterate = true });
        try std.posix.chdir(&sub_path);

        return Toolchain {
            .alloc = allocator,
            .dir = dir,
        };
    }

    pub fn deinit(self: *Toolchain, keep_files: bool) void {
        if (!keep_files) {
            self.cleanTempDir() catch |err| {
                std.debug.print("Failed to clean up toolchain temporary directory: {}\n", .{ err });
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
                std.debug.dumpCurrentStackTrace(null);
            };
        }
        self.dir.close();
    }

    pub fn runToolchain(self: *Toolchain, design: Design) !FitResults {
        {
            var f = try std.fs.cwd().createFile("test.tt4", .{});
            defer f.close();
            try design.writePla(f.writer());
        }
        {
            var f = try std.fs.cwd().createFile("test.lci", .{});
            defer f.close();
            try design.writeLci(f.writer());
        }

        var child = std.ChildProcess.init(&[_][]const u8 {
            "C:\\ispLEVER_Classic2_1\\ispcpld\\bin\\lpf4k.exe",
            "-i", "test.tt4",
            "-lci", "test.lci",
            "-d", design.dev.getFitterName(),
            "-fmt", "PLA",
            //"-lca",
            //"-lca_mfb",
            //"-lca_ifb",
            //"-klfm",
            //"-ppi_off",
            "-v",
        }, self.alloc);
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;

        try child.spawn();

        const term = waitForChild(&child, design.max_fit_time_ms) catch std.ChildProcess.Term { .Unknown = 0 };

        //var signals = try std.ArrayList(SignalFitData).initCapacity(self.alloc, 32);

        const log = try self.readFile("test.log");

        var failed = !std.meta.eql(term, std.ChildProcess.Term { .Exited = 0 });

        if (!failed and !std.mem.containsAtLeast(u8, log, 1, "Project 'test' was Fitted Successfully!")) {
            std.debug.print("Unexpected fitter log:\n {s}\n", .{ log });
            failed = true;
        }

        const jedec_size = design.dev.jedec_dimensions;

        var report: []const u8 = "";
        var jed: JedecData = undefined;
        if (failed) {
            jed = try JedecData.initFull(self.alloc, jedec_size);
        } else {
            report = try self.readFile("test.rpt");
            jed = (try jed_file.parse(self.alloc, jedec_size.width(), jedec_size.height(), try self.readFile("test.jed"))).data;
        }

        var results = FitResults {
            .term = term,
            .failed = failed,
            .report = report,
            .jedec = jed,
            .glbs = try self.alloc.alloc(GlbFitData, design.dev.num_glbs),
        };

        try self.parseFitterReport(design, &results);
        return results;
    }

    fn waitForChild(child: *std.ChildProcess, timeout_ms: u32) !std.ChildProcess.Term {
        if (timeout_ms > 0) {
            std.os.windows.WaitForSingleObjectEx(child.id, timeout_ms, false) catch {};
            std.os.windows.TerminateProcess(child.id, 1) catch |err| switch (err) {
                error.PermissionDenied => {
                    // Usually when TerminateProcess triggers a ACCESS_DENIED error, it
                    // indicates that the process has already exited, but there may be
                    // some rare edge cases where our process handle no longer has the
                    // PROCESS_TERMINATE access right, so let's do another check to make
                    // sure the process is really no longer running:
                    std.os.windows.WaitForSingleObjectEx(child.id, 0, false) catch return err;
                },
                else => return err,
            };
        }
        return child.wait();
    }

    fn readFile(self: *Toolchain, path: []const u8) ![]const u8 {
        var f = try std.fs.cwd().openFile(path, .{});
        defer f.close();
        return f.readToEndAlloc(self.alloc, 0x100000000);
    }

    fn parseGlbInputFitSignal(out: *GlbFitData, raw: []const u8, dev: *const DeviceInfo) !void {
        const gi = try std.fmt.parseInt(u8, raw[0..2], 10);
        const raw_name = raw[13..29];
        const signal = std.mem.trim(u8, raw_name, " ");

        if (signal.len == 0 or std.mem.eql(u8, signal, "...")) {
            out.inputs[gi] = null;
        } else {
            var source: GlbInputSignal = undefined;
            const raw_source = raw[3..12];

            if (std.mem.eql(u8, raw_source[0..3], "pin")) {
                const id = std.mem.trim(u8, raw_source[3..], " ");
                source = .{ .pin = dev.getPin(id).?.id };
            } else {
                const glb = raw_source[3] - 'A';
                const mc = try std.fmt.parseInt(lc4k.MacrocellIndex, std.mem.trim(u8, raw_source[5..], " "), 10);

                source = .{ .fb = .{
                    .glb = glb,
                    .mc = mc,
                }};
            }

            out.inputs[gi] = GlbInputFitSignal {
                .name = signal,
                .source = source,
            };
        }
    }

    fn parseFitterReport(self: *Toolchain, design: Design, results: *FitResults) !void {
        if (design.parse_glb_inputs) {
            var glb: u8 = 0;
            while (glb < design.dev.num_glbs) : (glb += 1) {
                const header = try std.fmt.allocPrint(self.alloc, "GLB_{s}_LOGIC_ARRAY_FANIN", .{ lc4k.getGlbName(glb) });
                if (helper.extract(results.report, header, "------------------------------------------")) |raw| {
                    var fit_data = GlbFitData {
                        .glb = glb,
                    };

                    var line_iter = std.mem.tokenize(u8, raw, "\r\n");
                    while (line_iter.next()) |line| {
                        if (line[0] != '0' and line[0] != '1') {
                            continue; // ignore remaining header/footer lines
                        }

                        if (line.len >= 36) {
                            try parseGlbInputFitSignal(&fit_data, line[0..36], design.dev);
                            if (line.len >= 69) {
                                try parseGlbInputFitSignal(&fit_data, line[40..], design.dev);
                            }
                        }
                    }
                    results.glbs[glb] = fit_data;
                }
            }
        }
    }

    pub fn cleanTempDir(self: *Toolchain) !void {
        var n: u8 = 0;
        const max: u8 = 20;
        while (n <= max) : (n += 1) {
            var retry = false;
            var iter = self.dir.iterate();
            while (try iter.next()) |entry| {
                self.dir.deleteFile(entry.name) catch |err| switch (err) {
                    error.FileBusy => {
                        if (n < max) {
                            retry = true;
                        } else {
                            return err;
                        }
                    },
                    else => return err,
                };
            }

            if (retry) {
                std.time.sleep(10_000_000 * @as(u64, n));
            } else {
                break;
            }
        }
    }

};
