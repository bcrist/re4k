# Fusemaps for Lattice ispMach4000 CPLDs

# TODO
* General documentation of LC4k architecture
* Convert LCI/TT4 generation from lua/limp to zig
* Bitstream configuration through zig
* Bitstream decompilation
* PT4 OE routing fuse
* shared clk/init polarity
* goe polarity
* OSCTIMER for ZE family
* power guard for ZE family
* Hardware verification
    * Shared PT Init polarity - hinted at in datasheet, but fitter won't let it happen
    * What happens if both GLB's PTOE/BIE are routed to the same GOE?  assuming they are summed, but should check with hardware.  I don't think the fitter will allow this config.
    * What happens if we write 0's to unused fuses?  Are they actually implemented as memory cells?
    * Which of the OSCTIMER output enables is for OSCOUT vs TIMEROUT?  Fitter always seems to enable them both at the same time.
    * Can you use input register feedback on MCs that aren't connected to pins?


# Bus Termination Options
2 fuses allow selection of one of four bus termination options:
    * pull up
    * pull down
    * bus-hold
    * floating/high-Z
In ZE family devices, this can be configured separately for each input pin.  In other families, there is only a single set of fuses which apply to the entire device.

## Bus Termination on non-ZE families with buried I/O cells
On certain non-ZE devices, setting all of the bus maintenance options off (i.e. floating inputs) causes the fitter to toggle additional fuses beyond the two global bus maintenance fuses.  This only happens on devices where the die has I/O cells that aren't bonded to any package pin.  (e.g. TQFP-44 packages)  Normally, these extra I/O cells are left as inputs, but if inputs are allowed to float, this could cause excessive power usage, so the fitter turns them into outputs by setting the appropriate OE mux fuses.  These fuses are documented in the `pull.sx` files within the `bus_maintenance_extra` section, if the device requires them.

# Input Threshold
When an input expects to see 2.5V or higher inputs, this fuse should be used to increase the threshold voltage for that input.

This probably also controls whether or not the 200mV input hysteresis should be applied in the ZE series(according to the datasheet it's active at 2.5V and 3.3V)

# Drive Type
One fuse per output controls whether the output is open-drain or push-pull.

Open-drain can also be emulated by outputing a constant low and using OE to enable or disable it, but that places a lot of limitation on how much logic can be done in the macrocell; only a single PT can be routed to the OE signal.

# Slew Rate
One fuse per output controls the slew rate for that driver.
SLOW should generally be used for any long traces or inter-board connections.
FAST can be used for short traces where transmission line effects are unlikely.

# Zero Hold Time
When a macrocell is configured as an input register, an extra delay can be added to bring `tHOLD` down to 0.  This also means the setup time is increased as well.  This is controlled by a single fuse that affects the entire chip.  Registers whose data comes from product term logic are not affected by this fuse.

# Input Threshold
When an input expects to see 2.5V or higher inputs, this fuse should be used to increase the threshold voltage for that input.

This probably also controls whether or not the 200mV input hysteresis should be applied (according to the datasheet it's active at 2.5V and 3.3V)

# GOE Numbering Conventions
I've chosen to make some assumptions regarding the naming of GOE signals.

    * The 3 fuses are placed in little endian order in the 3 rows dedicated to them (e.g. for devices with 100 rows, row 92's fuse has value 1, 93's has value 2, and 94's has value 4)
    * The names specified in figure 8 in the datasheets correspond to values 0-7, from top to bottom, encoded as described above.

For OE mux values 4-7, the above assumptions are consistent with the fitter output.  For the GOE0-3 inputs, the exact naming is mostly arbitrary.  There are two external pins labeled GOE0 and GOE1 which can be routed directly to one specific internal GOE signal, but there's no real reason it has to be internal GOE0 and 1.  In fact, under these rules the external GOE0/1 are routed to internal GOE2/3 (at least on the LC4032)

