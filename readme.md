# Fusemaps for Lattice ispMach4000 CPLDs

This repo contains reverse-engineered fusemaps for most of the commonly available LC4k CPLDs from Lattice.

Data is provided in text files containing machine and human readable S-Expressions describing the fuse locations that control each feature.
These are intended to be used to generate libraries so that CPLD configurations can be created using whatever programming language is desired.
Existing libraries include:

* [Zig-LC4k](https://github.com/bcrist/Zig-LC4k)

If you build a library/bindings for another language, let me know so I can list it here!

## Device List

|            |TQFP44|TQFP48|TQFP100|TQFP128|TQFP144|csBGA56|csBGA64|csBGA132|csBGA144|ucBGA64|ucBGA132|
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

LC4256 and larger devices are not supported at this time.
Automotive (LA4xxx) variants likely use the same fusemaps as their LC counterparts, but that's just conjecture.
Please don't use this project for any automotive or other safety-critical application.

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

#### MC Slice
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

All LC4k devices have a logical layout of fuses into a 2D grid with either 100 or 95 rows,
and a variable number of columns, depending on the number of GLBs in the device.
The JEDEC files list these fuses one row after another,
and when programming the device via JTAG each row is delivered in a separate SDR transaction.

The first 72 rows contain mostly product term fuses,
with one column for each product term in the device.
These rows also contain extra columns for the GI routing fuses (at least 3 columns per GLB).
This part of the fusemap is densely packed;
every single logical fuse corresponds to a bit of FLASH memory and controls the behavior of the device.

The remaining rows have a variety of uses, and are sparsely packed;
most bits don't actually correspond to FLASH memory cells, and always read as a `1`, even after attempting to program them to `0`.

Generally there is a single column corresponding to each macrocell slice, containing fuses that configure that macrocell slice.
These columns are arranged in groups of two, usually with 8 mostly-unused columns separating each pair.
Devices that only have 95 rows only have a single I/O cell per pair of macrocells.
Instead of placing all the I/O cell configuration fuses in the same column,
half of the fuses are shifted over to the adjacent macrocell's column,
reducing the total number of rows needed.

Each GLB has a few bits of block configuration which are placed in the "borders" to the left and right of the macrocell slice columns.
This includes fuses for configuring block clock source/polarity, shared PT polarity, and routing of the shared PT enable to the GOE bus.

Finally, global configuration is typically placed in a small, vaguely ring-shaped structure at the right edge of one of the GLB regions.
This includes configuration of input-only pins, GOE polarity, and oscillator/timer (in ZE devices).

## Bus Termination Options
2 fuses allow selection of one of four bus termination options:
    * pull up
    * pull down
    * bus-hold
    * floating/high-Z
In ZE family devices, this can be configured separately for each input pin.
In other families, there is only a single set of fuses which apply to the entire device.

### Bus Termination on non-ZE families with buried I/O cells
On certain non-ZE devices, setting all of the bus maintenance options off (i.e. floating inputs)
causes the fitter to toggle additional fuses beyond the two global bus maintenance fuses.
This only happens on devices where the die has I/O cells that aren't bonded to any package pin. (e.g. TQFP-44 packages)
Normally, these extra I/O cells are left as inputs,
but if inputs are allowed to float, this could cause excessive power usage,
so the fitter turns them into outputs by setting the appropriate OE mux fuses.
These fuses are documented in the `pull.sx` files within the `bus_maintenance_extra` section, if the device requires them.

## Input Threshold
The Lattice fitter allows each input signal's voltage standard to be selected from around a half dozen choices, including:
* 1.8V LVCMOS
* 2.5V LVCMOS
* 3.3V LVCMOS
* 3.3V LVTTL (5V-tolerant)
* 3.3V PCI (5V-tolerant)

The datasheets and IBIS models are quite vague about the actual input structure used in the devices,
but it turns out this configuration only affects one fuse per input,
so it seems that this fuse selects either a high or low input transition threshold.
Generally speaking, the high threshold is suitable for either 2.5V or 3.3V signals,
and the low threshold is for 1.8V or 1.5V signals.

Additionally, the datasheet mentions that inputs are only 5V-tolerant when V<sub>CCO</sub> is 3.3V,
so the protection diodes probably clamp relative to that rail rather than V<sub>CC</sub>.

The following are mostly guesses for the actual V<sub>th</sub> based on the published limits in the datasheet,
and assuming that the threshold is always referenced to V<sub>CC</sub>,
as opposed to using V<sub>CCO</sub> or an internal fixed voltage reference.

| V<sub>th</sub> | `-V`                      | `-B`                      | `-C`/`-ZC`                  | `-ZE`                    |
|:---------------|:-------------------------:|:-------------------------:|:---------------------------:|:------------------------:|
| low            | 0.28&times;V<sub>CC</sub> | 0.36&times;V<sub>CC</sub> | 0.5&times;V<sub>CC</sub>    | 0.5&times;V<sub>CC</sub> |
| high           | 0.4&times;V<sub>CC</sub>  | 0.5&times;V<sub>CC</sub>  | 0.73&times;V<sub>CC</sub>   | 0.68&times;V<sub>CC</sub> (falling edge)<br>0.79&times;V<sub>CC</sub> (rising edge) |

## Drive Type
One fuse per output controls whether the output is open-drain or push-pull.

Open-drain can also be emulated by outputing a constant low and using OE to enable or disable it,
but that places a lot of limitation on how much logic can be done in the macrocell;
only a single PT can be routed to the OE signal.

## Slew Rate
One fuse per output controls the slew rate for that driver.
SLOW should generally be used for any long traces or inter-board connections.
FAST can be used for short traces where transmission line effects are unlikely.

## Zero Hold Time
When a macrocell is configured as an input register,
an extra delay can be added to bring `tHOLD` down to 0.
This also means the setup time is increased as well.
This is controlled by a single fuse that affects the entire chip.
Registers whose data comes from product term logic are not affected by this fuse.

## GOE Numbering Conventions
All devices have 4 global OE signals.  The polarity of these signals can be configured globally, and their source depends on the device.

For LC4032 devices:

* GOE0: Shared PT OE bus bit 0
* GOE1: Shared PT OE bus bit 1
* GOE2: A0 input buffer
* GOE3: B15 input buffer

For other devices:

* GOE0: Selectable; either shared PT OE bus bit 0, or specific input buffer noted in datasheet
* GOE1: Selectable; either shared PT OE bus bit 1, or specific input buffer noted in datasheet
* GOE2: Shared PT OE bus bit 2
* GOE3: Shared PT OE bus bit 3

The shared PT OE bus is a set of 2 or 4 signals (depending on the device type, as above)
where each bit can be connected to any of the GLBs' shared enable PT
(note this is shared with the power guard feature on ZE devices).

# Fitter Bugs & Uncertainties

In the process of trying to get the LPF4k fitter to do what I want,
I've encountered a handful of bugs,
as well as some limitations which make it impossible to exercise certain hardware features.
In these cases, I've done my best to manually reverse engineer with real hardware,
but I don't have access to every device variant,
so I've also had to make some assumptions.
I'll try to document those here.

### Fitter won't route all GOEs
Even though there are four GOEs in every device,
the fitter will never route more than two of them in any particular design.
If you add more unique equations than that,
it'll start using PT4 as individual OE for the extra ones.
I tried adding a bunch of dummy logic product terms so that there isn't a free PT available,
but that doesn't convince it to do otherwise;
it'll just shout about failing to allocate everything.

It's also impossible to force the fitter to place a shared PT OE in a specific GLB.
This means I've had to make some assumptions about the locations of the shared PT OE bus fuses,
but based on testing with LC4032ZE and LC4064ZC devices,
I would be surprised if they don't hold for all devices.

### Negated GOE signals
When attempting to use a suffix of `.OE-` to create an active-low GOE,
the fitter report lists the correct equations,
but the JEDEC file that results is identical to one that just used `.OE`.
In order to coerce it to actually program the GOE polarity fuse,
you can invert the source signal instead,
but that only works when it's coming directly from an OE pin.
Otherwise it will just use the complemented signal in the shared PT OE.
This means it's really only possible to locate two of the GOE polarity fuses per device.
We have to infer the locations of the others by assuming that they're all in a contiguous block.

### Fitter won't set shared PT init polarity
Somewhat similar to the bug above,
the fitter will refuse to route a design that uses `.AR-` or `.AS-`.
Presumably this is because it's not able to invert the output of PT3 when that's used for initialization.
But when coming from the shared PT, there _is_ a configurable polarity;
it's just impossible to get the fitter to use it.
As above, if you invert a single signal, it will just encode that in the shared PT itself.
So again, we have to infer the location of this fuse based on where we know the shared PT clock polarity fuse is,
with hardware testing for verification.

### LC4128ZE_TQFP100 Missing Power Guard fuse for CLK0
Enabling a power guard instance for this pin on this particular device does not cause any fuse to be written.
The fitter does not give any warnings however,
and the dedicated clock power guard fuses for other package variants match this one,
except for this one fuse.
This leads me to assume that one line in the fitter source code probably got deleted or something,
causing it to skip this fuse.
I added a special case to force this to the fuse it (very likely) should be.

### LC4064ZC_csBGA56 Dedicated Inputs
The datasheet lists that this device has 32 I/Os and 12 input-only pins (4 clocks and 8 dedicated inputs).
I believe that two of the 8 dedicated inputs are actually just connected to regular macrocells.

There is quite a bit of evidence supporting this assumption:
* No other LC4064 or LC4128 packages have more than 6 dedicated inputs, even though some devices (e.g. `LC4064ZC_csBGA132`) have unconnected pins.  One would think if the die actually had 8 dedicated inputs, they would connect them to pins when possible.
* The LC4064s in TQFP-44 use a trick where only half the macrocells have corresponding I/O cells, resulting in a reduced JEDEC height of 95, but this device has a JEDEC height of 100, so internally it likely has the full complement of 64 I/O cells, with half of them unconnected.
* The GI routing fuses used for ball F8 are exactly the same as the fuses for macrocell C12's I/O in packages that expose it.
* The GI routing fuses used for ball E3 are exactly the same as the fuses for macrocell A15's I/O in packages that expose it.

Therefore, in the `pins.csv` file, I've listed balls E3 and F8 as I/Os corresponding to macrocells A15 and C12, respectively.
Attempting to assign these pins as outputs causes the fitter to spit out a warning,
so there are some fuses that I can't reverse engineer using the fitter.
In these cases I'm just copying the fuse locations from the corresponding macrocell in the `LC4064ZC_TQFP100` package,
under the assumption that it uses the same die.

Additionally, there appears to be a fitter bug relating to the input threshold fuse for balls F8 and E1.
The fitter toggles two input threshold fuses for the input on ball E1,
and no fuses for the input on ball F8.
Since F8 is one of the "weird" dedicated inputs,
I'm using the C12 macrocell's input threshold fuse from the TQFP100 package for that one,
just like I do for the output configuration fuses.
Then I can just exclude that fuse from the fuses the fitter toggled for ball E1,
which yields only one remaining correct fuse for that ball.

I don't have any of these devices to test physically, so to be safe,
you may just want to avoid using balls E1, E3, and F8 entirely for this particular device.

### Fitter Report missing GI data
For `LC4064ZC_csBGA56`, the second column (GIs 18-35) doesn't always show up in the fitter GI summary.
For some other devices, "input only" pins are incorrectly listed as sourced from a macrocell feedback signal.
e.g. for `LC4128ZC_TQFP100`, pin 12's source is listed as "mc B-11",
but the GI mux fuse that's set is one of the ones corresponding to pin 16 in `LC4128V_TQFP144`;
which is MC B14 and ORP B^11 in that device.
So it seems the fitter is writing the I/O cell's ID in this case, rather than the actual pin number.

# TODO
* Refactor routing jobs to use common.ClusterRouting, common.WideRouting
* Rename pull.zig/sx to bus_maintenance.zig/sx
* power_guard.sx says "enabled" instead of "from_bie"
* Hardware experiments
    * Why are there two fuses to enable the OSCTIMER? what happens if only one is enabled? (or none, but divider/outputs are enabled)
    * Do OSCTIMER outputs only replace the GRP feedback signals when enabled, or also the signal that goes to the ORM?
    * Can you use input register feedback on MCs that aren't connected to pins? (e.g. LC4064x TQFP48)
    * Can you use an input register MC with the ORM to have the register output directly on a different pin without going through the GRP?
    * What happens if you violate the one-cold rule for GI fuses?
    * What happens if you violate the one-cold rule for the PT OE internal bus?
    * When using fast 5-PT combinational path on non-ZE parts, can you use the register as a buried macrocell?