const std = @import("std");
const helper = @import("helper.zig");
const toolchain = @import("toolchain.zig");
const sx = @import("sx");
const jedec = @import("jedec.zig");
const core = @import("core.zig");
const devices = @import("devices.zig");
const DeviceType = devices.DeviceType;
const Toolchain = toolchain.Toolchain;
const Design = toolchain.Design;
const JedecData = jedec.JedecData;
const Fuse = jedec.Fuse;

pub fn main() void {
    helper.main(1);
}

pub fn run(ta: std.mem.Allocator, pa: std.mem.Allocator, tc: *Toolchain, dev: DeviceType, writer: *sx.Writer(std.fs.File.Writer)) !void {
    const sptclk_polarity_fuses = try helper.parseSharedPTClockPolarityFuses(ta, pa, dev);

    try writer.expressionExpanded(@tagName(dev));
    try writer.expressionExpanded("shared_pt_async_polarity");

    // The fitter seems to refuse to set this bit.  Attempting the same technique used for shared_pt_clk_polarity
    // (using out.AR- instead of out.AR) causes the fitter to say:
    // <Error>  F38026:  Unsupported low true Reset equation on signal 'out'.
    // The alternative would be using just a single inverted signal, but then the fitter just uses the complemented
    // GI input to the shared product term.
    //
    // The datasheet indicates that the shared init PT can be inverted, and it would make sense that it would
    // be near the PT clock polarity fuse.  Writing all zeros to a LC4032ZE showed that there is one mystery bit
    // in row 75, below the shared PT clock bit and shared PT OE bus bits.  Testing shows that toggling this fuse
    // does indeed invert the shared async PT.
    //
    // I have also tested this with an LC4064ZC.  In this device, there are four shared PT OE bus fuses instead of
    // two, so the async polarity bit is pushed down two rows.
    //
    // All devices *should* use one of these two layouts, but I have not tested any other variants.

    var glb: usize = 0;
    while (glb < sptclk_polarity_fuses.len) : (glb += 1) {
        try writer.expression("glb");
        try writer.int(glb, 10);
        try writer.expression("name");
        try writer.string(devices.getGlbName(@intCast(u8, glb)));
        try writer.close();
        writer.setCompact(false);

        const sptclk_fuse = sptclk_polarity_fuses[glb];
        const sptoe_bus_size = @min(4, dev.getNumGlbs());
        try helper.writeFuse(writer, Fuse.init(sptclk_fuse.row + 1 + sptoe_bus_size, sptclk_fuse.col));

        try writer.close(); // glb
    }

    try writer.expression("value");
    try writer.int(0, 10);
    try writer.string("active_low");
    try writer.close();

    try writer.expression("value");
    try writer.int(1, 10);
    try writer.string("active_high");
    try writer.close();

    try writer.done();

    _ = tc;
}
