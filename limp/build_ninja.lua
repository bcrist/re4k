device = {}
include 'lc4032ze'

local default_targets = {}

local write_build = template [[
build `file`.tt4: copy pla/`pla`.pla
build `file`.jed: fit `file`.lci | `file`.tt4
]]

function writeReadme (device, test_name, readme)
    if readme ~= nil then
        fs.ensure_dir_exists(fs.compose_path(device.name, test_name))
        fs.put_file_contents(fs.compose_path(device.name, test_name, 'readme.md'), readme)
    end
end

function globalTest (device, test_name, variants, pla, readme)
    writeReadme(device, test_name, readme)
    local base = fs.compose_path(device.name, test_name)
    fs.ensure_dir_exists(base)

    for _, variant in ipairs(variants) do
        local file = fs.compose_path(base, variant)
        fs.put_file_contents(file..'.lci', '//[[!! include "lci"; write_lci_'..test_name..'(device.'..device.name..', "'..variant..'") ]]')
        write_build { pla = pla, file = file }
    end

    local csv = fs.compose_path(base, "fuses.csv")
    write("build ", csv, ": udiff")
    for _, variant in ipairs(variants) do
        write(" ", fs.compose_path(base, variant..".jed"))
    end
    nl()
    nl()

    writeln("build ", test_name, ": phony ", csv)
    nl()
    default_targets[#default_targets+1] = test_name
end

function perGlbTest (device, test_name, variants, pla, readme)
    local targets = {}

    writeReadme(device, test_name, readme)

    for glb, glb_data in spairs(device.glb) do
        local base = fs.compose_path(device.name, test_name, 'glb'..glb)
        fs.ensure_dir_exists(base)

        for _, variant in ipairs(variants) do
            local file = fs.compose_path(base, variant)
            fs.put_file_contents(file..'.lci', '//[[!! include "lci"; write_lci_'..test_name..'(device.'..device.name..', "'..glb..'", "'..variant..'") ]]')
            write_build { pla = pla, file = file }
        end

        local csv = base .. "_fuses.csv"
        targets[#targets+1] = csv
        write("build ", csv, ": udiff")
        for _, variant in ipairs(variants) do
            write(" ", fs.compose_path(base, variant..".jed"))
        end
        nl()
        nl()
    end

    write("build ", test_name, ": phony")
    for _, target in ipairs(targets) do
        write(" ", target)
    end
    nl()
    nl()
    default_targets[#default_targets+1] = test_name
end

function perMacrocellTest(device, test_name, variants, pla, readme)
    local targets = {}

    writeReadme(device, test_name, readme)

    for glb, glb_data in spairs(device.glb) do
        for mc in spairs(glb_data.mc_to_pin) do
            local base = fs.compose_path(device.name, test_name, 'glb'..glb, 'mc'..mc)
            fs.ensure_dir_exists(base)

            for _, variant in ipairs(variants) do
                local file = fs.compose_path(base, variant)
                fs.put_file_contents(file..'.lci', '//[[!! include "lci"; write_lci_'..test_name..'(device.'..device.name..', "'..glb..'", "'..mc..'", "'..variant..'") ]]')
                write_build { pla = pla, file = file }
            end

            local csv = base .. "_fuses.csv"
            targets[#targets+1] = csv
            write("build ", csv, ": udiff")
            for _, variant in ipairs(variants) do
                write(" ", fs.compose_path(base, variant..".jed"))
            end
            nl()
            nl()
        end
    end

    write("build ", test_name, ": phony")
    for _, target in ipairs(targets) do
        write(" ", target)
    end
    nl()
    nl()
    default_targets[#default_targets+1] = test_name
end

local dev = device.lc4032ze

perMacrocellTest(dev, 'pull', { 'OFF', 'UP', 'DOWN', 'HOLD' }, 'and_31in_1out', [[
2 fuses per I/O allow configuration of pull up, pull down, bus-hold, or high-Z input conditioning.
]])
perMacrocellTest(dev, 'input_threshold', { 'LVCMOS33', 'LVCMOS15' }, 'and_31in_1out', [[
When an input expects to see 2.5V or higher inputs, this fuse should be used to increase the threshold voltage for that input.
]])
perMacrocellTest(dev, 'od', { 'LVCMOS33', 'LVCMOS33_OD' }, 'buf_1in_32out', [[
One fuse per output controls whether the output is open-drain or totem-pole.

Open-drain can also be emulated by outputing a constant low and using OE to enable or disable it, but that places a lot of limitation on how much logic can be done in the macrocell.
]])
perMacrocellTest(dev, 'slew', { 'SLOW', 'FAST' }, 'buf_1in_32out', [[
One fuse per output controls the slew rate for that driver.

SLOW should generally be used for any long traces or inter-board connections.
FAST can be used for short traces where transmission line effects are unlikely.
]])

globalTest(dev, 'zerohold', { 'no', 'yes' }, 'buf_1in_32out', [[
When this fuse is enabled, registered inputs have an extra delay added to bring `tHOLD` down to 0.

This also means the setup time is increased as well.

Registers whose data comes from product term logic are not affected by this fuse.

This fuse affects the entire chip.
]])


write("default")
for _, target in ipairs(default_targets) do
    write(" ", target)
end
nl()
