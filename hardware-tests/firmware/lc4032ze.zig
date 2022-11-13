const std = @import("std");
const microbe = @import("microbe");
const clock = microbe.clock;

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

pub var uart1: microbe.Uart(.{
    .baud_rate = 9600,
    .tx = .PA9,
    .rx = .PA10,
    // .cts = .PA11,
    // .rts = .PA12,
}) = undefined;

pub fn main() void {
    uart1 = @TypeOf(uart1).init();
    uart1.start();

    var tick = clock.current_tick;
    while (true) {
        if (uart1.canRead()) {
            var writer = uart1.writer();
            var reader = uart1.reader();

            try writer.writeAll(":");

            while (uart1.canRead()) {
                var b = reader.readByte() catch |err| {
                    const s = switch (err) {
                        error.Overrun => "!ORE!",
                        error.FramingError => "!FE!",
                        error.NoiseError =>   "!NE!",
                        error.EndOfStream => "!EOS!",
                        error.BreakInterrupt => "!BRK!",
                    };
                    try writer.writeAll(s);
                    continue;
                };

                switch (b) {
                    ' '...'[', ']'...'~' => try writer.writeByte(b),
                    else => try writer.print("\\x{x}", .{ b }),
                }
            }

            try writer.writeAll("\r\n");
        }

        tick = tick.plus(.{ .seconds = 2 });
        clock.blockUntilTick(tick);
    }
}
