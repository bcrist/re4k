include 'lc4032ze'

local default_targets = {}
local group_targets = {}

local write_build = template [[
build `file`.jed: fit `file`.lci | `file`.tt4
]]

local function writeReadme (device, test_name, extra)
    local t = type(extra)
    local readme
    if t == 'table' then
        readme = extra.readme
    elseif t == 'string' then
        readme = extra
    end
    if readme ~= nil then
        fs.ensure_dir_exists(fs.compose_path(device.name, test_name))
        fs.put_file_contents(fs.compose_path(device.name, test_name, 'readme.md'), readme)
    end
end

local limp_end_tokens = { ['!!'] = true, [']]'] = true }

local function writeVariants (device, test_name, variants, extra_path, extra_params, targets, extra)
    local diff_options
    local test_name_suffix
    if extra ~= nil then
        diff_options = extra.diff_options
        test_name_suffix = extra.test_name_suffix
    end

    local base_path = fs.compose_path(device.name, test_name)
    if extra_path ~= nil then
        if type(extra_path) == 'table' then
            base_path = fs.compose_path(base_path, table.unpack(extra_path))
        else
            base_path = fs.compose_path(base_path, extra_path)
        end
    end

    local write_lci = 'write_lci_'..(test_name:gsub('/', '_'))
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
        limp = limp..', "'..variant..'") '

        local limp_len = #limp
        local old_limp = fs.get_file_contents(file..'.lci')
        if old_limp == nil
                or old_limp:sub(1,limp_len) ~= limp
                or limp_end_tokens[old_limp:sub(limp_len+1,limp_len+2)] == nil
                then
            fs.put_file_contents(file..'.lci', limp..']]')
        end

        write_build { file = file }
    end

    local csv
    if targets == nil then
        csv = fs.compose_path(base_path, "fuses.csv")
    else
        csv = base_path.."_fuses.csv"
        targets[csv] = true
    end
    write("build ", csv, ": diff")
    for _, variant in ipairs(variants) do
        write(" ", fs.compose_path(base_path, variant..".jed"))
    end
    nl()
    if diff_options ~= nil then
        writeln("    diff_options = ", diff_options)
    end
    nl()

    return csv
end

local function writeMcVariants(device, test_name, variants, mc, targets, extra)
    if type(variants) == 'function' then
        variants = variants(mc)
    end
    if variants ~= nil then
        writeVariants(device, test_name, variants, { 'glb'..mc.glb.index, 'mc'..mc.index }, { mc.glb.index, mc.index }, targets, extra)
    end
end

local function writeGlbVariants(device, test_name, variants, glb, targets, extra)
    if type(variants) == 'function' then
        variants = variants(glb)
    end
    if variants ~= nil then
        writeVariants(device, test_name, variants, 'glb'..glb.index, glb.index, targets, extra)
    end
end

local function addToGroup (group, targets)
    local existing = group_targets[group]
    if existing == nil then
        group_targets[group] = targets
    else
        for target in pairs(targets) do
            existing[target] = true
        end
    end
    local parent = group:gsub('/[^/]+$', '')
    if parent ~= group then
        addToGroup(parent, {[group] = true})
    else
        default_targets[group] = true
    end
end

function globalTest (device, test_name, variants, extra)
    writeReadme(device, test_name, extra)
    if type(variants) == 'function' then
        variants = variants(mc)
    end
    if variants ~= nil then
        local csv = writeVariants(device, test_name, variants, nil, nil, nil, extra)
        addToGroup(test_name, {[csv] = true })
    end
end

function perGlbTest (device, test_name, variants, extra)
    local targets = {}
    writeReadme(device, test_name, extra)
    for _, glb in device.glbs() do
        writeGlbVariants(device, test_name, variants, glb, targets, extra)
    end
    addToGroup(test_name, targets)
end

function perMacrocellTest(device, test_name, variants, extra)
    local targets = {}
    writeReadme(device, test_name, extra)
    for _, glb in device.glbs() do
        for _, mc in glb.mcs() do
            writeMcVariants(device, test_name, variants, mc, targets, extra)
        end
    end
    addToGroup(test_name, targets)
end

function perOutputTest(device, test_name, variants, extra)
    local targets = {}
    writeReadme(device, test_name, extra)
    for _, glb in device.glbs() do
        for _, mc in glb.mcs() do
            if mc.pin ~= nil then
                writeMcVariants(device, test_name, variants, mc, targets, extra)
            end
        end
    end
    addToGroup(test_name, targets)
end

function perInputTest(device, test_name, variants, extra)
    local targets = {}
    writeReadme(device, test_name, extra)
    for _, glb in device.glbs() do
        for _, mc in glb.mcs() do
            if mc.pin ~= nil then
                writeMcVariants(device, test_name, variants, mc, targets, extra)
            end
        end
    end
    if type(extra) ~= 'table' then
        extra = {
            readme = extra
        }
    end
    extra.test_name_suffix = (extra.test_name_suffix or '')..'_clk'
    for _, clk in device.clks() do
        writeVariants(device, test_name, variants, { 'input', clk.name }, clk.clk_index, targets, extra)
    end
    addToGroup(test_name, targets)
end

local dev = device.lc4032ze

perInputTest(dev, 'pull', { 'OFF', 'UP', 'DOWN', 'HOLD' }, [[
2 fuses per I/O allow configuration of pull up, pull down, bus-hold, or high-Z input conditioning.
]])
perInputTest(dev, 'input_threshold', { 'LVCMOS33', 'LVCMOS15' }, [[
When an input expects to see 2.5V or higher inputs, this fuse should be used to increase the threshold voltage for that input.

This probably also controls whether or not the 200mV input hysteresis should be applied (according to the datasheet it's active at 2.5V and 3.3V)
]])
perOutputTest(dev, 'od', { 'LVCMOS33', 'LVCMOS33_OD' }, [[
One fuse per output controls whether the output is open-drain or totem-pole.

Open-drain can also be emulated by outputing a constant low and using OE to enable or disable it, but that places a lot of limitation on how much logic can be done in the macrocell.
]])
perOutputTest(dev, 'slew', { 'SLOW', 'FAST' }, [[
One fuse per output controls the slew rate for that driver.

SLOW should generally be used for any long traces or inter-board connections.
FAST can be used for short traces where transmission line effects are unlikely.
]])

globalTest(dev, 'zerohold', { 'no', 'yes' }, [[
When this fuse is enabled, registered inputs have an extra delay added to bring `tHOLD` down to 0.

This also means the setup time is increased as well.

Registers whose data comes from product term logic are not affected by this fuse.

This fuse affects the entire chip.
]])

-- globalTest(dev, 'security', { 'on', 'off' }, 'buf_1in_1out', [[
-- Prevents reading flash?
-- ]])

perGlbTest(dev, 'bclk01', { 'passthru', 'invert_both', 'clk0_comp', 'clk1_comp' })
perGlbTest(dev, 'bclk23', { 'passthru', 'invert_both', 'clk2_comp', 'clk3_comp' })

perInputTest(dev, 'pgdf', { 'pg', 'pg_disabled' })

globalTest(dev, 'goe0_polarity', { 'active_high', 'active_low' })
globalTest(dev, 'goe1_polarity', { 'active_high', 'active_low' })

--I'm having trouble coming up with a way to force the fitter into inverting the shared PTOE polarity.  I tried setting up 2 terms in the PLA, where either of 2
--input signals being 0 will enable an output.  That way it can't satisfy it using a single PT alone, but it didn't seem to figure out that it was possible
--to fit using the PTOE inverter, and just failed the fit instead.
--
--One thing I haven't tried yet is setting up an active-high shared PTOE that's used for one thing, and then another one that's the same signal but active low.
--Maybe it will realize it can use the inverter instead of allocating the second global PTOE?  Or maybe I can occupy the second PTOE slot with a PG/BIE.
--
--Alternatively since there's only a few fuses, maybe I can identify them by elimination at the end and manually test with hardware until it does what I want.
-- globalTest(dev, 'goe23_polarity', { 'LL', 'LH', 'HL', 'HH' }, { 'shared_goe_ll', 'shared_goe_ll', 'shared_goe_hh', 'shared_goe_hh' })


perOutputTest(dev, 'oe_mux', function (mc)
    if mc.pin.type == 'IO' then return {
        'off',
        'on',
        'npt',
        'pt',
        'goe0',
        'goe1',
        --[['goe2', 'goe3']]
    } else return {
        'off',
        'on',
        'npt',
        'pt',
        --[['goe2', 'goe3']]
    } end
end, { diff_options = '--rows 92-94', readme = [[
TODO: fix extra fuses showing up for macrocells A0 and B15 (goe0/1 inputs)
TODO: figure out how to select goe2/3
]] })

perOutputTest(dev, 'orm', { 'self', 'o1', 'o2', 'o3', 'o4', 'o5', 'o6', 'o7' })

perMacrocellTest(dev, 'reset_init', { 'SET', 'RESET' })

perMacrocellTest(dev, 'ce_mux', { 'always', 'npt', 'pt', 'shared' }, { diff_options = '--rows 86-87'})


-- for target_glb in dev.glbs() do
--     local valid_input_types = { IO = true, CLK = true, ['IO/CLK'] = true, GOE = true, ['IO/GOE'] = true }
--     local variants = { 'x', 'y' }

--     local targets = {}
--     for _, pin in dev.pins() do
--         if valid_input_types[pin.type] then
--             writeVariants(dev, 'grp_pin', { 'x', 'y' }, {'glb'..target_glb, 'pin'..pin.number}, {target_glb, pin.number}, targets)
--         end
--     end
--     addToGroup('grp_pin/glb'..target_glb, targets)

--     targets = {}
--     for _, glb in dev.glbs() do
--         for mc in glb.mcs() do
--             writeVariants(dev, 'grp_fb', { 'x', 'y' }, {'glb'..target_glb, 'glb'..glb.index, 'mc'..mc}, {target_glb, glb.index, mc}, targets)
--         end
--     end
--     addToGroup('grp_fb/glb'..target_glb, targets)
-- end

local gi_list = { 0, 1, 34, 35 }

do
    local variants = { 'p', 'n' }
    local targets = {}
    for _, glb in dev.glbs() do
        for _, mc in glb.mcs() do
            for _, gi in ipairs({ 0, 1 }) do
                -- due to the shenanigans needed to prevent the fitter from stealing PTs from previous MCs, this only
                -- works for lower GIs that are easier to fill with a specific signal
                writeVariants(dev, 'pt0', variants, { 'glb'..mc.glb.index, 'mc'..mc.index, 'gi'..gi }, { mc.glb.index, mc.index, gi }, targets)
            end
        end
    end
    addToGroup('pt0', targets)
end

do
    local variants = { 'p', 'n' }
    local targets = {}
    for _, glb in dev.glbs() do
        for _, mc in glb.mcs() do
            for _, gi in ipairs(gi_list) do
                writeVariants(dev, 'pt1', variants, { 'glb'..mc.glb.index, 'mc'..mc.index, 'gi'..gi }, { mc.glb.index, mc.index, gi }, targets)
            end
        end
    end
    addToGroup('pt1', targets)
end

do
    local variants = { 'p', 'n' }
    local targets = {}
    for _, glb in dev.glbs() do
        for _, mc in glb.mcs() do
            for _, gi in ipairs(gi_list) do
                writeVariants(dev, 'pt2', variants, { 'glb'..mc.glb.index, 'mc'..mc.index, 'gi'..gi }, { mc.glb.index, mc.index, gi }, targets)
            end
        end
    end
    addToGroup('pt2', targets)
end

do
    local variants = { 'p', 'n' }
    local targets = {}
    for _, glb in dev.glbs() do
        for _, mc in glb.mcs() do
            for _, gi in ipairs(gi_list) do
                writeVariants(dev, 'pt3', variants, { 'glb'..mc.glb.index, 'mc'..mc.index, 'gi'..gi }, { mc.glb.index, mc.index, gi }, targets)
            end
        end
    end
    addToGroup('pt3', targets)
end


for group, targets in spairs(group_targets) do
    write("build ", group, ": phony")
    for target in spairs(targets) do
        write(" ", target)
    end
    nl()
end

write("default")
for target in spairs(default_targets) do
    write(" ", target)
end
nl()
