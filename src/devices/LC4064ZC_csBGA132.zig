//[[!! include('device', 'LC4064ZC_csBGA132') !! 145 ]]
//[[ ################# !! GENERATED CODE -- DO NOT MODIFY !! ################# ]]
const std = @import("std");
const device_pins = @import("device_pins.zig");

pub const pins = buildPins();

fn buildPins() [132]device_pins.PinInfo {
    var b = device_pins.PinInfoBuilder {};
    return .{
        b.oe("C7", 0, 0, 0, 0),
        b.io("A6", 0, 0, 1),
        b.io("A3", 0, 0, 5),
        b.io("B3", 0, 0, 6),
        b.io("A2", 0, 0, 7),
        b.misc("A1", .no_connect),
        b.io("B6", 0, 0, 2),
        b.io("C6", 0, 0, 3),
        b.misc("B5", .no_connect),
        b.misc("A5", .no_connect),
        b.misc("A4", .no_connect),
        b.io("C4", 0, 0, 4),
        b.misc("C3", .no_connect),
        b.io("C2", 0, 0, 8),
        b.io("F1", 0, 0, 13),
        b.io("F3", 0, 0, 14),
        b.io("G1", 0, 0, 15),
        b.in("G2", 0, 0),
        b.io("D1", 0, 0, 9),
        b.io("D3", 0, 0, 10),
        b.io("D2", 0, 0, 11),
        b.misc("E1", .no_connect),
        b.misc("E3", .no_connect),
        b.io("F2", 0, 0, 12),
        b.in("M1", 0, 1),
        b.io("L3", 0, 1, 8),
        b.io("J1", 0, 1, 13),
        b.io("H3", 0, 1, 14),
        b.io("H1", 0, 1, 15),
        b.misc("H2", .no_connect),
        b.io("L1", 0, 1, 9),
        b.io("L2", 0, 1, 10),
        b.io("K3", 0, 1, 11),
        b.misc("K1", .no_connect),
        b.misc("J3", .no_connect),
        b.io("J2", 0, 1, 12),
        b.clk("C8", 0, 0, 0),
        b.clk("N7", 0, 1, 1),
        b.clk("M7", 1, 2, 2),
        b.clk("B8", 1, 3, 3),
        b.misc("P7", .no_connect),
        b.io("M6", 0, 1, 0),
        b.io("N3", 0, 1, 5),
        b.io("M3", 0, 1, 6),
        b.io("P3", 0, 1, 7),
        b.in("N2", 0, 1),
        b.io("P6", 0, 1, 1),
        b.io("N6", 0, 1, 2),
        b.io("M5", 0, 1, 3),
        b.misc("N5", .no_connect),
        b.misc("M4", .no_connect),
        b.io("P4", 0, 1, 4),
        b.misc("M8", .no_connect),
        b.io("P9", 1, 2, 0),
        b.io("P12", 1, 2, 5),
        b.io("N12", 1, 2, 6),
        b.io("P13", 1, 2, 7),
        b.misc("P14", .no_connect),
        b.io("N9", 1, 2, 1),
        b.io("M9", 1, 2, 2),
        b.io("N10", 1, 2, 3),
        b.misc("P10", .no_connect),
        b.misc("P11", .no_connect),
        b.io("M11", 1, 2, 4),
        b.misc("M12", .no_connect),
        b.io("M13", 1, 2, 8),
        b.io("J14", 1, 2, 13),
        b.io("J12", 1, 2, 14),
        b.io("H14", 1, 2, 15),
        b.in("H13", 1, 2),
        b.io("L14", 1, 2, 9),
        b.io("L12", 1, 2, 10),
        b.io("L13", 1, 2, 11),
        b.misc("K14", .no_connect),
        b.misc("K12", .no_connect),
        b.io("J13", 1, 2, 12),
        b.in("C14", 1, 3),
        b.io("D12", 1, 3, 8),
        b.io("F14", 1, 3, 14),
        b.io("G12", 1, 3, 15),
        b.misc("G14", .no_connect),
        b.misc("G13", .no_connect),
        b.io("D14", 1, 3, 9),
        b.io("D13", 1, 3, 10),
        b.io("E12", 1, 3, 11),
        b.misc("E14", .no_connect),
        b.io("F12", 1, 3, 12),
        b.io("F13", 1, 3, 13),
        b.misc("A13", .gnd),
        b.misc("B1", .gnd),
        b.misc("N14", .gnd),
        b.misc("P2", .gnd),
        b.misc("B4", .gnd),
        b.misc("E2", .gnd),
        b.misc("K2", .gnd),
        b.misc("N4", .gnd),
        b.misc("B11", .gnd),
        b.misc("E13", .gnd),
        b.misc("K13", .gnd),
        b.misc("N11", .gnd),
        b.misc("A7", .no_connect),
        b.misc("P8", .no_connect),
        b.oe("A8", 1, 3, 0, 1),
        b.io("C9", 1, 3, 1),
        b.io("B12", 1, 3, 6),
        b.io("C12", 1, 3, 7),
        b.in("A12", 1, 3),
        b.misc("B13", .no_connect),
        b.io("A9", 1, 3, 2),
        b.io("B9", 1, 3, 3),
        b.misc("C10", .no_connect),
        b.misc("B10", .no_connect),
        b.io("C11", 1, 3, 4),
        b.io("A11", 1, 3, 5),
        b.misc("N1", .tck),
        b.misc("B2", .tdi),
        b.misc("B14", .tdo),
        b.misc("N13", .tms),
        b.misc("A14", .vcc_core),
        b.misc("B7", .vcc_core),
        b.misc("N8", .vcc_core),
        b.misc("P1", .vcc_core),
        b.misc("C1", .no_connect),
        b.misc("C5", .vcco_bank_0),
        b.misc("G3", .vcco_bank_0),
        b.misc("M2", .no_connect),
        b.misc("P5", .vcco_bank_0),
        b.misc("A10", .vcco_bank_1),
        b.misc("C13", .no_connect),
        b.misc("H12", .vcco_bank_1),
        b.misc("M10", .vcco_bank_1),
        b.misc("M14", .no_connect),
    };
}
//[[ ######################### END OF GENERATED CODE ######################### ]]
