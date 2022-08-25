# Fusemaps for Lattice ispMach4000 CPLDs

# TODO
* LC4032ZE reverse engineering
* General documentation
* Bitstream configuration through zig
* Bitstream decompilation
* Save as JED
* Save as SVF

# TODO: LC4032ZE
* GLB inputs from GRP (WIP)
* Hardware verification
    * Shared PT Init polarity - hinted at in datasheet, but fitter won't let it happen
    * What happens if both GLB's PTOE/BIE are routed to the same GOE?  assuming they are summed, but should check with hardware.  I don't think the fitter will allow this config.
    * What happens if we write 0's to unused fuses?  Are they actually implemented as memory cells?
    * Which of the OSCTIMER output enables is for OSCOUT vs TIMEROUT?  Fitter always seems to enable them both at the same time.

# TODO: LC4064ZC

# TODO: LC4128ZE