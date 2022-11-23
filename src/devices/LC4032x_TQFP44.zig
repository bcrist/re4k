//[[!! include('device', 'LC4032x_TQFP44') !! 57 ]]
//[[ ################# !! GENERATED CODE -- DO NOT MODIFY !! ################# ]]
const std = @import("std");
const device_pins = @import("device_pins.zig");

pub const pins = buildPins();

fn buildPins() [44]device_pins.PinInfo {
    var b = device_pins.PinInfoBuilder {};
    return .{
        b.misc("1", .tdi),
        b.io("2", 0, 0, 5),
        b.io("3", 0, 0, 6),
        b.io("4", 0, 0, 7),
        b.misc("5", .gnd),
        b.misc("6", .vcco_bank_0),
        b.io("7", 0, 0, 8),
        b.io("8", 0, 0, 9),
        b.io("9", 0, 0, 10),
        b.misc("10", .tck),
        b.misc("11", .vcc_core),
        b.misc("12", .gnd),
        b.io("13", 0, 0, 12),
        b.io("14", 0, 0, 13),
        b.io("15", 0, 0, 14),
        b.io("16", 0, 0, 15),
        b.clk("17", 1, 1, 2),
        b.io("18", 1, 1, 0),
        b.io("19", 1, 1, 1),
        b.io("20", 1, 1, 2),
        b.io("21", 1, 1, 3),
        b.io("22", 1, 1, 4),
        b.misc("23", .tms),
        b.io("24", 1, 1, 5),
        b.io("25", 1, 1, 6),
        b.io("26", 1, 1, 7),
        b.misc("27", .gnd),
        b.misc("28", .vcco_bank_1),
        b.io("29", 1, 1, 8),
        b.io("30", 1, 1, 9),
        b.io("31", 1, 1, 10),
        b.misc("32", .tdo),
        b.misc("33", .vcc_core),
        b.misc("34", .gnd),
        b.io("35", 1, 1, 12),
        b.io("36", 1, 1, 13),
        b.io("37", 1, 1, 14),
        b.oe("38", 1, 1, 15, 1),
        b.clk("39", 0, 0, 0),
        b.oe("40", 0, 0, 0, 0),
        b.io("41", 0, 0, 1),
        b.io("42", 0, 0, 2),
        b.io("43", 0, 0, 3),
        b.io("44", 0, 0, 4),
    };
}
//[[ ######################### END OF GENERATED CODE ######################### ]]
