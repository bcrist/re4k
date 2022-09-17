//[[!! include('device', 'LC4256ZE_TQFP100') !! 113 ]]
//[[ ################# !! GENERATED CODE -- DO NOT MODIFY !! ################# ]]
const std = @import("std");
const device_pins = @import("device_pins.zig");

pub const pins = buildPins();

fn buildPins() [100]device_pins.PinInfo {
    var b = device_pins.PinInfoBuilder {};
    return .{
        b.misc("1", .gnd),
        b.misc("2", .tdi),
        b.io("3", 0, 2, 12),
        b.io("4", 0, 2, 10),
        b.io("5", 0, 2, 6),
        b.io("6", 0, 2, 2),
        b.misc("7", .gnd),
        b.io("8", 0, 3, 12),
        b.io("9", 0, 3, 10),
        b.io("10", 0, 3, 6),
        b.io("11", 0, 3, 4),
        b.in("12", 0, 3),
        b.misc("13", .vcco_bank_0),
        b.io("14", 0, 4, 4),
        b.io("15", 0, 4, 6),
        b.io("16", 0, 4, 10),
        b.io("17", 0, 4, 12),
        b.misc("18", .gnd),
        b.io("19", 0, 5, 2),
        b.io("20", 0, 5, 6),
        b.io("21", 0, 5, 10),
        b.io("22", 0, 5, 12),
        b.in("23", 0, 5),
        b.misc("24", .tck),
        b.misc("25", .vcc_core),
        b.misc("26", .gnd),
        b.in("27", 0, 6),
        b.io("28", 0, 6, 12),
        b.io("29", 0, 6, 10),
        b.io("30", 0, 6, 6),
        b.io("31", 0, 6, 2),
        b.misc("32", .gnd),
        b.misc("33", .vcco_bank_0),
        b.io("34", 0, 7, 12),
        b.io("35", 0, 7, 10),
        b.io("36", 0, 7, 6),
        b.io("37", 0, 7, 2),
        b.clk("38", 0, 7, 1),
        b.clk("39", 1, 8, 2),
        b.misc("40", .vcc_core),
        b.io("41", 1, 8, 2),
        b.io("42", 1, 8, 6),
        b.io("43", 1, 8, 10),
        b.io("44", 1, 8, 12),
        b.misc("45", .vcco_bank_1),
        b.misc("46", .gnd),
        b.io("47", 1, 9, 2),
        b.io("48", 1, 9, 6),
        b.io("49", 1, 9, 10),
        b.io("50", 1, 9, 12),
        b.misc("51", .gnd),
        b.misc("52", .tms),
        b.io("53", 1, 10, 12),
        b.io("54", 1, 10, 10),
        b.io("55", 1, 10, 6),
        b.io("56", 1, 10, 2),
        b.misc("57", .gnd),
        b.io("58", 1, 11, 12),
        b.io("59", 1, 11, 10),
        b.io("60", 1, 11, 6),
        b.io("61", 1, 11, 4),
        b.in("62", 1, 11),
        b.misc("63", .vcco_bank_1),
        b.io("64", 1, 12, 4),
        b.io("65", 1, 12, 6),
        b.io("66", 1, 12, 10),
        b.io("67", 1, 12, 12),
        b.misc("68", .gnd),
        b.io("69", 1, 13, 2),
        b.io("70", 1, 13, 6),
        b.io("71", 1, 13, 10),
        b.io("72", 1, 13, 12),
        b.in("73", 1, 13),
        b.misc("74", .tdo),
        b.misc("75", .vcc_core),
        b.misc("76", .gnd),
        b.in("77", 1, 14),
        b.io("78", 1, 14, 12),
        b.io("79", 1, 14, 10),
        b.io("80", 1, 14, 6),
        b.io("81", 1, 14, 2),
        b.misc("82", .gnd),
        b.misc("83", .vcco_bank_1),
        b.io("84", 1, 15, 12),
        b.io("85", 1, 15, 10),
        b.io("86", 1, 15, 6),
        b.goe("87", 1, 15, 2, 1),
        b.clk("88", 1, 15, 3),
        b.clk("89", 0, 0, 0),
        b.misc("90", .vcc_core),
        b.goe("91", 0, 0, 2, 0),
        b.io("92", 0, 0, 6),
        b.io("93", 0, 0, 10),
        b.io("94", 0, 0, 12),
        b.misc("95", .vcco_bank_0),
        b.misc("96", .gnd),
        b.io("97", 0, 1, 2),
        b.io("98", 0, 1, 6),
        b.io("99", 0, 1, 10),
        b.io("100", 0, 1, 12),
    };
}
//[[ ######################### END OF GENERATED CODE ######################### ]]
