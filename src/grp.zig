const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const jedec = lc4k.jedec;
const device_info = @import("device_info.zig");
const JedecData = jedec.JedecData;
const Fuse = jedec.Fuse;
const DeviceInfo = device_info.DeviceInfo;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const GlbInputSignal = toolchain.GlbInputSignal;
const GlbInputFitSignal = toolchain.GlbInputFitSignal;
const FitResults = toolchain.FitResults;
const GISet = toolchain.GISet;
const GlbInputSet = toolchain.GlbInputSet;
const MacrocellIterator = helper.MacrocellIterator;
const InputIterator = helper.InputIterator;
const getGlbName = lc4k.getGlbName;

const max_routed_signals = 33;

pub fn main() void {
    helper.main();
}

var report_number: usize = 0;
fn runToolchain(ta: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, signals_to_test: GlbInputSet, all_signals: []const GlbInputFitSignal) !FitResults {
    var design = Design.init(ta, dev);

    var temp_signal_names_storage = [_][]const u8 { "" } ** 36;
    var signal_names: [][]const u8 = &temp_signal_names_storage;
    signal_names.len = 0;

    std.debug.assert(signals_to_test.count() <= 36);
    var iter = signals_to_test.iterator(all_signals);
    while (iter.next()) |signal| {
        signal_names.len += 1;
        std.debug.assert(signal_names.len <= temp_signal_names_storage.len);
        signal_names[signal_names.len - 1] = signal.name;
        switch (signal.source) {
            .fb  =>      try design.nodeAssignment(.{ .signal = signal.name }),
            .pin => |id| try design.pinAssignment( .{ .signal = signal.name, .pin = id }),
        }
    }

    for (all_signals) |signal| {
        switch (signal.source) {
            .pin => {},
            .fb => |mcref| {
                try design.nodeAssignment(.{
                    .signal = signal.name,
                    .glb = mcref.glb,
                    .mc = mcref.mc,
                });
                if (mcref.mc == 6) {
                    try design.addPT(signal_names, signal.name);
                } else {
                    try design.addPT(.{}, signal.name);
                }
            },
        }
    }

    design.adjust_input_assignments = true;
    design.parse_glb_inputs = true;
    design.max_fit_time_ms = 500;

    const results = try tc.runToolchain(design);
    try helper.logResults(dev.device, "grp_{}", .{ report_number }, results);
    report_number += 1;
    //try results.checkTerm();
    return results;
}

fn getAllSignals(pa: std.mem.Allocator, dev: *const DeviceInfo) ![]const GlbInputFitSignal {
    var all_signals = try std.ArrayListUnmanaged(GlbInputFitSignal).initCapacity(
        pa, dev.num_mcs + dev.all_pins.len - 10 // there are always 4 JTAG and at least 6 power pins
    );

    var mc_iter = MacrocellIterator { .dev = dev };
    while (mc_iter.next()) |mcref| {
        const signal_name = try std.fmt.allocPrint(pa, "fb_{s}{}", .{ getGlbName(mcref.glb), mcref.mc });
        all_signals.appendAssumeCapacity(.{
            .name = signal_name,
            .source = .{ .fb = .{
                .glb = mcref.glb,
                .mc = mcref.mc
            }},
        });
    }

    var pin_iter = InputIterator { .pins = dev.all_pins };
    while (pin_iter.next()) |pin| {
        const signal_name = try std.fmt.allocPrint(pa, "pin_{s}", .{ pin.id });
        all_signals.appendAssumeCapacity(.{
            .name = signal_name,
            .source = .{ .pin = pin.id },
        });
    }

    return all_signals.items;
}

const GlbData = struct {
    dev: *const DeviceInfo,
    glb: u8,
    fuse_bitmap: JedecData,
    fuse_map: std.AutoHashMap(Fuse, GlbInputSignal),

    pub fn init(alloc: std.mem.Allocator, dev: *const DeviceInfo, glb: u8) !GlbData {
        return GlbData {
            .dev = dev,
            .glb = glb,
            .fuse_bitmap = try JedecData.initEmpty(alloc, dev.jedec_dimensions),
            .fuse_map = std.AutoHashMap(Fuse, GlbInputSignal).init(alloc),
        };
    }

    pub fn analyzeResults(self: *GlbData, results: FitResults) !usize {
        if (results.failed) {
            return 0;
        }

        var new_fuses: usize = 0;

        const mux_size_str = helper.extract(results.report, "GLB Input Mux Size   :  ", "\r\n") orelse return error.FitterFormatError;
        const mux_size = try std.fmt.parseInt(usize, mux_size_str, 10);

        var gi_iter = GISet.initFull().iterator();
        while (gi_iter.next()) |gi| {
            const signal = blk: {
                if (results.glbs[self.glb].inputs[gi]) |s| {
                    break :blk s;
                } else {
                    continue;
                }
            };

            var fuse_range = self.dev.getGIRange(self.glb, gi);
            std.debug.assert(fuse_range.count() == mux_size);

            var iter = fuse_range.iterator();
            while (iter.next()) |fuse| {
                if (!results.jedec.isSet(fuse) and !self.fuse_bitmap.isSet(fuse)) {
                    self.fuse_bitmap.put(fuse, 1);
                    try self.fuse_map.put(fuse, signal.source);
                    new_fuses += 1;
                }
            }
        }

        // if (new_fuses > 0) {
        //     std.debug.print("Found {} new fuses in GLB {} (total {})\n", .{ new_fuses, self.glb, self.fuse_map.count() });
        // }

        return new_fuses;
    }

};

const TestData = struct {
    ta: std.mem.Allocator,
    tc: *Toolchain,
    rng: std.rand.Xoshiro256,
    dev: *const DeviceInfo,
    all_signals: []const GlbInputFitSignal,
    glbs: []GlbData,
    tested_input_sets: std.AutoHashMap(GlbInputSet, void),
    dead_branches: usize = 0,

    pub fn init(ta: std.mem.Allocator, pa: std.mem.Allocator, gpa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo) !TestData {
        const glbs = try pa.alloc(GlbData, dev.num_glbs);
        for (glbs, 0..) |*glb, i| {
            glb.* = try GlbData.init(gpa, dev, @intCast(i));
        }

        return TestData {
            .ta = ta,
            .tc = tc,
            .rng = std.rand.Xoshiro256.init(@bitCast(std.time.milliTimestamp())),
            .dev = dev,
            .all_signals = try getAllSignals(pa, dev),
            .glbs = glbs,
            .tested_input_sets = std.AutoHashMap(GlbInputSet, void).init(gpa),
        };
    }

    pub fn runTest(self: *TestData, signals_to_test: GlbInputSet) !bool {
        if (self.tested_input_sets.contains(signals_to_test)) {
            return false;
        }

        // {
        //     std.debug.print("Testing signals:", .{});
        //     var iter = signals_to_test.iterator(self.all_signals);
        //     while (iter.next()) |signal| {
        //         std.debug.print(" {s}", .{ signal.name });
        //     }
        //     std.debug.print("\n", .{});
        // }

        try self.tested_input_sets.put(signals_to_test, {});

        try self.tc.cleanTempDir();
        helper.resetTemp();

        const results = try runToolchain(self.ta, self.tc, self.dev, signals_to_test, self.all_signals);
        var fuses_found: ?usize = null;
        for (self.glbs) |*glb| {
            const found = try glb.analyzeResults(results);
            if (fuses_found) |found_in_other_glb| {
                if (found != found_in_other_glb) {
                    try helper.err("Report {}: Expected to find {} fuses but found {}!", .{ report_number - 1, found_in_other_glb, found }, self.dev, .{ .glb = glb.glb });
                }
                fuses_found = @max(found_in_other_glb, found);
            } else {
                fuses_found = found;
            }
        }

        if ((fuses_found orelse 0) > 0) {
            // std.debug.print("Found {} new fuses\n", .{ fuses_found.? });
            self.dead_branches = 0;
            return true;
        } else {
            self.dead_branches += 1;
            return false;
        }
    }

    pub fn sortSignalsByLeastGIs(self: TestData, signals: []GlbInputFitSignal) !void {
        const GICountsMap = std.HashMap(GlbInputSignal, usize, GlbInputSignal.HashContext, 80);

        var gi_counts = GICountsMap.init(self.ta);
        defer gi_counts.deinit();

        const all_gis = GISet.initFull();
        var gi_iter = all_gis.iterator();
        while (gi_iter.next()) |gi| {
            var fuse_iter = self.dev.getGIRange(0, gi).iterator();
            while (fuse_iter.next()) |fuse| {
                if (self.glbs[0].fuse_map.get(fuse)) |signal| {
                    const result = try gi_counts.getOrPut(signal);
                    var new_count: usize = 1;
                    if (result.found_existing) {
                        new_count += result.value_ptr.*;
                    }
                    result.value_ptr.* = new_count;
                }
            }
        }

        const SortCtx = struct {
            fn lessThan(context: *const GICountsMap, lhs: GlbInputFitSignal, rhs: GlbInputFitSignal) bool {
                const lhs_count: usize = context.get(lhs.source) orelse 0;
                const rhs_count: usize = context.get(rhs.source) orelse 0;
                return lhs_count < rhs_count;
            }
        };
        std.sort.block(GlbInputFitSignal, signals, &gi_counts, SortCtx.lessThan);
    }

    fn getGIsContainingSignal(self: TestData, signal: GlbInputSignal, fromSet: GISet) GISet {
        var gis_containing_signal = GISet.initEmpty();
        var gi_iter = fromSet.iterator();
        while (gi_iter.next()) |gi| {
            var fuse_iter = self.dev.getGIRange(0, gi).iterator();
            while (fuse_iter.next()) |fuse| {
                if (self.glbs[0].fuse_map.get(fuse)) |fuse_signal| {
                    if (signal.eql(fuse_signal)) {
                        gis_containing_signal.add(gi);
                    }
                }
            }
        }
        return gis_containing_signal;
    }

    fn getSignalsInGIs(self: TestData, gis: GISet) GlbInputSet {
        var signals = GlbInputSet.initEmpty();
        var gi_iter = gis.iterator();
        while (gi_iter.next()) |gi| {
            var fuse_iter = self.dev.getGIRange(0, gi).iterator();
            while (fuse_iter.next()) |fuse| {
                if (self.glbs[0].fuse_map.get(fuse)) |fuse_signal| {
                    signals.add(fuse_signal, self.all_signals);
                }
            }
        }
        return signals;
    }

    pub fn findNewFuseForSignal(self: *TestData, signal: GlbInputSignal, additional_signals: GlbInputSet, depth: usize) !bool {
        var signals_to_test = additional_signals;
        signals_to_test.add(signal, self.all_signals);

        if (signals_to_test.count() > max_routed_signals) {
            _ = signals_to_test.removeRandom(self.rng.random(), signals_to_test.count() - max_routed_signals);
        }
        if (try self.runTest(signals_to_test)) {
            return true;
        }

        var gis = self.getGIsContainingSignal(signal, GISet.initFull());
        var gi_iter = gis.iterator();
        while (gi_iter.next()) |gi| {
            var gi_signals = self.getSignalsInGIs(GISet.initSingle(gi));
            gi_signals.removeAll(signals_to_test);

            var signal_iter = gi_signals.iterator(self.all_signals);
            while (signal_iter.next()) |extra_signal| {
                signals_to_test.add(extra_signal.source, self.all_signals);
            }
        }

        if (signals_to_test.count() > max_routed_signals) {
            _ = signals_to_test.removeRandom(self.rng.random(), signals_to_test.count() - max_routed_signals);
        }
        if (try self.runTest(signals_to_test)) {
            return true;
        }

        if (depth > 0) {
            gi_iter = gis.iterator();
            while (gi_iter.next()) |gi| {
                var gi_signals = self.getSignalsInGIs(GISet.initSingle(gi));
                var signal_iter = gi_signals.iterator(self.all_signals);
                while (signal_iter.next()) |extra_signal| {
                    if (try self.findNewFuseForSignal(extra_signal.source, signals_to_test, depth - 1)) {
                        return true;
                    }
                }
            }
        }

        return false;
    }

};


pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer) !void {
    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("global_routing_pool");

    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = false }) {};

    var test_data = try TestData.init(ta, pa, gpa.allocator(), tc, dev);
    const expected_fuses_per_glb = dev.getGIRange(0, 0).count() * 36;

    // First we start off by simply randomly selecting signals to route.
    // This works well to find 75-95% of the possible fuses, but it starts
    // to break down quickly after that, so we'll switch strategies once
    // we reach five attempts in a row that fail to discover any new fuses.
    var failed_attempts: usize = 0;
    while (test_data.glbs[0].fuse_map.count() < expected_fuses_per_glb and failed_attempts < 5) {
        var all_signals_set = GlbInputSet.initFull(test_data.all_signals);
        const signals = all_signals_set.removeRandom(test_data.rng.random(), 30);
        if (!try test_data.runTest(signals)) {
            failed_attempts += 1;
        } else {
            failed_attempts = 0;
        }
    }

    const signals_by_least_gis = try pa.dupe(GlbInputFitSignal, test_data.all_signals);

    var max_depth: usize = 1;
    fuse_found: while (test_data.glbs[0].fuse_map.count() < expected_fuses_per_glb) {
        // All signals should have approximately the same number of GIs it is associated with
        // so the missing fuses likely belong to signals with the fewest known GIs/fuses.
        // Therefore, we try to create signal sets whereby these signals are forced to be displaced
        // from their current known options, ideally while specifying as few other signals as possible.
        try test_data.sortSignalsByLeastGIs(signals_by_least_gis);
        for (signals_by_least_gis) |signal| {
            if (try test_data.findNewFuseForSignal(signal.source, GlbInputSet.initEmpty(), max_depth)) {
                continue :fuse_found;
            }
        }
        if (max_depth < 5) {
            max_depth += 1;
        } else {
            // Something is wrong, give up.
            break;
        }
    }

    for (test_data.glbs) |glb_data| {
        if (glb_data.fuse_map.count() != expected_fuses_per_glb) {
            try helper.err("Expected {} glb input mux fuses but found {}!",
                .{ expected_fuses_per_glb, glb_data.fuse_map.count() }, dev, .{ .glb = glb_data.glb });
        }

        try helper.writeGlb(writer, glb_data.glb);

        var gi: i64 = -1;
        var iter = glb_data.fuse_bitmap.iterator(.{});
        while (iter.next()) |fuse| {
            if (gi != fuse.row / 2) {
                if (gi != -1) {
                    try writer.close();
                }
                gi = @intCast(fuse.row / 2);
                try writer.expression("gi");
                try writer.int(gi, 10);
                writer.set_compact(false);
            }

            try writer.expression("fuse");
            try writer.int(fuse.row, 10);
            try writer.int(fuse.col, 10);

            if (glb_data.fuse_map.get(fuse)) |source| {
                switch (source) {
                    .fb => |mcref| {
                        try helper.writeGlb(writer, mcref.glb);
                        writer.set_compact(true);
                        try writer.close(); // glb
                        try helper.writeMc(writer, mcref.mc);
                        try writer.close(); // mc
                    },
                    .pin => |id| {
                        try helper.writePin(writer, dev.getPin(id).?);
                        try writer.close(); // pin
                    },
                }
            }

            try writer.close(); // fuse
        }
        if (gi != -1) {
            try writer.close(); // last gi
        }
        try writer.close(); // glb
    }

    try writer.done();
}
