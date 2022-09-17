//[[!! include('device', 'LC4128ZE_csBGA144') !! 157 ]]
//[[ ################# !! GENERATED CODE -- DO NOT MODIFY !! ################# ]]
const std = @import("std");
const device_pins = @import("device_pins.zig");

pub const pins = buildPins();

fn buildPins() [144]device_pins.PinInfo {
    var b = device_pins.PinInfoBuilder {};
    return .{
        b.io("B5", 0, 0, 5),
        b.io("A5", 0, 0, 6),
        b.goe("D6", 0, 0, 0, 0),
        b.io("B6", 0, 0, 1),
        b.io("A6", 0, 0, 2),
        b.io("C6", 0, 0, 4),
        b.io("C4", 0, 0, 13),
        b.io("B3", 0, 0, 14),
        b.misc("A2", .no_connect),
        b.io("A4", 0, 0, 8),
        b.io("B4", 0, 0, 9),
        b.io("C5", 0, 0, 10),
        b.io("A3", 0, 0, 12),
        b.io("B1", 0, 1, 1),
        b.io("B2", 0, 1, 0),
        b.io("D1", 0, 1, 6),
        b.io("C1", 0, 1, 5),
        b.io("C2", 0, 1, 4),
        b.io("C3", 0, 1, 2),
        b.clk("A7", 0, 0, 0),
        b.clk("L6", 0, 3, 1),
        b.clk("M6", 1, 4, 2),
        b.clk("C7", 1, 7, 3),
        b.io("F3", 0, 1, 14),
        b.io("E1", 0, 1, 8),
        b.misc("D3", .no_connect),
        b.misc("D2", .no_connect),
        b.io("F1", 0, 1, 13),
        b.io("D4", 0, 1, 12),
        b.io("F2", 0, 1, 10),
        b.io("E2", 0, 1, 9),
        b.io("G1", 0, 2, 14),
        b.io("H3", 0, 2, 8),
        b.misc("H2", .no_connect),
        b.io("E3", 0, 2, 13),
        b.io("G2", 0, 2, 12),
        b.io("G3", 0, 2, 10),
        b.io("H1", 0, 2, 9),
        b.io("K2", 0, 2, 1),
        b.io("L1", 0, 2, 0),
        b.io("J1", 0, 2, 6),
        b.io("J3", 0, 2, 5),
        b.io("J2", 0, 2, 4),
        b.io("K1", 0, 2, 2),
        b.io("L4", 0, 3, 8),
        b.io("M2", 0, 3, 14),
        b.misc("K3", .no_connect),
        b.misc("M1", .no_connect),
        b.io("M3", 0, 3, 9),
        b.io("K4", 0, 3, 10),
        b.io("J4", 0, 3, 12),
        b.io("L3", 0, 3, 13),
        b.misc("F06", .gnd),
        b.misc("F07", .gnd),
        b.misc("G06", .gnd),
        b.misc("G07", .gnd),
        b.misc("E6", .gnd),
        b.misc("F05", .gnd),
        b.misc("G05", .gnd),
        b.misc("H04", .gnd),
        b.misc("H06", .gnd),
        b.misc("E07", .gnd),
        b.misc("F08", .gnd),
        b.misc("G08", .gnd),
        b.misc("H7", .gnd),
        b.misc("J09", .gnd),
        b.io("L5", 0, 3, 5),
        b.io("M4", 0, 3, 6),
        b.io("K6", 0, 3, 0),
        b.io("M5", 0, 3, 1),
        b.io("J6", 0, 3, 2),
        b.io("K5", 0, 3, 4),
        b.io("L8", 1, 4, 5),
        b.io("M8", 1, 4, 6),
        b.io("K7", 1, 4, 0),
        b.io("M7", 1, 4, 1),
        b.io("L7", 1, 4, 2),
        b.io("J7", 1, 4, 4),
        b.io("L10", 1, 4, 13),
        b.io("K9", 1, 4, 14),
        b.misc("M11", .no_connect),
        b.io("M9", 1, 4, 8),
        b.io("L9", 1, 4, 9),
        b.io("K8", 1, 4, 10),
        b.io("M10", 1, 4, 12),
        b.io("L11", 1, 5, 1),
        b.io("L12", 1, 5, 0),
        b.io("K11", 1, 5, 6),
        b.io("J10", 1, 5, 5),
        b.io("K12", 1, 5, 4),
        b.io("K10", 1, 5, 2),
        b.io("G10", 1, 5, 14),
        b.io("H10", 1, 5, 8),
        b.misc("J11", .no_connect),
        b.misc("J12", .no_connect),
        b.io("G12", 1, 5, 13),
        b.io("H11", 1, 5, 12),
        b.io("G11", 1, 5, 10),
        b.io("H12", 1, 5, 9),
        b.io("F12", 1, 6, 14),
        b.io("F10", 1, 6, 8),
        b.misc("D12", .no_connect),
        b.io("F11", 1, 6, 13),
        b.io("E11", 1, 6, 12),
        b.io("E12", 1, 6, 10),
        b.io("D10", 1, 6, 9),
        b.io("C11", 1, 6, 1),
        b.io("B12", 1, 6, 0),
        b.io("E10", 1, 6, 6),
        b.io("D11", 1, 6, 5),
        b.io("E9", 1, 6, 4),
        b.io("C12", 1, 6, 2),
        b.io("A10", 1, 7, 8),
        b.io("B10", 1, 7, 14),
        b.misc("C10", .no_connect),
        b.misc("A12", .no_connect),
        b.io("C9", 1, 7, 9),
        b.io("B9", 1, 7, 10),
        b.io("D9", 1, 7, 12),
        b.io("A11", 1, 7, 13),
        b.io("B8", 1, 7, 5),
        b.io("A9", 1, 7, 6),
        b.goe("B7", 1, 7, 0, 1),
        b.io("D7", 1, 7, 1),
        b.io("A8", 1, 7, 2),
        b.io("C8", 1, 7, 4),
        b.misc("L02", .tck),
        b.misc("A01", .tdi),
        b.misc("B11", .tdo),
        b.misc("M12", .tms),
        b.misc("E05", .vcc_core),
        b.misc("E08", .vcc_core),
        b.misc("H05", .vcc_core),
        b.misc("H08", .vcc_core),
        b.misc("D05", .vcco_bank_0),
        b.misc("E4", .vcco_bank_0),
        b.misc("F04", .vcco_bank_0),
        b.misc("G4", .vcco_bank_0),
        b.misc("J05", .vcco_bank_0),
        b.misc("D08", .vcco_bank_1),
        b.misc("F9", .vcco_bank_1),
        b.misc("G09", .vcco_bank_1),
        b.misc("H9", .vcco_bank_1),
        b.misc("J08", .vcco_bank_1),
    };
}
//[[ ######################### END OF GENERATED CODE ######################### ]]
