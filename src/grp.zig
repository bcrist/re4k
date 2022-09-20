const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx.zig");
const core = @import("core.zig");
const jedec = @import("jedec.zig");
const devices = @import("devices.zig");
const JedecData = jedec.JedecData;
const Fuse = jedec.Fuse;
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const GlbInputSignal = toolchain.GlbInputSignal;
const GlbInputFitSignal = toolchain.GlbInputFitSignal;
const FitResults = toolchain.FitResults;

const min_signals_to_route = 28;
const max_signals_to_route = 36;
const max_attempts_without_progress: usize = 10;

pub fn main() void {
    helper.main();
}

fn runToolchainPrep(ta: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, with_mc: bool) !FitResults {
    // The idea here is to find the column that has MC6 for each GLB.  That's the one we're going to be routing
    // signals to to discover input mux fuses.
    var design = Design.init(ta, dev);

    try design.pinAssignment(.{
        .signal = "in",
        .pin_index = dev.getClockPin(0).?.pin_index,
    });

    var glb: u8 = 0;
    while (glb < dev.getNumGlbs()) : (glb += 1) {
        var out = try std.fmt.allocPrint(ta, "out{}", .{ glb });
        var dum = try std.fmt.allocPrint(ta, "dum{}", .{ glb });

        try design.nodeAssignment(.{
            .signal = dum,
            .glb = glb,
            .mc = 1,
        });
        try design.addPT("in", dum);

        try design.nodeAssignment(.{
            .signal = out,
            .glb = glb,
            .mc = 6,
        });
        if (with_mc) {
            try design.addPT("in", out);
        } else {
            try design.addPT(.{}, out);
        }
    }

    var results = try tc.runToolchain(design);
    try helper.logReport("grp_prep_glb{}", .{ glb }, results);
    try results.checkTerm(false);
    return results;
}

const GlbTest = struct {
    arena: std.heap.ArenaAllocator,
    device: DeviceType,
    glb: u8,
    all_signals: []GlbInputFitSignal,
    temp_signal_names: [][]const u8,
    report_number: usize,
    rng: std.rand.Xoshiro256,
    columns_to_ignore: std.DynamicBitSetUnmanaged,
    fuse_bitmap: JedecData,
    fuse_map: std.AutoHashMapUnmanaged(u32, GlbInputSignal),
    fuse_count_by_gi: [36]u16,

    pub fn init(
        device: DeviceType,
        glb: u8,
        columns_to_ignore: std.DynamicBitSetUnmanaged
    ) !GlbTest {
        var ret = GlbTest {
            .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
            .device = device,
            .glb = glb,
            .all_signals = undefined,
            .temp_signal_names = undefined,
            .report_number = 0,
            .rng = std.rand.Xoshiro256.init(@bitCast(u64, std.time.milliTimestamp())),
            .columns_to_ignore = columns_to_ignore,
            .fuse_bitmap = undefined,
            .fuse_map = std.AutoHashMapUnmanaged(u32, GlbInputSignal) {},
            .fuse_count_by_gi = [_]u16 {0} ** 36,
        };
        errdefer ret.arena.deinit();
        var ga = ret.arena.allocator();

        var all_signals = try std.ArrayListUnmanaged(GlbInputFitSignal).initCapacity(
            ga, @as(usize, device.getNumGlbs()) * device.getNumMcsPerGlb()
            + device.getPins().len
            - 10 // there are always 4 JTAG and at least 6 power pins
        );

        var mc_iter = core.MacrocellIterator { .device = device };
        while (mc_iter.next()) |mcref| {
            const signal_name = try std.fmt.allocPrint(ga, "fb_{s}{}", .{ devices.getGlbName(mcref.glb), mcref.mc });
            all_signals.appendAssumeCapacity(.{
                .name = signal_name,
                .source = .{ .fb = .{
                    .glb = mcref.glb,
                    .mc = mcref.mc
                }},
            });
        }

        var pin_iter = devices.pins.InputIterator { .pins = device.getPins() };
        while (pin_iter.next()) |info| {
            const signal_name = try std.fmt.allocPrint(ga, "pin_{s}", .{ info.pin_number() });
            all_signals.appendAssumeCapacity(.{
                .name = signal_name,
                .source = .{ .pin = info.pin_index() },
            });
        }

        ret.all_signals = all_signals.items;
        ret.temp_signal_names = try ga.alloc([]const u8, device.getNumGlbInputs());
        ret.fuse_bitmap = try device.initJedecZeroes(ga);

        return ret;
    }

    pub fn deinit(self: *GlbTest) void {
        self.arena.deinit();
    }

    pub fn runToolchain(self: *GlbTest, ta: std.mem.Allocator, tc: *Toolchain) !FitResults {
        var signals_to_test = self.all_signals;
        std.debug.assert(signals_to_test.len >= 36);

        var rnd = self.rng.random();

        if (self.fuse_map.count() > 0) {
            // For the GI with the fewest known fuses, don't pick any of the known ones;
            // we want to encourage discovery of new fuses for that slot.
            // But we don't do this every time because there are some edge cases where it backfires.

            var min_gi: usize = 0;
            var min_count = self.all_signals.len;
            for (self.fuse_count_by_gi) |count, gi| {
                if (count < min_count) {
                    min_gi = gi;
                    min_count = count;
                }
            }

            var iter = self.fuse_map.iterator();
            while (iter.next()) |entry| {
                const fuse = Fuse.fromRaw(entry.key_ptr.*, self.fuse_bitmap);
                const gi = fuse.row / 2;
                if (gi == min_gi) {
                    for (signals_to_test) |signal, index| {
                        if (std.meta.eql(signal.source, entry.value_ptr.*)) {
                            swapRemove(GlbInputFitSignal, &signals_to_test, index);
                            break;
                        }
                    }
                }
            }

        }

        var signals_to_route = rnd.intRangeAtMost(usize, min_signals_to_route, max_signals_to_route);

        while (signals_to_test.len > signals_to_route) {
            swapRemove(GlbInputFitSignal, &signals_to_test, rnd.intRangeLessThan(usize, 0, signals_to_test.len));
        }

        var design = Design.init(ta, self.device);

        var signal_names = self.temp_signal_names;
        signal_names.len = 0;
        for (signals_to_test) |signal| {
            signal_names.len += 1;
            signal_names[signal_names.len - 1] = signal.name;
            switch (signal.source) {
                .fb  =>             try design.nodeAssignment(.{ .signal = signal.name }),
                .pin => |pin_index| try design.pinAssignment( .{ .signal = signal.name, .pin_index = pin_index }),
            }
        }

        for (self.all_signals) |signal| {
            switch (signal.source) {
                .pin => {},
                .fb => |mcref| {
                    try design.nodeAssignment(.{
                        .signal = signal.name,
                        .glb = mcref.glb,
                        .mc = mcref.mc,
                    });
                    if (mcref.mc == 6 and mcref.glb == self.glb) {
                        try design.addPT(signal_names, signal.name);
                    } else {
                        try design.addPT(.{}, signal.name);
                    }
                },
            }
        }

        design.adjust_input_assignments = true;
        design.parse_glb_inputs = true;

        var results = try tc.runToolchain(design);
        try helper.logReport("grp_glb{}_{}", .{ self.glb, self.report_number }, results);
        self.report_number += 1;
        //try results.checkTerm(true);
        return results;
    }

    pub fn analyzeResults(self: *GlbTest, ta: std.mem.Allocator, results: FitResults, compare: JedecData) !bool {
        if (results.failed) {
            return false;
        }
        var new_fuses: usize = 0;
        const diff = try JedecData.initDiff(ta, compare, results.jedec);
        var diff_iter = diff.iterator(.{});
        while (diff_iter.next()) |fuse| {
            if (self.fuse_bitmap.isSet(fuse) or results.jedec.isSet(fuse)) {
                continue;
            }

            const gi = fuse.row / 2;

            if (gi < self.device.getNumGlbInputs() and !self.columns_to_ignore.isSet(fuse.col)) {
                if (results.glbs[self.glb].inputs[gi]) |signal| {
                    self.fuse_bitmap.put(fuse, 1);
                    self.fuse_count_by_gi[gi] += 1;
                    try self.fuse_map.put(self.arena.allocator(), @intCast(u32, fuse.toRaw(diff)), signal.source);
                    new_fuses += 1;
                } else {
                    try helper.err("Found glb input fuse {}:{} but report did not list a source for GI {}!\n",
                        .{ fuse.row, fuse.col, gi }, self.device, .{ .glb = self.glb });
                }
            }
        }
        if (new_fuses > 0) {
            std.debug.print("Found {} new fuses in GLB {} (total {})\n", .{ new_fuses, self.glb, self.fuse_map.count() });
        }
        return new_fuses > 0;
    }

};

fn swapRemove(comptime T: type, slice: *[]T, index_to_remove: usize) void {
    const s = slice.*;
    if (s.len - 1 != index_to_remove) {
        const old_item = s[index_to_remove];
        s[index_to_remove] = s[s.len - 1];
        s[s.len - 1] = old_item;
    }
    slice.*.len -= 1;
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    var progress = std.Progress{};
    const prog_root = progress.start("", dev.getNumGlbs() + 1);
    if (progress.terminal == null) {
        std.debug.print("progress.terminal == null\n", .{});
    }
    prog_root.activate();

    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("global_routing_pool");

    const results_empty = try runToolchainPrep(ta, tc, dev, false);
    const results_with_mc = try runToolchainPrep(ta, tc, dev, true);

    const mux_size_str = helper.extract(results_empty.report, "GLB Input Mux Size   :  ", "\r\n") orelse return error.FitterFormatError;
    const mux_size = try std.fmt.parseInt(usize, mux_size_str, 10);
    const expected_fuses = mux_size * dev.getNumGlbInputs();

    var columns_to_ignore = try std.DynamicBitSetUnmanaged.initEmpty(pa, dev.getJedecWidth());

    var diff = try JedecData.initDiff(ta, results_empty.jedec, results_with_mc.jedec);
    var diff_iter = diff.iterator(.{});
    while (diff_iter.next()) |fuse| {
        if (fuse.row < 2 * dev.getNumGlbInputs()) {
            columns_to_ignore.set(fuse.col);
        }
    }

    prog_root.completeOne();
    prog_root.end();

    var glb: u8 = 0;
    while (glb < dev.getNumGlbs()) : (glb += 1) {
        var prog_glb = prog_root.start(devices.getGlbName(glb), expected_fuses);
        prog_glb.activate();

        var state = try GlbTest.init(dev, glb, columns_to_ignore);
        defer state.deinit();

        var results_0 = try state.runToolchain(ta, tc);
        while (results_0.failed) {
            results_0 = try state.runToolchain(ta, tc);
        }
        var results_1 = try state.runToolchain(ta, tc);
        while (results_1.failed) {
            results_1 = try state.runToolchain(ta, tc);
        }

        _ = try state.analyzeResults(ta, results_0, results_1.jedec);
        _ = try state.analyzeResults(ta, results_1, results_0.jedec);

        var base_jedec = try results_0.jedec.clone(state.arena.allocator());

        var attempt: usize = 0;
        while (state.fuse_map.count() < expected_fuses and attempt < max_attempts_without_progress) : (attempt += 1) {
            prog_glb.setCompletedItems(state.fuse_map.count());
            progress.maybeRefresh();
            try tc.cleanTempDir();
            helper.resetTemp();

            var results = try state.runToolchain(ta, tc);
            if (try state.analyzeResults(ta, results, base_jedec)) {
                // made progress; reset attempts
                attempt = 0;
            }
        }

        if (state.fuse_map.count() != expected_fuses) {
            try std.io.getStdErr().writer().print("Expected {} glb input mux fuses for device {s} glb {} but found {}!\n",
                .{ expected_fuses, @tagName(dev), glb, state.fuse_map.count() });
        }

        try writer.expression("glb");
        try writer.printRaw("{}", .{ glb });
        try writer.expression("name");
        try writer.printRaw("{s}", .{ devices.getGlbName(glb) });
        try writer.close();
        writer.setCompact(false);

        var gi: i64 = -1;
        var iter = state.fuse_bitmap.iterator(.{});
        while (iter.next()) |fuse| {
            if (gi != fuse.row / 2) {
                if (gi != -1) {
                    try writer.close();
                }
                gi = fuse.row / 2;
                try writer.expression("gi");
                try writer.printRaw("{}", .{ gi });
                writer.setCompact(false);
            }

            try writer.expression("fuse");
            try writer.printRaw("{} {}", .{ fuse.row, fuse.col });

            if (state.fuse_map.get(@intCast(u32, fuse.toRaw(state.fuse_bitmap)))) |source| {
                switch (source) {
                    .fb => |mcref| {
                        try writer.expression("glb");
                        try writer.printRaw("{}", .{ mcref.glb });
                        try writer.expression("name");
                        try writer.printRaw("{s}", .{ devices.getGlbName(mcref.glb) });
                        try writer.close(); // name
                        try writer.close(); // glb
                        try writer.expression("mc");
                        try writer.printRaw("{}", .{ mcref.mc });
                        try writer.close(); // mc
                    },
                    .pin => |pin_index| {
                        try writer.expression("pin");
                        try writer.printRaw("{s}", .{ dev.getPins()[pin_index].pin_number() });
                        try writer.close(); // pin
                    },
                }
            }

            try writer.close(); // fuse
        }
        try writer.close(); // last gi
        try writer.close(); // glb
        prog_glb.end();
    }

    try writer.done();
    prog_root.completeOne();
}
