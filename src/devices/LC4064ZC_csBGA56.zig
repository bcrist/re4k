//[[!! include('device', 'LC4064ZC_csBGA56') !! 69 ]]
//[[ ################# !! GENERATED CODE -- DO NOT MODIFY !! ################# ]]
const std = @import("std");
const device_pins = @import("device_pins.zig");

pub const pins = buildPins();

fn buildPins() [56]device_pins.PinInfo {
    var b = device_pins.PinInfoBuilder {};
    return .{
        b.io("A1", 0, 0, 6),
        b.io("A2", 0, 0, 4),
        b.io("A3", 0, 0, 2),
        b.io("A4", 0, 0, 1),
        b.clk("A5", 0, 0, 0),
        b.oe("A6", 1, 3, 0, 1),
        b.io("A7", 1, 3, 6),
        b.in("A8", 1, 3),
        b.misc("A9", .vcc_core),
        b.misc("A10", .tdo),
        b.misc("B1", .tdi),
        b.in("B10", 1, 3),
        b.io("C1", 0, 0, 10),
        b.io("C3", 0, 0, 8),
        b.oe("C4", 0, 0, 0, 0),
        b.clk("C5", 1, 3, 3),
        b.io("C6", 1, 3, 2),
        b.io("C7", 1, 3, 4),
        b.misc("C8", .gnd),
        b.io("C10", 1, 3, 8),
        b.io("D1", 0, 0, 11),
        b.misc("D3", .gnd),
        b.io("D8", 1, 3, 12),
        b.io("D10", 1, 3, 10),
        b.in("E1", 0, 1),
        b.in("E3", 0, 0),
        b.misc("E8", .vcco_bank_1),
        b.io("E10", 1, 3, 15),
        b.io("F1", 0, 1, 15),
        b.misc("F3", .vcco_bank_0),
        b.in("F8", 1, 2),
        b.in("F10", 1, 3),
        b.io("G1", 0, 1, 10),
        b.io("G3", 0, 1, 12),
        b.misc("G8", .gnd),
        b.io("G10", 1, 2, 11),
        b.io("H1", 0, 1, 8),
        b.misc("H3", .gnd),
        b.io("H4", 0, 1, 4),
        b.io("H5", 0, 1, 2),
        b.clk("H6", 0, 1, 1),
        b.io("H7", 1, 2, 0),
        b.io("H8", 1, 2, 8),
        b.io("H10", 1, 2, 10),
        b.in("J1", 0, 1),
        b.misc("J10", .tms),
        b.misc("K1", .tck),
        b.misc("K2", .vcc_core),
        b.in("K3", 0, 1),
        b.io("K4", 0, 1, 6),
        b.io("K5", 0, 1, 0),
        b.clk("K6", 1, 2, 2),
        b.io("K7", 1, 2, 1),
        b.io("K8", 1, 2, 2),
        b.io("K9", 1, 2, 4),
        b.io("K10", 1, 2, 6),
    };
}
//[[ ######################### END OF GENERATED CODE ######################### ]]
