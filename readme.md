# Fusemaps for Lattice ispMach4000 CPLDs

This repo contains reverse-engineered fusemaps for most of the commonly available LC4k CPLDs from Lattice.

Data is provided in text files containing machine and human readable S-Expressions describing the fuse locations that
control each feature.  These are intended to be used to generate libraries so that CPLD configurations can be created
using whatever programming language is desired.

## Device List

|            |TQFP44|TQFP48|TQFP100|TQFP128|TQFP144|csBGA56|csBGA64|csBGA132|csBGA144|ucBGA64|ucBGA144|
|:-----------|:----:|:----:|:-----:|:-----:|:-----:|:-----:|:-----:|:------:|:------:|:-----:|:------:|
|LC4032V/B/C | ✔️    | ✔️    |       |       |       |       |       |        |        |       |        |
|LC4032ZC    |      | ✔️    |       |       |       | ✔️     |       |        |        |       |        |
|LC4032ZE    |      | ✔️    |       |       |       |       | ✔️     |        |        |       |        |
|LC4064V/B/C | ✔️    | ✔️    | ✔️     |       |       |       |       |        |        |       |        |
|LC4064ZC    |      | ✔️    | ✔️     |       |       | ✔️     |       | ✔️      |        |       |        |
|LC4064ZE    |      | ✔️    | ✔️     |       |       |       | ✔️     |        | ✔️      | ✔️     |        |
|LC4128V     |      |      | ✔️     | ✔️     | ✔️     |       |       |        |        |       |        |
|LC4128B/C   |      |      | ✔️     | ✔️     |       |       |       |        |        |       |        |
|LC4128ZC    |      |      | ✔️     |       |       |       |       | ✔️      |        |       |        |
|LC4128ZE    |      |      | ✔️     |       | ✔️     |       |       |        | ✔️      |       | ✔️      |

LC4256 and larger devices are not supported at this time.  Automotive (LA4xxx) variants likely use
the same fusemaps as their LC counterparts, but that's just conjecture.  Please don't use this
project for any automotive or other safety-critical application.

## Jargon

#### GLB
Generic Logic Block: A group of 36 GIs, 83 PTs, 16 MCs, and the other logic associated with them.  Each device contains two or more GLBs.

#### GRP
Global Routing Pool: the set of all signals that can be used as inputs to a GLB.  This includes all I/O cell pins, feedback from all MCs, dedicated clock pins, and (in some devices) dedicated input pins.

#### GI
Generic Input: One of 36 signals per GLB which can be used in that GLB's product terms.

#### PT
Product Term: Up to 36 signals (or their complements) ANDed together.

#### MC
Macrocell: A single flip-flop or combinational logic "output".

### MC Slice
Macrocell Slice: A 5-PT cluster, macrocell, routing logic, and I/O cell.  Each GLB contains 16 MC Slices, along with the 3 shared PTs, BCLK and GI configuration.

#### ORM
Output Routing Multiplexer: Allows macrocells and their associated OE product term to be shunted to a different nearby pin.

#### BCLK
Block Clock: Each GLB ("Block") can independently configure the polarity of the dedicated clock inputs.

#### BIE
Block Input Enable: For ZE-family devices, inputs can be dynamically masked to reduce power consumption.

#### GOE
Global Output Enable: Up to four signals which can come from specific input pins, or from the BIE shared PTs.

#### CE
Clock Enable

#### LE
Latch Enable

#### AS
Asynchronous (pre)Set

#### AR
Asynchronous Reset/clear


## General Fusemap Layout

All LC4k devices have a logical layout of fuses into a 2D grid with either 100 or 95 rows, and a variable number of columns, depending on the number of GLBs in the device.  The JEDEC files list these fuses one
row after another, and when programming the device via JTAG, each row is delivered in a separate SDR transaction.

The first 72 rows contain mostly product term fuses, with one column for each product term in the device.  These rows also contain extra columns for the GI routing fuses (at least 3 columns per GLB).

The lower 28 rows (or 23 for devices with only 95 rows) contain macrocell and I/O cell configuration, as well as cluster and output routing fuses, and global configuration.  This area is logically much larger
than necessary, but the unused "fuses" are not backed by EEPROM; trying to program them to 0 will have no effect and they will always read back as 1.  Each macrocell slice is controlled mostly by fuses in one
specific column, and pairs of macrocell slices are grouped together, so overall there will be 2 columns used, then 8 columns unused, then 2 more used columns, etc.

# TODO
* Single combined .sx file for each device - check that no fuse is marked for multiple uses and every expected fuse is mentioned once
* Bitstream configuration through zig
* Bitstream decompilation
* Hardware verification
    * What happens if both GLB's PTOE/BIE are routed to the same GOE?  assuming they are summed, but should check with hardware.  I don't think the fitter will allow this config.
    * Which of the OSCTIMER output enables is for OSCOUT vs TIMEROUT?  Fitter always seems to enable them both at the same time.
    * There are two mystery fuses directly under the OSCTIMER divider fuses.  Possibly input enable flags for TIMERRES and DYNOSCDIS?
    * Can you use input register feedback on MCs that aren't connected to pins?
    * What happens if you violate the one-cold rule for GIs fuses?


## Bus Termination Options
2 fuses allow selection of one of four bus termination options:
    * pull up
    * pull down
    * bus-hold
    * floating/high-Z
In ZE family devices, this can be configured separately for each input pin.  In other families, there is only a single set of fuses which apply to the entire device.

### Bus Termination on non-ZE families with buried I/O cells
On certain non-ZE devices, setting all of the bus maintenance options off (i.e. floating inputs) causes the fitter to toggle additional fuses beyond the two global bus maintenance fuses.  This only happens on devices where the die has I/O cells that aren't bonded to any package pin.  (e.g. TQFP-44 packages)  Normally, these extra I/O cells are left as inputs, but if inputs are allowed to float, this could cause excessive power usage, so the fitter turns them into outputs by setting the appropriate OE mux fuses.  These fuses are documented in the `pull.sx` files within the `bus_maintenance_extra` section, if the device requires them.

## Input Threshold
When an input expects to see 2.5V or higher inputs, this fuse should be used to increase the threshold voltage for that input.

This probably also controls whether or not the 200mV input hysteresis should be applied in the ZE series(according to the datasheet it's active at 2.5V and 3.3V)

## Drive Type
One fuse per output controls whether the output is open-drain or push-pull.

Open-drain can also be emulated by outputing a constant low and using OE to enable or disable it, but that places a lot of limitation on how much logic can be done in the macrocell; only a single PT can be routed to the OE signal.

## Slew Rate
One fuse per output controls the slew rate for that driver.
SLOW should generally be used for any long traces or inter-board connections.
FAST can be used for short traces where transmission line effects are unlikely.

## Zero Hold Time
When a macrocell is configured as an input register, an extra delay can be added to bring `tHOLD` down to 0.  This also means the setup time is increased as well.  This is controlled by a single fuse that affects the entire chip.  Registers whose data comes from product term logic are not affected by this fuse.

## Input Threshold
When an input expects to see 2.5V or higher inputs, this fuse should be used to increase the threshold voltage for that input.

This probably also controls whether or not the 200mV input hysteresis should be applied (according to the datasheet it's active at 2.5V and 3.3V)

## GOE Numbering Conventions
All devices have 4 global OE signals.  The polarity of these signals can be configured globally, and their source depends on the device.

For LC4032 devices:

- GOE0: Shared PT OE bus bit 0
- GOE1: Shared PT OE bus bit 1
- GOE2: A0 input buffer
- GOE3: B15 input buffer

For other devices:

- GOE0: Selectable; either shared PT OE bus bit 0, or specific input buffer noted in datasheet
- GOE1: Selectable; either shared PT OE bus bit 1, or specific input buffer noted in datasheet
- GOE2: Shared PT OE bus bit 2
- GOE3: Shared PT OE bus bit 3

The shared PT OE bus is a set of 2 or 4 signals (depending on the device type, as above) where each bit can be connected to any of the GLBs' shared enable PT (note this is shared with the power guard feature on ZE devices).
