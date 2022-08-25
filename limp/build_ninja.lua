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

perOutputTest(dev, 'orm', { 'self', 'o1', 'o2', 'o3', 'o4', 'o5', 'o6', 'o7' })

perMacrocellTest(dev, 'reset_init', { 'SET', 'RESET' })

perMacrocellTest(dev, 'ce_mux', { 'always', 'npt', 'pt', 'shared' }, { diff_options = '--include 72:0-99:171'}) --86-87'})


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

perGlbTest(dev, 'grp\\gi0',  { 'pin 20', 'pin 27', 'fb B6',  'pin 44', 'fb B15', 'fb A5'  }, { diff_options = '--include 0:0-1:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi1',  { 'fb A3',  'fb A11', 'fb A15', 'pin 4',  'pin 14', 'pin 34' }, { diff_options = '--include 2:0-3:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi2',  { 'fb A2',  'fb A9',  'fb A13', 'fb B12', 'pin 19', 'pin 45' }, { diff_options = '--include 4:0-5:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi3',  { 'fb A12', 'pin 28', 'pin 31', 'pin 14', 'pin 44', 'fb B12' }, { diff_options = '--include 6:0-7:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi4',  { 'fb A7',  'fb B7',  'pin 24', 'pin 32', 'pin 44', 'fb A15' }, { diff_options = '--include 8:0-9:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi5',  { 'fb A4',  'fb A14', 'fb B3',  'pin 18', 'pin 38', 'pin 4'  }, { diff_options = '--include 10:0-11:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi6',  { 'fb B10', 'pin 8',  'pin 22', 'pin 40', 'pin 4',  'fb B7'  }, { diff_options = '--include 12:0-13:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi7',  { 'fb A6',  'fb B1',  'fb B4',  'fb B13', 'pin 10', 'pin 45' }, { diff_options = '--include 14:0-15:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi8',  { 'fb A8',  'fb B0',  'pin 33', 'fb A3',  'pin 20', 'pin 45' }, { diff_options = '--include 16:0-17:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi9',  { 'fb B11', 'pin 9',  'pin 17', 'pin 47', 'fb B15', 'fb A9'  }, { diff_options = '--include 18:0-19:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi10', { 'pin 23', 'pin 26', 'pin 43', 'fb A2',  'fb B3',  'fb B11' }, { diff_options = '--include 20:0-21:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi11', { 'pin 3',  'pin 21', 'fb A11', 'pin 47', 'fb A5',  'pin 28' }, { diff_options = '--include 22:0-23:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi12', { 'pin 16', 'pin 27', 'fb A3',  'fb B7',  'pin 31', 'pin 47' }, { diff_options = '--include 24:0-25:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi13', { 'fb A10', 'pin 2',  'pin 39', 'pin 14', 'fb A5',  'pin 9'  }, { diff_options = '--include 26:0-27:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi14', { 'fb A0',  'fb B9',  'pin 10', 'fb A8',  'pin 43', 'pin 8'  }, { diff_options = '--include 28:0-29:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi15', { 'fb B5',  'fb B8',  'fb B14', 'pin 19', 'pin 39', 'fb B0'  }, { diff_options = '--include 30:0-31:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi16', { 'fb B2',  'pin 34', 'pin 18', 'fb B15', 'fb A7',  'fb A10' }, { diff_options = '--include 32:0-33:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi17', { 'fb A1',  'pin 15', 'pin 27', 'fb A11', 'pin 40', 'fb B9'  }, { diff_options = '--include 34:0-35:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi18', { 'fb A13', 'fb A6',  'pin 17', 'fb B5',  'pin 38', 'pin 3'  }, { diff_options = '--include 36:0-37:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi19', { 'pin 7',  'pin 41', 'fb A4',  'fb A8',  'pin 19', 'pin 2'  }, { diff_options = '--include 38:0-39:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi20', { 'pin 46', 'pin 28', 'fb A0',  'fb B5',  'pin 18', 'fb B10' }, { diff_options = '--include 40:0-41:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi21', { 'pin 42', 'pin 22', 'pin 7',  'fb B14', 'fb B3',  'fb B9'  }, { diff_options = '--include 42:0-43:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi22', { 'fb A13', 'pin 32', 'pin 41', 'pin 10', 'fb A12', 'fb B8'  }, { diff_options = '--include 44:0-45:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi23', { 'pin 48', 'fb B11', 'pin 2',  'fb B6',  'pin 16', 'fb B0'  }, { diff_options = '--include 46:0-47:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi24', { 'fb B4',  'pin 40', 'fb A4',  'pin 3',  'pin 24', 'fb B2'  }, { diff_options = '--include 48:0-49:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi25', { 'pin 21', 'fb A6',  'fb A1',  'pin 42', 'fb B6',  'fb B2'  }, { diff_options = '--include 50:0-51:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi26', { 'pin 26', 'pin 42', 'pin 17', 'fb A7',  'fb A12', 'fb A0'  }, { diff_options = '--include 52:0-53:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi27', { 'fb B1',  'pin 31', 'pin 20', 'pin 38', 'fb A10', 'fb B11' }, { diff_options = '--include 54:0-55:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi28', { 'fb A14', 'pin 33', 'pin 46', 'pin 23', 'fb B12', 'fb B7'  }, { diff_options = '--include 56:0-57:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi29', { 'fb B10', 'pin 48', 'fb B4',  'pin 7',  'pin 23', 'fb A1'  }, { diff_options = '--include 58:0-59:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi30', { 'pin 9',  'fb A4',  'pin 32', 'pin 22', 'fb B5',  'pin 48' }, { diff_options = '--include 60:0-61:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi31', { 'fb A7',  'pin 15', 'fb A2',  'pin 39', 'fb B1',  'fb B6'  }, { diff_options = '--include 62:0-63:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi32', { 'pin 34', 'pin 24', 'fb B14', 'pin 26', 'fb B12', 'fb A8'  }, { diff_options = '--include 64:0-65:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi33', { 'fb B13', 'pin 21', 'fb A10', 'pin 41', 'fb B10', 'fb A14' }, { diff_options = '--include 66:0-67:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi34', { 'fb A9',  'fb A3',  'pin 46', 'pin 8',  'pin 15', 'fb B13' }, { diff_options = '--include 68:0-69:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })
perGlbTest(dev, 'grp\\gi35', { 'pin 43', 'fb B8',  'pin 33', 'fb A15', 'fb A9',  'pin 16' }, { diff_options = '--include 70:0-71:171 --exclude 0:3-71:85 --exclude 0:89-71:171' })

perMacrocellTest(dev, 'ff_type', { 'D', 'T', 'latch', 'none' }, { diff_options = '--include 79:0-80:171' })

perMacrocellTest(dev, 'pt2_reset', { 'none', 'pt' }, { diff_options = '--include 82:0-82:171' })
perMacrocellTest(dev, 'pt3_reset', { 'none', 'pt', 'shared' }, { diff_options = '--include 83:0-83:171' })

perMacrocellTest(dev, 'clk_mux', { 'bclk0', 'bclk1', 'bclk2', 'bclk3', 'pt', 'npt', 'shared_pt', 'gnd' }, { diff_options = '--include 76:0-81:171'})

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

    rows 74, 75: Cluster allocator steering
         0   0 : Route this cluster to the allocator for MC-2
         0   1 : Route this cluster to the allocator for MC+1
         1   0 : Route this cluster to this allocator
         1   1 : Route this cluster to the allocator for MC-1

]]})

perOutputTest(dev, 'inreg', { 'normal', 'inreg' }, { diff_options = '--include 85:0-85:171'})

perMacrocellTest(dev, 'xor', { 'normal', 'invert', 'xor_pt0', 'xor_npt0' }, { diff_options = '--include 72:0-99:171'})

globalTest(dev, 'osctimer', { 'none', 'oscout', 'timerout', 'timerout_timerres', 'oscout_dynoscdis' }, { diff_options = '--include 75:165-99:171 --exclude 85:0-86:171 --exclude 95:0-95:171 --exclude 87:168-90:168 --exclude 87:171-91:171'})

globalTest(dev, 'osctimer_div', { '128', '1024', '1048576' }, { diff_options = '--include 75:165-99:171 --exclude 85:0-86:171 --exclude 95:0-95:171 --exclude 87:168-90:168 --exclude 87:171-91:171'})

for group, targets in spairs(group_targets) do
    write("build ", group, ": phony")
    for target in spairs(targets) do
        write(" ", target)
    end
    nl()
end
nl()

write("build check: phony")
for _, jed in ipairs(jed_jobs) do
    write(" ", jed)
end
nl()
nl()

write("default")
for target in spairs(default_targets) do
    write(" ", target)
end
nl()
