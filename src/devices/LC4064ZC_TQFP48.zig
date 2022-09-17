//[[!! include('device', 'LC4064ZC_TQFP48') !! 61 ]]
//[[ ################# !! GENERATED CODE -- DO NOT MODIFY !! ################# ]]
const std = @import("std");
const device_pins = @import("device_pins.zig");

pub const pins = buildPins();

fn buildPins() [48]device_pins.PinInfo {
    var b = device_pins.PinInfoBuilder {};
    return .{
        b.misc("1", .tdi),
        b.io("2", 0, 0, 8),
        b.io("3", 0, 0, 10),
        b.io("4", 0, 0, 11),
        b.misc("5", .gnd),
        b.misc("6", .vcco_bank_0),
        b.io("7", 0, 1, 15),
        b.io("8", 0, 1, 12),
        b.io("9", 0, 1, 10),
        b.io("10", 0, 1, 8),
        b.misc("11", .tck),
        b.misc("12", .vcc_core),
        b.misc("13", .gnd),
        b.io("14", 0, 1, 6),
        b.io("15", 0, 1, 4),
        b.io("16", 0, 1, 2),
        b.io("17", 0, 1, 0),
        b.clk("18", 0, 1, 1),
        b.clk("19", 1, 2, 2),
        b.io("20", 1, 2, 0),
        b.io("21", 1, 2, 1),
        b.io("22", 1, 2, 2),
        b.io("23", 1, 2, 4),
        b.io("24", 1, 2, 6),
        b.misc("25", .tms),
        b.io("26", 1, 2, 8),
        b.io("27", 1, 2, 10),
        b.io("28", 1, 2, 11),
        b.misc("29", .gnd),
        b.misc("30", .vcco_bank_1),
        b.io("31", 1, 3, 15),
        b.io("32", 1, 3, 12),
        b.io("33", 1, 3, 10),
        b.io("34", 1, 3, 8),
        b.misc("35", .tdo),
        b.misc("36", .vcc_core),
        b.misc("37", .gnd),
        b.io("38", 1, 3, 6),
        b.io("39", 1, 3, 4),
        b.io("40", 1, 3, 2),
        b.goe("41", 1, 3, 0, 1),
        b.clk("42", 1, 3, 3),
        b.clk("43", 0, 0, 0),
        b.goe("44", 0, 0, 0, 0),
        b.io("45", 0, 0, 1),
        b.io("46", 0, 0, 2),
        b.io("47", 0, 0, 4),
        b.io("48", 0, 0, 6),
    };
}
//[[ ######################### END OF GENERATED CODE ######################### ]]
