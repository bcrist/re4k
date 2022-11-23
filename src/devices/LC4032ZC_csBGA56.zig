//[[!! include('device', 'LC4032ZC_csBGA56') !! 69 ]]
//[[ ################# !! GENERATED CODE -- DO NOT MODIFY !! ################# ]]
const std = @import("std");
const device_pins = @import("device_pins.zig");

pub const pins = buildPins();

fn buildPins() [56]device_pins.PinInfo {
    var b = device_pins.PinInfoBuilder {};
    return .{
        b.io("A1", 0, 0, 4),
        b.io("A2", 0, 0, 3),
        b.io("A3", 0, 0, 2),
        b.io("A4", 0, 0, 1),
        b.clk("A5", 0, 0, 0),
        b.oe("A6", 1, 1, 15, 1),
        b.io("A7", 1, 1, 12),
        b.misc("A8", .no_connect),
        b.misc("A9", .vcc_core),
        b.misc("A10", .tdo),
        b.misc("B1", .tdi),
        b.misc("B10", .no_connect),
        b.io("C1", 0, 0, 6),
        b.io("C3", 0, 0, 5),
        b.oe("C4", 0, 0, 0, 0),
        b.clk("C5", 1, 1, 3),
        b.io("C6", 1, 1, 14),
        b.io("C7", 1, 1, 13),
        b.misc("C8", .gnd),
        b.io("C10", 1, 1, 11),
        b.io("D1", 0, 0, 7),
        b.misc("D3", .gnd),
        b.io("D8", 1, 1, 9),
        b.io("D10", 1, 1, 10),
        b.misc("E1", .no_connect),
        b.misc("E3", .no_connect),
        b.misc("E8", .vcco_bank_1),
        b.io("E10", 1, 1, 8),
        b.io("F1", 0, 0, 8),
        b.misc("F3", .vcco_bank_0),
        b.misc("F8", .no_connect),
        b.misc("F10", .no_connect),
        b.io("G1", 0, 0, 10),
        b.io("G3", 0, 0, 9),
        b.misc("G8", .gnd),
        b.io("G10", 1, 1, 7),
        b.io("H1", 0, 0, 11),
        b.misc("H3", .gnd),
        b.io("H4", 0, 0, 13),
        b.io("H5", 0, 0, 14),
        b.clk("H6", 0, 0, 1),
        b.io("H7", 1, 1, 0),
        b.io("H8", 1, 1, 5),
        b.io("H10", 1, 1, 6),
        b.misc("J1", .no_connect),
        b.misc("J10", .tms),
        b.misc("K1", .tck),
        b.misc("K2", .vcc_core),
        b.misc("K3", .no_connect),
        b.io("K4", 0, 0, 12),
        b.io("K5", 0, 0, 15),
        b.clk("K6", 1, 1, 2),
        b.io("K7", 1, 1, 1),
        b.io("K8", 1, 1, 2),
        b.io("K9", 1, 1, 3),
        b.io("K10", 1, 1, 4),
    };
}
//[[ ######################### END OF GENERATED CODE ######################### ]]
