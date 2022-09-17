//[[!! include('device', 'LC4256ZC_csBGA132') !! 145 ]]
//[[ ################# !! GENERATED CODE -- DO NOT MODIFY !! ################# ]]
const std = @import("std");
const device_pins = @import("device_pins.zig");

pub const pins = buildPins();

fn buildPins() [132]device_pins.PinInfo {
    var b = device_pins.PinInfoBuilder {};
    return .{
        b.io("C3", 0, 2, 12),
        b.io("C2", 0, 2, 10),
        b.io("D1", 0, 2, 8),
        b.io("D3", 0, 2, 6),
        b.io("D2", 0, 2, 4),
        b.io("E1", 0, 2, 2),
        b.io("E3", 0, 3, 12),
        b.io("F2", 0, 3, 10),
        b.io("F1", 0, 3, 8),
        b.io("F3", 0, 3, 6),
        b.io("G1", 0, 3, 4),
        b.io("G2", 0, 3, 2),
        b.io("H2", 0, 4, 2),
        b.io("H1", 0, 4, 4),
        b.io("H3", 0, 4, 6),
        b.io("J1", 0, 4, 8),
        b.io("J2", 0, 4, 10),
        b.io("J3", 0, 4, 12),
        b.io("K1", 0, 5, 2),
        b.io("K3", 0, 5, 4),
        b.io("L2", 0, 5, 6),
        b.io("L1", 0, 5, 8),
        b.io("L3", 0, 5, 10),
        b.io("M1", 0, 5, 12),
        b.io("N2", 0, 6, 12),
        b.io("P3", 0, 6, 10),
        b.io("M3", 0, 6, 8),
        b.io("N3", 0, 6, 6),
        b.io("P4", 0, 6, 4),
        b.io("M4", 0, 6, 2),
        b.io("N5", 0, 7, 12),
        b.io("M5", 0, 7, 10),
        b.io("N6", 0, 7, 8),
        b.io("P6", 0, 7, 6),
        b.io("M6", 0, 7, 4),
        b.io("P7", 0, 7, 2),
        b.clk("N7", 0, 7, 1),
        b.clk("M7", 1, 8, 2),
        b.in("P8", 1, 8),
        b.io("M8", 1, 8, 2),
        b.io("P9", 1, 8, 4),
        b.io("N9", 1, 8, 6),
        b.io("M9", 1, 8, 8),
        b.io("N10", 1, 8, 10),
        b.io("P10", 1, 8, 12),
        b.io("P11", 1, 9, 2),
        b.io("M11", 1, 9, 4),
        b.io("P12", 1, 9, 6),
        b.io("N12", 1, 9, 8),
        b.io("P13", 1, 9, 10),
        b.io("P14", 1, 9, 12),
        b.io("M12", 1, 10, 12),
        b.io("M13", 1, 10, 10),
        b.io("L14", 1, 10, 8),
        b.io("L12", 1, 10, 6),
        b.io("L13", 1, 10, 4),
        b.io("K14", 1, 10, 2),
        b.io("K12", 1, 11, 12),
        b.io("J13", 1, 11, 10),
        b.io("J14", 1, 11, 8),
        b.io("J12", 1, 11, 6),
        b.io("H14", 1, 11, 4),
        b.io("H13", 1, 11, 2),
        b.io("G13", 1, 12, 2),
        b.io("G14", 1, 12, 4),
        b.io("G12", 1, 12, 6),
        b.io("F14", 1, 12, 8),
        b.io("F13", 1, 12, 10),
        b.io("F12", 1, 12, 12),
        b.io("E14", 1, 13, 2),
        b.io("E12", 1, 13, 4),
        b.io("D13", 1, 13, 6),
        b.io("D14", 1, 13, 8),
        b.io("D12", 1, 13, 10),
        b.io("C14", 1, 13, 12),
        b.io("B13", 1, 14, 12),
        b.io("A12", 1, 14, 10),
        b.io("C12", 1, 14, 8),
        b.io("B12", 1, 14, 6),
        b.io("A11", 1, 14, 4),
        b.io("C11", 1, 14, 2),
        b.io("B10", 1, 15, 12),
        b.io("C10", 1, 15, 10),
        b.io("B9", 1, 15, 8),
        b.io("A9", 1, 15, 6),
        b.io("C9", 1, 15, 4),
        b.goe("A8", 1, 15, 2, 1),
        b.clk("B8", 1, 15, 3),
        b.clk("C8", 0, 0, 0),
        b.in("A7", 0, 0),
        b.goe("C7", 0, 0, 2, 0),
        b.io("A6", 0, 0, 4),
        b.io("B6", 0, 0, 6),
        b.io("C6", 0, 0, 8),
        b.io("B5", 0, 0, 10),
        b.io("A5", 0, 0, 12),
        b.io("A4", 0, 1, 2),
        b.io("C4", 0, 1, 4),
        b.io("A3", 0, 1, 6),
        b.io("B3", 0, 1, 8),
        b.io("A2", 0, 1, 10),
        b.io("A1", 0, 1, 12),
        b.misc("N1", .tck),
        b.misc("B2", .tdi),
        b.misc("B14", .tdo),
        b.misc("N13", .tms),
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
        b.misc("A14", .vcc_core),
        b.misc("B7", .vcc_core),
        b.misc("N8", .vcc_core),
        b.misc("P1", .vcc_core),
        b.misc("C1", .vcco_bank_0),
        b.misc("C5", .vcco_bank_0),
        b.misc("G3", .vcco_bank_0),
        b.misc("M2", .vcco_bank_0),
        b.misc("P5", .vcco_bank_0),
        b.misc("A10", .vcco_bank_1),
        b.misc("C13", .vcco_bank_1),
        b.misc("H12", .vcco_bank_1),
        b.misc("M10", .vcco_bank_1),
        b.misc("M14", .vcco_bank_1),
    };
}
//[[ ######################### END OF GENERATED CODE ######################### ]]
