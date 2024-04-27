const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const jedec = lc4k.jedec;
const lc4k = @import("lc4k");
const device_info = @import("device_info.zig");
const DeviceInfo = device_info.DeviceInfo;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JedecData = jedec.JedecData;
const Fuse = jedec.Fuse;

pub fn main() void {
    helper.main();
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const DeviceInfo, writer: *sx.Writer) !void {
    const input_file = helper.getInputFile("bclk_polarity.sx") orelse return error.MissingInputFile;
    const input_dev = DeviceInfo.init(input_file.device_type);
    std.debug.assert(input_dev.num_glbs == dev.num_glbs);
    std.debug.assert(input_dev.jedec_dimensions.eql(dev.jedec_dimensions));

    var stream = std.io.fixedBufferStream(input_file.contents);
    const reader = stream.reader();
    var parser = sx.reader(ta, reader.any());
    defer parser.deinit();

    parseAndWrite(dev, &parser, writer) catch |e| switch (e) {
        error.SExpressionSyntaxError => {
            var ctx = try parser.token_context();
            try ctx.print_for_string(input_file.contents, std.io.getStdErr().writer(), 120);
            return e;
        },
        else => return e,
    };

    _ = pa;
    _ = tc;
}

fn parseAndWrite(dev: *const DeviceInfo, parser: *sx.Reader, writer: *sx.Writer) !void {
    _ = try parser.require_any_expression();
    try parser.require_expression("bclk_polarity");
    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("bclk_polarity");

    var glb: u8 = 0;
    while (glb < dev.num_glbs) : (glb += 1) {
        try parser.require_expression("glb");
        const found_glb = try parser.require_any_int(u8, 10);
        std.debug.assert(found_glb == glb);

        if (try parser.expression("name")) {
            try parser.ignore_remaining_expression();
        }
        try helper.writeGlb(writer, glb);

        var base_clk: usize = 0;
        while (base_clk < 4) : (base_clk += 2) {
            try parser.require_expression("clk");
            const found_clk_a = try parser.require_any_int(u8, 10);
            const found_clk_b = try parser.require_any_int(u8, 10);
            std.debug.assert(found_clk_a == base_clk);
            std.debug.assert(found_clk_b == base_clk + 1);
            try writer.expression("clk");
            try writer.int(base_clk, 10);
            try writer.int(base_clk + 1, 10);

            while (try parser.expression("fuse")) {
                const row = try parser.require_any_int(u16, 10);
                const col = try parser.require_any_int(u16, 10);
                const val = if (try parser.expression("value")) blk: {
                    const val = try parser.require_any_int(u16, 10);
                    try parser.require_close();
                    break :blk val;
                } else 1;

                try helper.writeFuseOptValue(writer, Fuse.init(row, col), val);
                try parser.require_close();
            }

            try writer.close(); // clk
            try parser.require_close(); // clk
        }
        try writer.close(); // glb
        try parser.require_close(); // glb
    }

    while (try parser.expression("value")) {
        const val = try parser.require_any_int(usize, 10);
        const mode = try parser.require_any_string();
        if (std.mem.eql(u8, mode, "first_complemented") or dev.clock_pins.len >= 4) {
            try helper.writeValue(writer, val, mode);
        }
        try parser.require_close(); // value
    }

    try writer.done();
    try parser.require_close(); // bclk_polarity
    try parser.require_close(); // device
}
