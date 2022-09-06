# Fusemaps for Lattice ispMach4000 CPLDs

# TODO
* General documentation of LC4k architecture
* Convert LCI/TT4 generation from lua/limp to zig
* Bitstream configuration through zig
* Bitstream decompilation

* pull.zig: TQFP44 devices and some ZC devices have some extra fuses?


# TODO: LC4032ZE
* GLB inputs from GRP (WIP)
* Hardware verification
    * Shared PT Init polarity - hinted at in datasheet, but fitter won't let it happen
    * What happens if both GLB's PTOE/BIE are routed to the same GOE?  assuming they are summed, but should check with hardware.  I don't think the fitter will allow this config.
    * What happens if we write 0's to unused fuses?  Are they actually implemented as memory cells?
    * Which of the OSCTIMER output enables is for OSCOUT vs TIMEROUT?  Fitter always seems to enable them both at the same time.







# Input Threshold
When an input expects to see 2.5V or higher inputs, this fuse should be used to increase the threshold voltage for that input.

This probably also controls whether or not the 200mV input hysteresis should be applied (according to the datasheet it's active at 2.5V and 3.3V)
