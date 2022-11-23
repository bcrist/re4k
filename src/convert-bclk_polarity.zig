const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const jedec = @import("jedec.zig");
const core = @import("core.zig");
const devices = @import("devices.zig");
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JedecData = jedec.JedecData;
const Fuse = jedec.Fuse;

pub fn main() void {
    helper.main(1);
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    const input_file = helper.getInputFile("bclk_polarity.sx") orelse return error.MissingInputFile;
    std.debug.assert(input_file.device.getNumGlbs() == dev.getNumGlbs());
    std.debug.assert(input_file.device.getJedecWidth() == dev.getJedecWidth());
    std.debug.assert(input_file.device.getJedecHeight() == dev.getJedecHeight());

    var stream = std.io.fixedBufferStream(input_file.contents);
    var parser = sx.reader(ta, stream.reader());
    defer parser.deinit();

    parseAndWrite(dev, &parser, writer) catch |e| switch (e) {
        error.SExpressionSyntaxError => {
            var ctx = try parser.getNextTokenContext();
            try ctx.printForString(input_file.contents, std.io.getStdErr().writer(), 120);
            return e;
        },
        else => return e,
    };

    _ = pa;
    _ = tc;
}

fn parseAndWrite(dev: DeviceType, parser: *sx.Reader(std.io.FixedBufferStream([]const u8).Reader), writer: *sx.Writer(std.fs.File.Writer)) !void {
    _ = try parser.requireAnyExpression();
    try parser.requireExpression("bclk_polarity");
    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("bclk_polarity");

    var glb: u8 = 0;
    while (glb < dev.getNumGlbs()) : (glb += 1) {
        try parser.requireExpression("glb");
        var found_glb = try parser.requireAnyInt(u8, 10);
        std.debug.assert(found_glb == glb);

        if (try parser.expression("name")) {
            try parser.ignoreRemainingExpression();
        }
        try helper.writeGlb(writer, glb);

        var base_clk: usize = 0;
        while (base_clk < 4) : (base_clk += 2) {
            try parser.requireExpression("clk");
            var found_clk_a = try parser.requireAnyInt(u8, 10);
            var found_clk_b = try parser.requireAnyInt(u8, 10);
            std.debug.assert(found_clk_a == base_clk);
            std.debug.assert(found_clk_b == base_clk + 1);
            try writer.expression("clk");
            try writer.int(base_clk, 10);
            try writer.int(base_clk + 1, 10);

            while (try parser.expression("fuse")) {
                var row = try parser.requireAnyInt(u16, 10);
                var col = try parser.requireAnyInt(u16, 10);
                var val = if (try parser.expression("value")) blk: {
                    var val = try parser.requireAnyInt(u16, 10);
                    try parser.requireClose();
                    break :blk val;
                } else 1;

                try helper.writeFuseOptValue(writer, Fuse.init(row, col), val);
                try parser.requireClose();
            }

            try writer.close(); // clk
            try parser.requireClose(); // clk
        }
        try writer.close(); // glb
        try parser.requireClose(); // glb
    }

    while (try parser.expression("value")) {
        var val = try parser.requireAnyInt(usize, 10);
        var mode = try parser.requireAnyString();
        if (std.mem.eql(u8, mode, "first_complemented") or dev.getClockPin(1) != null) {
            try helper.writeValue(writer, val, mode);
        }
        try parser.requireClose(); // value
    }

    try writer.done();
    try parser.requireClose(); // bclk_polarity
    try parser.requireClose(); // device
}
