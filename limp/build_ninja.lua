include 'lc4032ze'

local default_targets = {}
local group_targets = {}
local jed_jobs = {}

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

    local write_lci = 'write_lci_'..(test_name:gsub('[/\\]', '_'))
    if test_name_suffix ~= nil then
        write_lci = write_lci..test_name_suffix
    end

    fs.ensure_dir_exists(base_path)

    for v, variant in ipairs(variants) do
        variant = variant:gsub(' ', '_')
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

    local checkname = fs.compose_path(base_path, "check")
    jed_jobs[#jed_jobs+1] = checkname
    write("build ", checkname, ": check")
    for _, variant in ipairs(variants) do
        variant = variant:gsub(' ', '_')
        write(" ", fs.compose_path(base_path, variant..".jed"))
    end
    nl()

    local csv
    if targets == nil then
        csv = fs.compose_path(base_path, "fuses.csv")
    else
        csv = base_path.."_fuses.csv"
        targets[csv] = true
    end
    write("build ", csv, ": diff")
    for _, variant in ipairs(variants) do
        variant = variant:gsub(' ', '_')
        write(" ", fs.compose_path(base_path, variant..".jed"))
    end
    nl()
    if diff_options ~= nil then
        writeln("    diff_options = ", diff_options)
    end
    nl()

    return csv
end

local mc_columns = {
    mc0 = 7, mc1 = 8,
    mc2 = 17, mc3 = 18,
    mc4 = 27, mc5 = 28,
    mc6 = 37, mc7 = 38,
    mc8 = 47, mc9 = 48,
    mc10 = 57, mc11 = 58,
    mc12 = 67, mc13 = 68,
    mc14 = 77, mc15 = 78,
}

local function writeMcVariants(device, test_name, variants, mc, targets, extra)
    if type(variants) == 'function' then
        variants = variants(mc)
    end
    if variants ~= nil then
        if extra and extra.mc_range then
            local col = 86 * (device.num_glbs - mc.glb.index - 1) + mc_columns['mc'..mc.index]
            extra = {
                readme = extra.readme,
                diff_options = extra.diff_options or ''
            }
            extra.diff_options = extra.diff_options .. ' --include 72:'..col..'-99:'..col
        end
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
    local parent = group:gsub('[/\\][^/\\]+$', '')
    if parent ~= group then
        addToGroup(parent, {[group] = true})
    else
        default_targets[group] = true
    end
end

function globalTest (device, test_name, variants, extra)
    writeReadme(device, test_name, extra)
    if type(variants) == 'function' then
        variants = variants()
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

perGlbTest(dev, 'bclk01', { 'passthru', 'invert_both', 'clk0_comp', 'clk1_comp' })
perGlbTest(dev, 'bclk23', { 'passthru', 'invert_both', 'clk2_comp', 'clk3_comp' })

perInputTest(dev, 'pgdf', { 'pg', 'pg_disabled' })

globalTest(dev, 'goe0_polarity', { 'active_high', 'active_low' })
globalTest(dev, 'goe1_polarity', { 'active_high', 'active_low' })

globalTest(dev, 'goe23_polarity', { 'goe2low_goe3low', 'goe2low_goe3high', 'goe2high_goe3low', 'goe2high goe3high' }, [[

|      |Column 85                                   |Column 171                                  |
|Row 73|When cleared, route GLB 1's PTOE/BIE to GOE2|When cleared, route GLB 0's PTOE/BIE to GOE2|
|Row 74|When cleared, route GLB 1's PTOE/BIE to GOE3|When cleared, route GLB 0's PTOE/BIE to GOE3|

|      |Column 171                      |
|Row 88|When cleared, GOE2 is active low|
|Row 89|When cleared, GOE3 is active low|
]])


perOutputTest(dev, 'oe_mux', function (mc)
    local variants = { 'off', 'on', 'npt', 'pt' }
    if mc.pin.type == 'IO' then
        variants[#variants+1] = 'goe0'
        variants[#variants+1] = 'goe1'
    end
    variants[#variants+1] = 'goe2'
    variants[#variants+1] = 'goe3'
    return variants
end, { diff_options = '--exclude 0:0-91:171', mc_range = true })

globalTest(dev, 'ptoe_orm', { 'test', 'control' }, { diff_options = '--include 84:0-84:171 --include 92:0-94:171', readme = [[
Row 84 indicates that pt4 is used as a PTOE and should be redirected from the cluster sum.

At first that may seem redundant, since rows 92-94 (OE mux) normally also encode that, and
for other PT routing (PTCE, PTCLK, etc.) the PT is automatically removed from the logic sum
when the mux is set to a value that requires it.  But one must remember that the OE mux is
actually associated with the I/O cell, not the macrocell, and the PTOE input to the OE mux
goes through the ORM and may be from a different MC/logic allocator.  So if row 84 didn't
exist, there would have to be a third, "reverse" channel in the ORM to propagate knowledge
of whether PTOE is used back to the original logic allocator.

This is just a quick test to validate that rows 92-94 associate to an I/O cell, while 84
stays with the MC/logic alloc, evem when the ORM is in use.
]]})


perGlbTest(dev, 'shared_ptclk_polarity', { 'normal', 'invert' })

globalTest(dev, 'clusters', function()
    local variants = {}
    for i = 1, 75 do
        variants[#variants+1] = '' .. i
    end
    return variants
end, { diff_options = '--include 72:0-99:171',
readme = [[
    row 88: SuperWIDE steering
        1 : Route this cluster allocator's output to this MC
        0 : Route this cluster allocator's output to the cluster allocator for MC+4, wrapping around if above 15

]]})

globalTest(dev, 'osctimer', { 'none', 'oscout', 'timerout', 'timerout_timerres', 'oscout_dynoscdis' }, { diff_options = '--include 75:165-99:171 --exclude 85:0-86:171 --exclude 95:0-95:171 --exclude 87:168-90:168 --exclude 87:171-91:171'})

globalTest(dev, 'osctimer_div', { '128', '1024', '1048576' }, { diff_options = '--include 75:165-99:171 --exclude 85:0-86:171 --exclude 95:0-95:171 --exclude 87:168-90:168 --exclude 87:171-91:171'})
