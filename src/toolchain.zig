const std = @import("std");
const core = @import("core.zig");

const DeviceInfo = core.DeviceInfo;
const JedecData = core.JedecData;

pub const Design = struct {
    // TODO
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
    source: GlbInputSignal,
};

pub const GlbFitData = struct {
    glb: u8,
    inputs: [36]GlbInputFitSignal,
};

pub const FitResults = struct {
    term: Term,
    stdout: []u8,
    stderr: []u8,
    log: []u8,
    report: []u8,
    jedec: JedecData,
    signals: []SignalFitData,
    glbs: []GlbFitData,
};


const Toolchain = struct {

    alloc: std.mem.Allocator,
    dir: std.fs.Dir,

    fn init(allocator: std.mem.Allocator) !Self {
        var random_bytes: [6]u8 = undefined;
        std.crypto.random.bytes(&random_bytes);
        var sub_path: [8]u8 = undefined;
        _ = std.fs.base64_encoder.encode(&sub_path, &random_bytes);

        var cwd = std.fs.cwd();
        var dir = try std.fs.cwd().makeOpenPath(&sub_path, .{ .iterate = true });

        return Self {
            .alloc = allocator,
            .dir = dir,
        };
    }

    fn cleanup(self: *Toolchain) !void {
        try dir.deleteTree(".");
    }

    fn deinit() void {
        dir.close();
    }

    fn runToolchain(self: *Self, device: DeviceInfo, design: Design) !void {

        self.writeTt4(device, design);
        self.writeLci(device, design);

        var proc_results = try std.ChildProcess.exec(.{
            .allocator = self.alloc,
            .argv = &[_][]const u8 {
                "C:\\ispLEVER_Classic2_1\ispcpld\\bin\\lpf4k.exe",
                "-i", "test.tt4",
                "-lci", "test.lci",
                "-d", device.fitter_name,
                "-fmt", "PLA",
                "-v",
            },
        });


        var signals = std.ArrayList(SignalFitData).initCapacity(self.alloc, 32);

        var results = FitResults {
            .term = proc_results.term,
            .stdout = proc_results.stdout,
            .stderr = proc_results.stderr,
            .log = try self.readLog(),
            .report = try self.readReport(),
            .jedec = try JedecData.init(allocator, device.jedec.width, device.jedec.height),
            .signals = &[_]SignalFitData{},
            .glbs = try self.temp.allocator().alloc(GlbFitData, device.num_glbs),
        };

        self.parseReport(results.report, &signals, results.glbs);
        results.signals = signals.items;
        return results;

        // switch (results.term) {
        //     .Exited => |code| {
        //         if (code != 0) {
        //             try std.io.getStdErr().writer().print("lpf4k returned code {}", .{ code });
        //             return error.FitterError;
        //         }
        //     },
        //     .Signal => |s| {
        //         try std.io.getStdErr().writer().print("lpf4k signalled {}", .{ s });
        //         return error.FitterError;
        //     },
        //     .Stopped => |s| {
        //         try std.io.getStdErr().writer().print("lpf4k stopped with {}", .{ s });
        //         return error.FitterError;
        //     },
        //     .Unknown => |s| {
        //         try std.io.getStdErr().writer().print("lpf4k terminated unexpectedly with {}", .{ s });
        //         return error.FitterError;
        //     },
        // }
    }

    fn readFitterReport(self: *Self, results: *FitResults) !void {

    }

    fn cleanTempDir(self: *Self) void {
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            try dir.deleteFile(entry.name);
        }
    }


};