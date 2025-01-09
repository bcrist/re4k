const std = @import("std");
const microbe = @import("microbe");
const clock = microbe.clock;
const svf_file = @import("svf_file");
const LC4kCommand = svf_file.JtagCommand;
const Device_Type = @import("common").Device_Type;

const device = Device_Type.LC4032ZE_TQFP48;
const width = device.get().jedec_dimensions.width();
const height = device.get().jedec_dimensions.height();
const RowDataType = std.meta.Int(.unsigned, width);

pub const clocks = microbe.ClockConfig {
    .hsi_enabled = true,
    .pll = .{
        .source = .hsi,
        .r_frequency_hz = 64_000_000,
    },
    .sys_source = .{ .pll_r = {}},
    .tick = .{ .period_ns = 1_000_000 },
};

pub const interrupts = struct {
    pub const SysTick = clock.handleTickInterrupt;
};

var uart: microbe.Uart(.{
    .baud_rate = 128000,
    .tx = .PA9,
    .rx = .PA10,
    .cts = .PA11,
    // .rts = .PA12,
}) = undefined;

var jtag: microbe.jtag.Adapter(.{
    .tck = .PB6,
    .tms = .PB5,
    .tdi = .PB4,
    .tdo = .PB3,
    .max_frequency_hz = 1_000_000,
    .chain = &.{ LC4kCommand },
}) = undefined;

// Connects to serial adapter's CTS.
// We manage the state manually rather than relying on the UART's RTS logic, because that
// only asserts once the fifo is completely full, but most USB serial adapters don't
// respond to CTS instantly on the next byte.
const RTS = microbe.Bus("RTS", .{ .PA12 }, .{ .mode = .output });

pub fn log(comptime message_level: std.log.Level, comptime scope: @Type(.enum_literal), comptime format: []const u8, args: anytype) void {
    const rts = RTS.get();
    RTS.modifyInline(1);
    uart.writer().print("\r\n{s}: {s}: ", .{ @tagName(message_level), @tagName(scope) }) catch {};
    uart.writer().print(format, args) catch {};
    uart.writer().writeAll("\r\n") catch {};
    RTS.modifyInline(rts);
}

pub fn main() !void {
    jtag = @TypeOf(jtag).init();
    uart = @TypeOf(uart).init();
    RTS.init();
    uart.start();
    clock.delay(.{ .ms = 100 });
    reset();

    while (true) {
        process() catch |err| {
            RTS.modifyInline(1);
            const s = switch (err) {
                error.Overrun => "Input buffer overrun detected!  Please use a serial connection capable of CTS flow control.\r\n",
                error.FramingError => "UART framing error detected!\r\n",
                error.NoiseError => "UART noise error detected!\r\n",
                error.EndOfStream, error.BreakInterrupt => "UART connection broken!\r\n",
                error.BadIDCode => "Chip reported incorrect IDCODE; possible hardware failure?\r\n",
                error.Abort => blk: {
                    try uart.writer().writeAll("Aborting device programming due to unexpected character; hit Escape to reset.\r\n");
                    RTS.modifyInline(0);
                    while (try uart.reader().readByte() != 0x1B) {}
                    RTS.modifyInline(1);
                    break :blk "In the pipe, five by five.\r\n";
                },
            };
            try uart.writer().writeAll(s);
            reset();
        };
    }
}

fn process() !void {
    if (!uart.canRead()) {
        RTS.modifyInline(0);
    }
    switch (try uart.reader().readByte()) {
        '@' => try readIdCode(),
        '?' => try readChip(),
        '`' => {
            try prepWriteChip();
            try writeChip();
        },
        0x1b => {
            RTS.modifyInline(1);
            try uart.writer().writeAll("There's always money in the banana stand.\r\n");
        },
        else => |c| {
            RTS.modifyInline(1);
            try uart.writer().print("Unrecognized command: '{}'\r\n", .{
                std.fmt.fmtSliceEscapeLower(std.mem.asBytes(&c)),
            });
        },
    }
}

fn readIdCode() !void {
    RTS.modifyInline(1);
    const idcode = doCommand(.IDCODE, u32, 0xFFFF_FFFF);
    try uart.writer().print("IDCODE: {X:0>8}\r\n", .{ idcode });
}

fn readChip() !void {
    RTS.modifyInline(1);

    const writer = uart.writer();

    const idcode = doCommand(.IDCODE, u32, 0xFFFF_FFFF);
    if (idcode != svf_file.getIDCode(device.get())) {
        return error.BadIDCode;
    }

    _ = doCommand(.SAMPLE_PRELOAD, std.meta.Int(.unsigned, svf_file.getBoundaryScanLength(device.get())), 0);
    doCommand(.ISC_ENABLE, void, {});

    try writer.writeByte(0x2);
    try writer.writeAll("*\r\n");
    try writer.writeAll("QP48*\r\n");
    try writer.print("QF{}*\r\n", .{ comptime (width * height) });
    try writer.writeAll("F0*\r\n");

    try verifyInternal();

    const usercode = doCommand(.READ_USERCODE, u32, 0xFFFFFFFF);
    try writer.print("U{b:0>32}*\r\n", .{ usercode });
    try writer.writeByte(0x3); // ETX

    reset();
}

fn verifyInternal() !void {
    const writer = uart.writer();

    _ = doCommand(.ISC_ADDRESS_SHIFT, u100, 0x8000000000000000000000000);
    doCommand(.ISC_READ, void, {});

    var row: u16 = 0;
    var base_fuse: u32 = 0;
    while (row < height) : (row += 1) {
        idleForCommand(.ISC_READ);
        var data = jtag.tap(0).data(RowDataType, 0, .idle);

        try writer.print("L{:0>6} ", .{ base_fuse });

        var bits_remaining: u16 = width;
        while (bits_remaining > 0) : (bits_remaining -= 1) {
            const b: u8 = if (@truncate(u1, data) == 0) '0' else '1';
            try writer.writeByte(b);
            data >>= 1;
        }

        try writer.writeAll("*\r\n");
        base_fuse += width;
    }

}

const JedecParseData = struct {
    program_security_bit: bool = false,
    usercode: ?u32 = null,
    fuse_index: u32 = 0,
    bits_left_in_row: u32 = width,
    row_data: RowDataType = 0,
    in_l_data: bool = false,
};

fn parseJedec(data: *JedecParseData) !void {
    var reader = uart.reader();
    while (true) {
        if (data.in_l_data) {
            switch (try reader.readByte()) {
                '0', '1' => |b| {
                    data.bits_left_in_row -= 1;
                    data.fuse_index += 1;
                    data.row_data >>= 1;
                    if (b == '1') {
                        data.row_data |= 1 << (width - 1);
                    }

                    if (data.bits_left_in_row == 0) {
                        return;
                    }
                },
                ' ', '\t', '\r', '\n' => {},
                '*' => {
                    data.in_l_data = false;
                },
                else => return error.Abort,
            }
        } else switch (try reader.readByte()) {
            'G' => {
                data.program_security_bit = switch (try reader.readByte()) {
                    '0' => false,
                    '1' => true,
                    else => return error.Abort,
                };
                switch (try reader.readByte()) {
                    '*' => {},
                    else => return error.Abort,
                }
                RTS.modifyInline(1);
                if (data.program_security_bit) {
                    try uart.writer().writeAll("Security bit enabled\r\n");
                } else {
                    try uart.writer().writeAll("Security bit disabled\r\n");
                }
                RTS.modifyInline(0);
            },
            'U' => {
                var usercode: u32 = 0;
                var bits_remaining: u8 = 32;
                while (bits_remaining > 0) : (bits_remaining -= 1) {
                    usercode <<= 1;
                    switch (try reader.readByte()) {
                        '0' => {},
                        '1' => usercode |= 1,
                        else => return error.Abort,
                    }
                }
                if (try reader.readByte() != '*') return error.Abort;
                data.usercode = usercode;
                RTS.modifyInline(1);
                try uart.writer().writeAll("User code read\r\n");
                RTS.modifyInline(0);
            },
            'L' => {
                var fuse_index: u32 = 0;
                while (true) {
                    switch (try reader.readByte()) {
                        '0'...'9' => |b| {
                            fuse_index *= 10;
                            fuse_index += b - '0';
                        },
                        ' ', '\t', '\r', '\n' => break,
                        else => return error.Abort,
                    }
                }

                if (fuse_index != data.fuse_index) {
                    return error.Abort;
                }

                RTS.modifyInline(1);
                try uart.writer().print("Reading data for location {}\r\n", .{ fuse_index });
                RTS.modifyInline(0);

                data.in_l_data = true;
            },
            ' ', '\t', '\r', '\n' => {},
            0x3, '`' => if (data.fuse_index < (width * height)) {
                return error.Abort;
            } else {
                return;
            },
            else => while (true) {
                switch (try reader.readByte()) {
                    0x1b => return error.Abort,
                    '*' => break,
                    else => {},
                }
            },
        }
    }
}

fn prepWriteChip() !void {
    doCommand(.ISC_DISABLE, void, {});
    doCommand(.BYPASS, void, {});
    doCommand(.IDCODE, void, {});
    doCommand(.ISC_DISABLE, void, {});

    RTS.modifyInline(1);
    try uart.writer().writeAll("Ready to receive JEDEC file; send ETX or backtick when finished.\r\n");
    RTS.modifyInline(0);

    const reader = uart.reader();
    while (true) {
        const b = try reader.readByte();
        if (b == '*') break;
        if (b == 0x1B) return error.Abort;
    }
}

fn writeChip() !void {
    var data = JedecParseData {};
    try parseJedec(&data);
    RTS.modifyInline(1);

    const idcode = doCommand(.IDCODE, u32, 0xFFFF_FFFF);
    if (idcode != svf_file.getIDCode(device.get())) {
        return error.BadIDCode;
    }

    _ = doCommand(.SAMPLE_PRELOAD, std.meta.Int(.unsigned, svf_file.getBoundaryScanLength(device.get())), 0);
    doCommand(.ISC_ENABLE, void, {});
    doCommand(.ISC_ERASE, void, {});
    doCommand(.ISC_DISCHARGE, void, {});
    doCommand(.ISC_ADDRESS_INIT, void, {});
    doCommand(.ISC_PROGRAM, void, {});

    var row: u16 = 0;
    while (row < height) : (row += 1) {
        _ = jtag.tap(0).data(RowDataType, data.row_data, .idle);
        idleForCommand(.ISC_PROGRAM);

        RTS.modifyInline(0);
        data.bits_left_in_row = width;
        data.row_data = 0;
        try parseJedec(&data);
        RTS.modifyInline(1);
    }

    try verifyInternal();

    if (data.usercode) |uc| {
        _ = doCommand(.ISC_PROGRAM_USERCODE, u32, uc);
    }
    if (data.program_security_bit) {
        doCommand(.ISC_PROGRAM_SECURITY, void, {});
    }
    doCommand(.ISC_PROGRAM_DONE, void, {});
    doCommand(.ISC_PROGRAM_DONE, void, {}); // not sure if this is necessary but the lattice SVFs do this twice...?

    doCommand(.ISC_DISABLE, void, {});
    doCommand(.BYPASS, void, {});
    doCommand(.IDCODE, void, {});
    doCommand(.ISC_DISABLE, void, {});
    reset();
}

fn reset() void {
    jtag.changeState(.reset);
    jtag.changeState(.idle);
}

// Removing `noinline` causes "LLVM ERROR: underestimated function size" when compiled with ReleaseSmall
// ...not sure if that's zig's fault or LLVM's.
noinline fn doCommand(comptime command: LC4kCommand, comptime T: type, value: T) T {
    const tap = jtag.tap(0);

    tap.instruction(command, .idle);
    const result = if (T == void) {} else tap.data(T, value, .DR_pause);

    switch (command) {
        .ISC_PROGRAM, .ISC_READ => {},
        else => idleForCommand(command),
    }

    return result;
}

fn idleForCommand(comptime command: LC4kCommand) void {
    const delay = comptime command.getDelay();
    if (delay.min_ms > 0) {
        _ = jtag.idleUntil(clock.current_tick.plus(.{ .ms = delay.min_ms }), delay.min_clocks);
    } else {
        jtag.idle(delay.min_clocks);
    }
}
