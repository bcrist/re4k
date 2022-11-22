const std = @import("std");
const core = @import("core.zig");
const jedec = @import("jedec.zig");

const Fuse = jedec.Fuse;

pub const JtagCommand = enum (u8) {
    ISC_ENABLE = 0x15,
    ISC_DISABLE = 0x1E,

    ISC_ERASE = 0x03,

    ISC_PROGRAM_USERCODE = 0x1A,
    READ_USERCODE = 0x17,

    ISC_PROGRAM_SECURITY = 0x09,

    ISC_ADDRESS_INIT = 0x21,
    ISC_ADDRESS_SHIFT = 0x01,

    ISC_PROGRAM_INCR = 0x27,
    ISC_READ_INCR = 0x2A,

    ISC_PROGRAM_DONE = 0x2F,
    DISCHARGE = 0x14,
    SAMPLE_PRELOAD = 0x1C,
    IDCODE = 0x16,
    BYPASS = 0xFF,

    pub fn getDelayMillis(self: JtagCommand) usize {
        return switch (self) {
            .ISC_ENABLE => 20,
            .ISC_ERASE => 100,
            .DISCHARGE => 10,
            .ISC_PROGRAM_INCR => 13,
            .ISC_READ_INCR => 1, // N.B. this delay happens *before* the SDR transaction
            .ISC_PROGRAM_USERCODE => 13,
            .ISC_PROGRAM_SECURITY => 50,
            .ISC_PROGRAM_DONE => 50,
            .ISC_DISABLE => 200,
            .BYPASS => 10,
            else => 0,
        };
    }
    pub fn getDelayClocks(self: JtagCommand) usize {
        return switch (self) {
            .ISC_PROGRAM_DONE => 5,
            .ISC_DISABLE => 5,
            .BYPASS => 32,
            else => 0,
        };
    }

};

pub fn write(data: jedec.JedecData, writer: anytype, options: core.FuseFileWriteOptions) !void {
    const nl = options.line_ending;

    try writeState("RESET", writer, nl);
    try writer.writeAll(nl);
    try writer.print("! Row_Width\t:{}{s}", .{ data.width, nl });
    try writer.print("! Address_Length\t:{}{s}", .{ data.height, nl });
    try writer.print("HDR\t0;{s}", .{ nl });
    try writer.print("HIR\t0;{s}", .{ nl });
    try writer.print("TDR\t0;{s}", .{ nl });
    try writer.print("TIR\t0;{s}", .{ nl });
    try writer.print("ENDDR\tDRPAUSE;{s}", .{ nl });
    try writer.print("ENDIR\tIDLE;{s}", .{ nl });
    try writer.print("! FREQUENCY\t1.E+6 HZ;{s}", .{ nl });
    try writeState("IDLE", writer, nl);
    try writer.writeAll(nl);

    // TODO should this vary from one device to another?
    try writeCommand(.IDCODE, u32, 0xFFFFFFFF, 0x01806043, writer, nl);
    try writer.writeAll(nl);

    // TODO this has to do with the length of the BSR, which is device dependent.
    try writeCommand(.SAMPLE_PRELOAD, u68, 0, null, writer, nl);
    try writer.writeAll(nl);

    try writeCommand(.ISC_ENABLE, bool, null, null, writer, nl);
    try writer.writeAll(nl);

    if (options.svf_erase) {
        try writeCommand(.ISC_ERASE, bool, null, null, writer, nl);
        try writeCommand(.DISCHARGE, bool, null, null, writer, nl);
        try writer.writeAll(nl);
    }

    {
        try writeCommand(.ISC_ADDRESS_INIT, bool, null, null, writer, nl);
        try writeCommand(.ISC_PROGRAM_INCR, bool, null, null, writer, nl);

        var row: u16 = 0;
        while (row < data.height) : (row += 1) {
            try writer.print("SDR\t{}\tTDI  (", .{ data.width });
            try writeRowHex(data, row, writer);
            try writer.print(");{s}", .{ nl });
            try writeIdle(.ISC_PROGRAM_INCR, writer, nl);
        }
        try writer.writeAll(nl);
    }

    if (options.svf_verify) {
        // TODO does this need to be modified based on the height?
        try writeCommand(.ISC_ADDRESS_SHIFT, u100, 0x8000000000000000000000000, null, writer, nl);
        try writeCommand(.ISC_READ_INCR, bool, null, null, writer, nl);

        var row: u16 = 0;
        while (row < data.height) : (row += 1) {
            try writeIdle(.ISC_READ_INCR, writer, nl);
            try writer.print("SDR\t{}\tTDI  (", .{ data.width });
            var chars: u16 = (data.width + 3) / 4;
            try writer.writeByteNTimes('0', chars);
            try writer.print("){s}\t\tTDO  (", .{ nl });

            try writeRowHex(data, row, writer);
            try writer.print(");{s}", .{ nl });
        }
        try writer.writeAll(nl);
    }

    if (data.usercode) |u| {
        try writeCommand(.ISC_PROGRAM_USERCODE, u32, u, null, writer, nl);
        if (options.svf_verify) {
            try writeCommand(.READ_USERCODE, u32, 0xFFFFFFFF, u, writer, nl);
        }
        try writer.writeAll(nl);
    }

    if (data.security) |g| {
        if (g != 0) {
            try writeCommand(.ISC_PROGRAM_SECURITY, bool, null, null, writer, nl);
            try writer.writeAll(nl);
        }
    }

    try writeCommand(.ISC_PROGRAM_DONE, bool, null, null, writer, nl);
    try writeCommand(.ISC_PROGRAM_DONE, bool, null, null, writer, nl); // not sure why this is done twice...?
    try writeCommand(.ISC_DISABLE, bool, null, null, writer, nl);
    try writeCommand(.BYPASS, bool, null, null, writer, nl);
    try writer.print("! {s}{s}", .{ @tagName(JtagCommand.IDCODE), nl });
    try writer.print("SIR\t8\tTDI  ({X:0>2}){s}", .{ @enumToInt(JtagCommand.IDCODE), nl });
    try writer.print("\t\tTDO  ({X:0>2});{s}", .{ 0x1D, nl });
    try writeCommand(.ISC_DISABLE, bool, null, null, writer, nl);
    try writeState("RESET", writer, nl);
}

fn writeRowHex(data: jedec.JedecData, row: u16, writer: anytype) !void {
    const chars: u16 = (data.width + 3) / 4;
    var col: i32 = chars * 4;
    while (col >= 4) : (col -= 4) {
        var val: u4 = 0;
        comptime var b = 1;
        inline while (b <= 4) : (b += 1) {
            var c = col - b;
            if (c < data.width) {
                val *= 2;
                val += data.get(Fuse.init(row, @intCast(u16, c)));
            }
        }
        try writer.print("{X:0>1}", .{ val });
    }
}

fn writeHex(comptime T: type, data: T, writer: anytype) !void {
    // TODO this assumes it's running on little endian, maybe refactor?
    if (T != bool) {
        const bits = @bitSizeOf(T);
        const digits = comptime (bits + 3) / 4;
        try writer.print(std.fmt.comptimePrint("{{X:0>{}}}", .{ digits }), .{ data });
    }
}

fn writeCommand(command: JtagCommand, comptime T: type, tdi_data: ?T, tdo_data: ?T, writer: anytype, nl: []const u8) !void {
    try writer.print("! {s}{s}", .{ @tagName(command), nl });
    try writer.print("SIR\t8\tTDI  ({X:0>2});{s}", .{ @enumToInt(command), nl });

    if (tdi_data) |tdi| {
        try writer.print("SDR\t{}\tTDI  (", .{ @bitSizeOf(T) });
        try writeHex(T, tdi, writer);

        if (tdo_data) |tdo| {
            try writer.print("){s}\t\tTDO  (", .{ nl });
            try writeHex(T, tdo, writer);
        }

        try writer.print(");{s}", .{ nl });
    }

    switch (command) {
        .ISC_PROGRAM_INCR, .ISC_READ_INCR => {},
        else => try writeIdle(command, writer, nl),
    }
}

fn writeState(state: []const u8, writer: anytype, nl: []const u8) !void {
    try writer.print("STATE\t{s};{s}", .{ state, nl });
}

fn writeIdle(command: JtagCommand, writer: anytype, nl: []const u8) !void {
    var ms = command.getDelayMillis();
    var clocks = command.getDelayClocks();
    if (ms > 0 and clocks > 0) {
        try writer.print("RUNTEST\tIDLE\t{} TCK\t{}.E-3 SEC;{s}", .{ clocks, ms, nl });
    } else if (ms > 0) {
        try writer.print("RUNTEST\tIDLE\t3 TCK\t{}.E-3 SEC;{s}", .{ ms, nl });
    } else if (clocks > 0) {
        try writer.print("RUNTEST\tIDLE\t{} TCK;{s}", .{ clocks, nl });
    }
}
