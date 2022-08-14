include 'lc4032ze'

local default_targets = {}

local write_build = template [[
build `file`.tt4: copy pla/`pla`.pla
build `file`.jed: fit `file`.lci | `file`.tt4
]]

local function writeReadme (device, test_name, readme)
    if readme ~= nil then
        fs.ensure_dir_exists(fs.compose_path(device.name, test_name))
        fs.put_file_contents(fs.compose_path(device.name, test_name, 'readme.md'), readme)
    end
end

local function writeVariants (device, test_name, variants, pla, extra_path, extra_params, targets, test_name_suffix)
    local base_path = fs.compose_path(device.name, test_name)
    if extra_path ~= nil then
        if type(extra_path) == 'table' then
            base_path = fs.compose_path(base_path, table.unpack(extra_path))
        else
            base_path = fs.compose_path(base_path, extra_path)
        end
    end

    local write_lci = 'write_lci_'..test_name
    if test_name_suffix ~= nil then
        write_lci = write_lci..test_name_suffix
    end

    fs.ensure_dir_exists(base_path)

    for v, variant in ipairs(variants) do
        local file = fs.compose_path(base_path, variant)
        local limp = '//[[!! include "lci"; '..write_lci..'(device.'..device.name
        if extra_params ~= nil then
            if type(extra_params) == 'table' then
                limp = limp..', '..table.concat(extra_params, ', ')
            else
                limp = limp..', '..extra_params
            end
        end
        limp = limp..', "'..variant..'") ]]'
        fs.put_file_contents(file..'.lci', limp)

        if type(pla) == 'table' then
            write_build { pla = pla[v], file = file }
        else
            write_build { pla = pla, file = file }
        end
    end

    local csv
    if targets == nil then
        csv = fs.compose_path(base_path, "fuses.csv")
    else
        csv = base_path.."_fuses.csv"
        targets[#targets+1] = csv
    end
    write("build ", csv, ": udiff")
    for _, variant in ipairs(variants) do
        write(" ", fs.compose_path(base_path, variant..".jed"))
    end
    nl()
    nl()

    return csv
end

local function writeMcVariants(device, test_name, variants, pla, mc, targets)
    writeVariants(device, test_name, variants, pla, { 'glb'..mc.glb.index, 'mc'..mc.index }, { mc.glb.index, mc.index }, targets)
end

local function writePhony (test_name, targets)
    write("build ", test_name, ": phony")
    for _, target in ipairs(targets) do
        write(" ", target)
    end
    nl()
    nl()
    default_targets[#default_targets+1] = test_name
end

function globalTest (device, test_name, variants, pla, readme)
    writeReadme(device, test_name, readme)
    local csv = writeVariants(device, test_name, variants, pla)
    writePhony(test_name, { csv })
end

function perGlbTest (device, test_name, variants, pla, readme)
    local targets = {}
    writeReadme(device, test_name, readme)
    for glb in device.glbs() do
        writeVariants(device, test_name, variants, pla, 'glb'..glb, glb, targets)
    end
    writePhony(test_name, targets)
end

function perMacrocellTest(device, test_name, variants, pla, readme)
    local targets = {}
    writeReadme(device, test_name, readme)
    for _, glb in device.glbs() do
        for _, mc in glb.mcs() do
            writeMcVariants(device, test_name, variants, pla, mc, targets)
        end
    end
    writePhony(test_name, targets)
end

function perOutputTest(device, test_name, variants, pla, readme)
    local targets = {}
    writeReadme(device, test_name, readme)
    for _, glb in device.glbs() do
        for _, mc in glb.mcs() do
            if mc.pin ~= nil then
                writeMcVariants(device, test_name, variants, pla, mc, targets)
            end
        end
    end
    writePhony(test_name, targets)
end

function perInputTest(device, test_name, variants, pla, readme)
    local targets = {}
    writeReadme(device, test_name, readme)
    for _, glb in device.glbs() do
        for _, mc in glb.mcs() do
            if mc.pin ~= nil then
                writeMcVariants(device, test_name, variants, pla, mc, targets)
            end
        end
    end
    for _, clk in device.clks() do
        writeVariants(device, test_name, variants, pla, { 'input', clk.name }, clk.index, targets, '_clk')
    end
    writePhony(test_name, targets)
end

local dev = device.lc4032ze

perInputTest(dev, 'pull', { 'OFF', 'UP', 'DOWN', 'HOLD' }, 'and_31in_1out', [[
2 fuses per I/O allow configuration of pull up, pull down, bus-hold, or high-Z input conditioning.
]])
perInputTest(dev, 'input_threshold', { 'LVCMOS33', 'LVCMOS15' }, 'and_31in_1out', [[
When an input expects to see 2.5V or higher inputs, this fuse should be used to increase the threshold voltage for that input.

This probably also controls whether or not the 200mV input hysteresis should be applied (according to the datasheet it's active at 2.5V and 3.3V)
]])
perOutputTest(dev, 'od', { 'LVCMOS33', 'LVCMOS33_OD' }, 'buf_1in_32out', [[
One fuse per output controls whether the output is open-drain or totem-pole.

Open-drain can also be emulated by outputing a constant low and using OE to enable or disable it, but that places a lot of limitation on how much logic can be done in the macrocell.
]])
perOutputTest(dev, 'slew', { 'SLOW', 'FAST' }, 'buf_1in_32out', [[
One fuse per output controls the slew rate for that driver.

SLOW should generally be used for any long traces or inter-board connections.
FAST can be used for short traces where transmission line effects are unlikely.
]])

globalTest(dev, 'zerohold', { 'no', 'yes' }, 'buf_1in_1out', [[
When this fuse is enabled, registered inputs have an extra delay added to bring `tHOLD` down to 0.

This also means the setup time is increased as well.

Registers whose data comes from product term logic are not affected by this fuse.

This fuse affects the entire chip.
]])

-- globalTest(dev, 'security', { 'on', 'off' }, 'buf_1in_1out', [[
-- Prevents reading flash?
-- ]])

perGlbTest(dev, 'bclk01', { 'passthru', 'invert_both', 'clk0_comp', 'clk1_comp' }, { 'bclk_passthru', 'bclk_both_inverted', 'bclk_clk0', 'bclk_clk1' })
perGlbTest(dev, 'bclk23', { 'passthru', 'invert_both', 'clk2_comp', 'clk3_comp' }, { 'bclk_passthru', 'bclk_both_inverted', 'bclk_clk0', 'bclk_clk1' })

perInputTest(dev, 'pgdf', { 'pg', 'pg_disabled' }, { 'pg2', 'pg1' })

write("default")
for _, target in ipairs(default_targets) do
    write(" ", target)
end
nl()
