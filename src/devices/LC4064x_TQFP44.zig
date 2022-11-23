//[[!! include('device', 'LC4064x_TQFP44') !! 57 ]]
//[[ ################# !! GENERATED CODE -- DO NOT MODIFY !! ################# ]]
const std = @import("std");
const device_pins = @import("device_pins.zig");

pub const pins = buildPins();

fn buildPins() [44]device_pins.PinInfo {
    var b = device_pins.PinInfoBuilder {};
    return .{
        b.misc("1", .tdi),
        b.io("2", 0, 0, 10),
        b.io("3", 0, 0, 12),
        b.io("4", 0, 0, 14),
        b.misc("5", .gnd),
        b.misc("6", .vcco_bank_0),
        b.io("7", 0, 1, 0),
        b.io("8", 0, 1, 2),
        b.io("9", 0, 1, 4),
        b.misc("10", .tck),
        b.misc("11", .vcc_core),
        b.misc("12", .gnd),
        b.io("13", 0, 1, 8),
        b.io("14", 0, 1, 10),
        b.io("15", 0, 1, 12),
        b.io("16", 0, 1, 14),
        b.clk("17", 1, 2, 2),
        b.io("18", 1, 2, 0),
        b.io("19", 1, 2, 2),
        b.io("20", 1, 2, 4),
        b.io("21", 1, 2, 6),
        b.io("22", 1, 2, 8),
        b.misc("23", .tms),
        b.io("24", 1, 2, 10),
        b.io("25", 1, 2, 12),
        b.io("26", 1, 2, 14),
        b.misc("27", .gnd),
        b.misc("28", .vcco_bank_1),
        b.io("29", 1, 3, 0),
        b.io("30", 1, 3, 2),
        b.io("31", 1, 3, 4),
        b.misc("32", .tdo),
        b.misc("33", .vcc_core),
        b.misc("34", .gnd),
        b.io("35", 1, 3, 8),
        b.io("36", 1, 3, 10),
        b.io("37", 1, 3, 12),
        b.oe("38", 1, 3, 14, 1),
        b.clk("39", 0, 0, 0),
        b.oe("40", 0, 0, 0, 0),
        b.io("41", 0, 0, 2),
        b.io("42", 0, 0, 4),
        b.io("43", 0, 0, 6),
        b.io("44", 0, 0, 8),
    };
}
//[[ ######################### END OF GENERATED CODE ######################### ]]
