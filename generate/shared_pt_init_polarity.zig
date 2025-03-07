const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const lc4k = @import("lc4k");
const Device_Info = @import("Device_Info.zig");
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JEDEC_Data = lc4k.JEDEC_Data;
const Fuse = lc4k.Fuse;

pub fn main() void {
    helper.main();
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: *const Device_Info, writer: *sx.Writer) !void {
    const sptclk_polarity_fuses = try helper.parse_shared_pt_clock_polarity_fuses(ta, pa, dev);

    try writer.expression_expanded(@tagName(dev.device));
    try writer.expression_expanded("shared_pt_init_polarity");

    // The fitter seems to refuse to set this bit.  Attempting the same technique used for shared_pt_clk_polarity
    // (using out.AR- instead of out.AR) causes the fitter to say:
    // <Error>  F38026:  Unsupported low true Reset equation on signal 'out'.
    // The alternative would be using just a single inverted signal, but then the fitter just uses the complemented
    // GI input to the shared product term.
    //
    // The datasheet indicates that the shared init PT can be inverted, and it would make sense that it would
    // be near the PT clock polarity fuse.  Writing all zeros to a LC4032ZE showed that there is one mystery bit
    // in row 75, below the shared PT clock bit and shared PT OE bus bits.  Testing shows that toggling this fuse
    // does indeed invert the shared init PT.
    //
    // I have also tested this with an LC4064ZC.  In this device, there are four shared PT OE bus fuses instead of
    // two, so the init polarity bit is pushed down two rows.
    //
    // All devices *should* use one of these two layouts, but I have not tested any other variants.

    var glb: usize = 0;
    while (glb < sptclk_polarity_fuses.len) : (glb += 1) {
        try writer.expression("glb");
        try writer.int(glb, 10);
        try writer.expression("name");
        try writer.string(helper.get_glb_name(@intCast(glb)));
        try writer.close();
        writer.set_compact(false);

        const sptclk_fuse = sptclk_polarity_fuses[glb];
        const sptoe_bus_size = @min(4, dev.num_glbs);
        try helper.write_fuse(writer, Fuse.init(sptclk_fuse.row + 1 + sptoe_bus_size, sptclk_fuse.col));

        try writer.close(); // glb
    }

    try helper.write_value(writer, 0, "active_low");
    try helper.write_value(writer, 1, "active_high");

    try writer.done();

    _ = tc;
}
