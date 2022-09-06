const std = @import("std");
const core = @import("core.zig");
const jedec = @import("jedec.zig");

const DeviceType = @import("device.zig").DeviceType;
const JedecData = jedec.JedecData;

fn getDeviceFitterName(device: DeviceType) []const u8 {
    return switch (device) {
        .LC4032x_TQFP44   => "M4S_32_30",
        .LC4032x_TQFP48   => "M4S_32_32",
        .LC4032ZC_TQFP48   => "M4Z_32_32",
        .LC4032ZC_csBGA56   => "M4Z_32_32S",
        .LC4032ZE_TQFP48   => "M4E_32_32",
        .LC4032ZE_csBGA64   => "M4E_32_32S",
        .LC4064x_TQFP44   => "M4S_64_30",
        .LC4064x_TQFP48   => "M4S_64_32",
        .LC4064ZC_TQFP48   => "M4Z_64_32",
        .LC4064ZE_TQFP48   => "M4E_64_32",
        .LC4064ZC_csBGA56  => "M4Z_64_32S",
        .LC4064ZE_csBGA64   => "M4E_64_48S",
        .LC4064ZE_ucBGA64   => "M4E_64_48U",
        .LC4064x_TQFP100  => "M4S_64_64",
        .LC4064ZC_TQFP100  => "M4Z_64_64",
        .LC4064ZE_TQFP100  => "M4E_64_64",
        .LC4064ZC_csBGA132  => "M4Z_64_64S",
        .LC4064ZE_csBGA144  => "M4E_64_64S",
        .LC4128x_TQFP100 => "M4S_128_64",
        .LC4128ZC_TQFP100 => "M4Z_128_64",
        .LC4128ZE_TQFP100 => "M4E_128_64",
        .LC4128x_TQFP128  => "M4S_128_92",
        .LC4128V_TQFP144  => "M4S_128_96",
        .LC4128ZC_csBGA132  => "M4Z_128_96S",
        .LC4128ZE_TQFP144  => "M4E_128_96",
        .LC4128ZE_csBGA144  => "M4E_128_96S",
        .LC4128ZE_ucBGA144  => "M4E_128_96U",
        .LC4256x_TQFP100 => "M4S_256_64",
        .LC4256ZC_TQFP100 => "M4Z_256_64",
        .LC4256ZE_TQFP100 => "M4E_256_64",
        .LC4256ZC_csBGA132  => "M4Z_256_96S",
        .LC4256V_TQFP144 => "M4S_256_96",
        .LC4256ZE_TQFP144 => "M4E_256_96",
        .LC4256ZE_csBGA144 => "M4E_256_108S",
    };
}

pub const PinAssignment = struct {
    signal: []const u8,
    pin_index: ?u16 = null,
    //input_register: ?bool = null,
    iostd: ?core.LogicLevels = null,
    bus_maintenance: ?core.BusMaintenanceType = null,
    slew_rate: ?core.SlewRate = null,
    //power_guard_signal: ?[]const u8 = null,
};

pub const NodeAssignment = struct {
    signal: []const u8,
    glb: ?u8 = null,
    mc: ?u8 = null,
};

pub const ProductTerm = struct {
    inputs: std.ArrayListUnmanaged([]const u8),
    outputs: std.ArrayListUnmanaged([]const u8),

    pub fn inputsEql(self: *ProductTerm, other_inputs: []const[]const u8) bool {
        if (self.inputs.items.len != other_inputs.len) {
            return false;
        }
        for (self.inputs.items) |input, i| {
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
    device: DeviceType,
    pins: std.ArrayListUnmanaged(PinAssignment),
    nodes: std.ArrayListUnmanaged(NodeAssignment),
    inputs: std.ArrayListUnmanaged([]const u8),
    outputs: std.ArrayListUnmanaged([]const u8),
    pts: std.ArrayListUnmanaged(ProductTerm),
    zero_hold_time: bool,
    ignore_fitter_warnings: bool,

    pub fn init(alloc: std.mem.Allocator, device: DeviceType) Design {
        return .{
            .alloc = alloc,
            .device = device,
            .pins = .{},
            .nodes = .{},
            .inputs = .{},
            .outputs = .{},
            .pts = .{},
            .zero_hold_time = false,
            .ignore_fitter_warnings = false,
        };
    }

    pub fn pinAssignment(self: *Design, pa: PinAssignment) !void {
        for (self.pins.items) |*existing| {
            if (std.mem.eql(u8, pa.signal, existing.signal)) {
                if (pa.pin_index) |pin_index| existing.pin_index = pin_index;
                // if (pa.input_register) |inreg| existing.input_register = inreg;
                if (pa.iostd) |iostd| existing.iostd = iostd;
                if (pa.bus_maintenance) |pull| existing.bus_maintenance = pull;
                if (pa.slew_rate) |slew| existing.slew_rate = slew;
                // if (pa.power_guard_signal) |pg| {
                    // existing.power_guard_signal = pg;
                    // try self.addPinIfNotNode(pg);
                // }
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
        // if (pa.power_guard_signal) |pg| {
        //     try self.addPinIfNotNode(pg);
        // }
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

    fn addInput(self: *Design, signal: []const u8) !void {
        var sig = if (signal[0] == '~') signal[1..] else signal;

        for (self.inputs.items) |input| {
            if (std.mem.eql(u8, input, sig)) {
                return;
            }
        }

        try self.inputs.append(self.alloc, sig);
        try self.addPinIfNotNode(stripSignalSuffix(signal));
    }

    fn addOutput(self: *Design, signal: []const u8) !void {
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
                for (inputs) |input| {
                    try pt_inputs.append(input);
                }
            },
            .Pointer => {
                try pt_inputs.append(inputs);
            },
            else => {
                @compileError("Expected inputs to be a string or tuple of strings!");
            },
        }

        for (pt_inputs.items) |input| {
            try self.addInput(input);
        }

        std.sort.sort([]const u8, pt_inputs.items, {}, stringSort);

        var pt: *ProductTerm = blk: {
            for (self.pts.items) |*pt| {
                if (pt.inputsEql(pt_inputs.items)) {
                    pt_inputs.deinit();
                    break :blk pt;
                }
            }

            var new_pt = try self.pts.addOne(self.alloc);
            new_pt.* = .{
                .inputs = pt_inputs.moveToUnmanaged(),
                .outputs = .{},
            };
            break :blk new_pt;
        };

        const outputs_type_info = @typeInfo(@TypeOf(outputs));
        switch (outputs_type_info) {
            .Struct => {
                for (outputs) |output| {
                    if(try pt.addOutput(self.alloc, output)) {
                        try self.addOutput(output);
                    }
                }
            },
            .Pointer => {
                if (try pt.addOutput(self.alloc, outputs)) {
                    try self.addOutput(outputs);
                }
            },
            else => {
                @compileError("Expected outputs to be a string or tuple of strings!");
            },
        }
    }

    pub fn writeLci(self: Design, writer: anytype) !void {
        const device = self.device;
        const macrocells = device.getNumMcs();
        const series_suffix: []const u8 = switch (device.getFamily()) {
            .low_power => "v",
            .zero_power => "c",
            .zero_power_enhanced => "e",
        };

        try writer.writeAll("[Revision]\n");
        try writer.print("Parent = lc4k{}{s}.lci;\n", .{ macrocells, series_suffix });

        try writer.writeAll("\n[Fitter Report Format]\n");
        try writer.writeAll("Detailed = yes;\n");

        try writer.writeAll("\n[Constraint Version]\n");
        try writer.writeAll("version = 1.0;\n");

        try writer.writeAll("\n[Device]\n");
        try writer.writeAll("Family = lc4k;\n");
        try writer.writeAll("PartNumber = ");
        try device.writePartNumber(writer, null, null, null);
        try writer.writeAll(";\n");
        try writer.print("Package = {s};\n", .{ device.getPackage().getName() });
        try writer.print("PartType = {s}{s};\n", .{ device.getBasePartNumber(), device.getFamily().getPartNumberSuffix() });
        try writer.writeAll("Speed = -7.5;\n");
        try writer.writeAll("Operating_condition = COM;\n");
        try writer.writeAll("Status = Production;\n");
        try writer.writeAll("Default_Device_Io_Types=LVCMOS33,-;\n");

        try writer.writeAll("\n[Global Constraints]\n");
        try writer.writeAll("Spread_Placement=No;\n");

        var zerohold = if (self.zero_hold_time) "yes" else "no";
        try writer.print("Zero_hold_time={s};\n", .{ zerohold });

        try writer.writeAll("\n[Location Assignments]\n");
        for (self.pins.items) |pin_assignment| {
            if (pin_assignment.pin_index) |pin_index| {
                switch (device.getPinInfo(pin_index)) {
                    .input_output => |info| {
                        const glb_name = device.getGlbName(info.glb);
                        try writer.print("{s}=pin,{s},-,{s},{};\n", .{ pin_assignment.signal, info.pin_number, glb_name, info.mc });
                    },
                    .input => |info| {
                        try writer.print("{s}=pin,{s},-,-,-;\n", .{ pin_assignment.signal, info.pin_number });
                    },
                    .clock_input => |info| {
                        try writer.print("{s}=pin,{s},-,-,-;\n", .{ pin_assignment.signal, info.pin_number });
                    },
                    else => return error.InvalidPinAssignment,
                }
            }
        }

        for (self.nodes.items) |node_assignment| {
            if (node_assignment.glb) |glb| {
                const glb_name = device.getGlbName(glb);
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
                try writer.print("{s}={s},pin,-,-;\n", .{ pin_assignment.signal, @tagName(iostd) });
            }
        }

        try writer.writeAll("\n[Pullup]\n");

        if (device.getFamily() == .zero_power_enhanced) {
            try writer.writeAll("Default=down;\n");
            for ([_]core.BusMaintenanceType { .float, .pulldown, .pullup, .keeper }) |pull| {
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
            var default: ?core.BusMaintenanceType = null;
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

        for ([_]core.SlewRate { .slow, .fast }) |slew| {
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
        // TODO power guard
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

pub const SignalFitFlags = enum {
    uses_gclk,
    uses_goe,
    uses_shared_clk,
    uses_shared_ce,
    uses_shared_ar,
    uses_shared_ap,
    powerup_reset,
    powerup_preset,
    uses_input_reg,
    uses_ar,
    uses_ap,
    uses_ce,
    uses_oe,
    uses_fast_path,
    uses_orp_bypass,
};

pub const SignalFitData = struct {
    name: []const u8,
    pin: u16,
    glb: u8,
    mc: u8,
    type: core.SignalType,
    iostd: core.LogicLevels,
    bus_maintenance: core.BusMaintenanceType,
    macrocell_type: core.MacrocellType,
    uses_input_reg: bool,
    num_unique_inputs: u16,
    num_shared_inputs: u16,
    num_pts: u8,
    num_logic_pts: u8,
    num_xor_pts: u8,
    num_ctrl_pts: u8,
    num_clusters: u8,
    num_logic_levels: u8,
    cluster_pt_usage: [16]u8,
    pg_enable_signal: []const u8,
    flags: std.EnumSet(SignalFitFlags),
};

pub const GlbInputFitSignal = struct {
    name: []const u8,
    //source: GlbInputSignal,
};

pub const GlbFitData = struct {
    glb: u8,
    inputs: [36]GlbInputFitSignal,
};

pub const FitResults = struct {
    term: std.ChildProcess.Term,
    report: []const u8,
    jedec: JedecData,
    signals: []SignalFitData,
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
    }
};


pub const Toolchain = struct {

    alloc: std.mem.Allocator,
    dir: std.fs.IterableDir,
    dir_name: [8]u8,

    pub fn init(allocator: std.mem.Allocator) !Toolchain {
        var random_bytes: [6]u8 = undefined;
        std.crypto.random.bytes(&random_bytes);
        var sub_path: [8]u8 = undefined;
        _ = std.fs.base64_encoder.encode(&sub_path, &random_bytes);

        var dir = try std.fs.cwd().makeOpenPathIterable(&sub_path, .{});
        try std.os.chdir(&sub_path);

        return Toolchain {
            .alloc = allocator,
            .dir = dir,
            .dir_name = sub_path,
        };
    }

    fn moveToParentPath(self: *Toolchain) !void {
        const parent_path = try self.dir.dir.realpathAlloc(self.alloc, "..");
        try std.os.chdir(parent_path);
    }

    pub fn deinit(self: *Toolchain, keep_files: bool) void {
        self.moveToParentPath() catch |err| {
            std.debug.print("Failed to clean up toolchain temporary directory: {}", .{ err });
        };
        self.dir.close();
        if (!keep_files) {
            std.fs.cwd().deleteTree(&self.dir_name) catch |err| {
                std.debug.print("Failed to clean up toolchain temporary directory: {}", .{ err });
            };
        }
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

        var proc_results = try std.ChildProcess.exec(.{
            .allocator = self.alloc,
            .argv = &[_][]const u8 {
                "C:\\ispLEVER_Classic2_1\\ispcpld\\bin\\lpf4k.exe",
                "-i", "test.tt4",
                "-lci", "test.lci",
                "-d", getDeviceFitterName(design.device),
                "-fmt", "PLA",
                "-v",
            },
        });

        var signals = try std.ArrayList(SignalFitData).initCapacity(self.alloc, 32);

        var log = try self.readFile("test.log");

        if (!std.mem.eql(u8, log, "Project 'test' was Fitted Successfully!\r\n")) {
            const stderr = std.io.getStdErr().writer();

            if (!std.mem.endsWith(u8, log, "Project 'test' was Fitted Successfully!\r\n")) {
                try stderr.writeAll("Fitter failed!n");
                try stderr.print("Log:\n{s}\n", .{ log });
                try stderr.print("1>\n{s}\n", .{ proc_results.stdout });
                try stderr.print("2>\n{s}\n", .{ proc_results.stderr });
                return error.FitFailed;
            } else if (!design.ignore_fitter_warnings) {
                try stderr.writeAll("Fitter had warnings!\n");
                try stderr.print("Log:\n{s}\n", .{ log });
            }
        }

        var results = FitResults {
            .term = proc_results.term,
            .report = try self.readFile("test.rpt"),
            .jedec = try JedecData.parse(self.alloc, design.device.getJedecWidth(), design.device.getJedecHeight(), "test.jed", try self.readFile("test.jed")),
            .signals = &[_]SignalFitData{},
            .glbs = try self.alloc.alloc(GlbFitData, design.device.getNumGlbs()),
        };

        try self.parseFitterReport(&results, &signals);
        results.signals = signals.items;
        return results;
    }

    fn readFile(self: *Toolchain, path: []const u8) ![]const u8 {
        var f = try std.fs.cwd().openFile(path, .{});
        defer f.close();
        return f.readToEndAlloc(self.alloc, 0x100000000);
    }

    fn parseFitterReport(self: *Toolchain, results: *FitResults, signals: *std.ArrayList(SignalFitData)) !void {
        _ = self;
        _ = results;
        _ = signals;
    }

    pub fn cleanTempDir(self: *Toolchain) !void {
        var iter = self.dir.iterate();
        while (try iter.next()) |entry| {
            try self.dir.dir.deleteFile(entry.name);
        }
    }

};