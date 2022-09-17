//[[!! include('device', 'LC4064ZE_csBGA144') !! 157 ]]
//[[ ################# !! GENERATED CODE -- DO NOT MODIFY !! ################# ]]
const std = @import("std");
const device_pins = @import("device_pins.zig");

pub const pins = buildPins();

fn buildPins() [144]device_pins.PinInfo {
    var b = device_pins.PinInfoBuilder {};
    return .{
        b.misc("B5", .no_connect),
        b.misc("A5", .no_connect),
        b.goe("D6", 0, 0, 0, 0),
        b.io("B6", 0, 0, 1),
        b.io("A6", 0, 0, 2),
        b.io("C6", 0, 0, 3),
        b.misc("C4", .no_connect),
        b.misc("B3", .no_connect),
        b.misc("A2", .no_connect),
        b.io("A4", 0, 0, 4),
        b.io("B4", 0, 0, 5),
        b.io("C5", 0, 0, 6),
        b.io("A3", 0, 0, 7),
        b.misc("B1", .no_connect),
        b.misc("B2", .no_connect),
        b.io("D1", 0, 0, 11),
        b.io("C1", 0, 0, 10),
        b.io("C2", 0, 0, 9),
        b.io("C3", 0, 0, 8),
        b.clk("A7", 0, 0, 0),
        b.clk("L6", 0, 1, 1),
        b.clk("M6", 1, 2, 2),
        b.clk("C7", 1, 3, 3),
        b.in("F3", 0, 0),
        b.misc("E1", .no_connect),
        b.misc("D3", .no_connect),
        b.misc("D2", .no_connect),
        b.io("F1", 0, 0, 15),
        b.io("D4", 0, 0, 14),
        b.io("F2", 0, 0, 13),
        b.io("E2", 0, 0, 12),
        b.io("G1", 0, 1, 15),
        b.misc("H3", .no_connect),
        b.misc("H2", .no_connect),
        b.io("E3", 0, 1, 14),
        b.io("G2", 0, 1, 13),
        b.io("G3", 0, 1, 12),
        b.misc("H1", .no_connect),
        b.in("K2", 0, 1),
        b.misc("L1", .no_connect),
        b.io("J1", 0, 1, 11),
        b.io("J3", 0, 1, 10),
        b.io("J2", 0, 1, 9),
        b.io("K1", 0, 1, 8),
        b.io("L4", 0, 1, 4),
        b.misc("M2", .no_connect),
        b.misc("K3", .no_connect),
        b.misc("M1", .no_connect),
        b.io("M3", 0, 1, 5),
        b.io("K4", 0, 1, 6),
        b.io("J4", 0, 1, 7),
        b.in("L3", 0, 1),
        b.misc("F06", .gnd),
        b.misc("F07", .gnd),
        b.misc("G06", .gnd),
        b.misc("G07", .gnd),
        b.misc("E6", .no_connect),
        b.misc("F05", .gnd),
        b.misc("G05", .gnd),
        b.misc("H04", .gnd),
        b.misc("H06", .gnd),
        b.misc("E07", .gnd),
        b.misc("F08", .gnd),
        b.misc("G08", .gnd),
        b.misc("H7", .no_connect),
        b.misc("J09", .gnd),
        b.misc("L5", .no_connect),
        b.misc("M4", .no_connect),
        b.io("K6", 0, 1, 0),
        b.io("M5", 0, 1, 1),
        b.io("J6", 0, 1, 2),
        b.io("K5", 0, 1, 3),
        b.misc("L8", .no_connect),
        b.misc("M8", .no_connect),
        b.io("K7", 1, 2, 0),
        b.io("M7", 1, 2, 1),
        b.io("L7", 1, 2, 2),
        b.io("J7", 1, 2, 3),
        b.misc("L10", .no_connect),
        b.misc("K9", .no_connect),
        b.misc("M11", .no_connect),
        b.io("M9", 1, 2, 4),
        b.io("L9", 1, 2, 5),
        b.io("K8", 1, 2, 6),
        b.io("M10", 1, 2, 7),
        b.misc("L11", .no_connect),
        b.misc("L12", .no_connect),
        b.io("K11", 1, 2, 11),
        b.io("J10", 1, 2, 10),
        b.io("K12", 1, 2, 9),
        b.io("K10", 1, 2, 8),
        b.in("G10", 1, 2),
        b.misc("H10", .no_connect),
        b.misc("J11", .no_connect),
        b.misc("J12", .no_connect),
        b.io("G12", 1, 2, 15),
        b.io("H11", 1, 2, 14),
        b.io("G11", 1, 2, 13),
        b.io("H12", 1, 2, 12),
        b.io("F12", 1, 3, 15),
        b.misc("F10", .no_connect),
        b.misc("D12", .no_connect),
        b.io("F11", 1, 3, 14),
        b.io("E11", 1, 3, 13),
        b.io("E12", 1, 3, 12),
        b.misc("D10", .no_connect),
        b.in("C11", 1, 3),
        b.misc("B12", .no_connect),
        b.io("E10", 1, 3, 11),
        b.io("D11", 1, 3, 10),
        b.io("E9", 1, 3, 9),
        b.io("C12", 1, 3, 8),
        b.io("A10", 1, 3, 4),
        b.misc("B10", .no_connect),
        b.misc("C10", .no_connect),
        b.misc("A12", .no_connect),
        b.io("C9", 1, 3, 5),
        b.io("B9", 1, 3, 6),
        b.io("D9", 1, 3, 7),
        b.in("A11", 1, 3),
        b.misc("B8", .no_connect),
        b.misc("A9", .no_connect),
        b.goe("B7", 1, 3, 0, 1),
        b.io("D7", 1, 3, 1),
        b.io("A8", 1, 3, 2),
        b.io("C8", 1, 3, 3),
        b.misc("L02", .tck),
        b.misc("A01", .tdi),
        b.misc("B11", .tdo),
        b.misc("M12", .tms),
        b.misc("E05", .vcc_core),
        b.misc("E08", .vcc_core),
        b.misc("H05", .vcc_core),
        b.misc("H08", .vcc_core),
        b.misc("D05", .vcco_bank_0),
        b.misc("E4", .no_connect),
        b.misc("F04", .vcco_bank_0),
        b.misc("G4", .no_connect),
        b.misc("J05", .vcco_bank_0),
        b.misc("D08", .vcco_bank_1),
        b.misc("F9", .no_connect),
        b.misc("G09", .vcco_bank_1),
        b.misc("H9", .no_connect),
        b.misc("J08", .vcco_bank_1),
    };
}
//[[ ######################### END OF GENERATED CODE ######################### ]]