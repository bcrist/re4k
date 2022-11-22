local device = ...

local function ZE_only (device) 
    return nil ~= device:find('ZE_', 1, true)
end

local function non_ZE_only (device)
    return nil == device:find('ZE_', 1, true)
end

local jobs = {
    grp = { device_map = {
        -- For some packages, not all inputs on the die are attached to pins, so it's
        -- impossible to exercise every fuse in the GRP muxes.  Instead we just do a
        -- package that does expose all the signals, and then map that to the pins on other
        -- packages that use the same die.
        LC4032x_TQFP44 = "LC4032x_TQFP48",
        LC4032ZC_TQFP48 = "LC4032x_TQFP48",
        LC4032ZC_csBGA56 = "LC4032x_TQFP48",
        LC4032ZE_TQFP48 = "LC4032x_TQFP48",
        LC4032ZE_csBGA64 = "LC4032x_TQFP48",
        LC4064x_TQFP44 = "LC4064x_TQFP48",
        LC4064ZC_TQFP48 = "LC4064x_TQFP100",
        LC4064ZC_csBGA56 = "LC4064x_TQFP100",
        LC4064ZC_TQFP100 = "LC4064x_TQFP100",
        LC4064ZC_csBGA132 = "LC4064x_TQFP100",
        LC4064ZE_TQFP48 = "LC4064x_TQFP100",
        LC4064ZE_csBGA64 = "LC4064x_TQFP100",
        LC4064ZE_ucBGA64 = "LC4064x_TQFP100",
        LC4064ZE_TQFP100 = "LC4064x_TQFP100",
        LC4064ZE_csBGA144 = "LC4064x_TQFP100",
        LC4128x_TQFP100 = "LC4128V_TQFP144",
        LC4128x_TQFP128 = "LC4128V_TQFP144",
        LC4128ZC_TQFP100 = "LC4128V_TQFP144",
        LC4128ZC_csBGA132 = "LC4128V_TQFP144",
        LC4128ZE_TQFP100 = "LC4128V_TQFP144",
        LC4128ZE_TQFP144 = "LC4128V_TQFP144",
        LC4128ZE_ucBGA144 = "LC4128V_TQFP144",
        LC4128ZE_csBGA144 = "LC4128V_TQFP144",
    }},
    bclk_polarity = { device_map = {
        -- These devices only have 2 dedicated clock inputs, 0 and 2, but use the same
        -- die as the TQFP48 version, so the clock polarity should generally be set up for
        -- complementary versions of both clocks.
        LC4032x_TQFP44 = "LC4032x_TQFP48",
        LC4064x_TQFP44 = "LC4064x_TQFP48",
    }},
    shared_pt_clk_polarity = {},
    shared_pt_async_polarity = { 'shared_pt_clk_polarity' },
    output_routing_mode = { device_predicate = non_ZE_only },
    zerohold         = {},
    slew             = {},
    threshold        = {},
    pull             = {},
    drive            = {},
    oe_mux           = {},
    orm              = {},
    powerup_state    = {},
    ce_mux           = {},
    reg_type         = {},
    pt2_reset        = {},
    pt3_reset        = {},
    pt4_oe           = { 'oe_mux' },
    clk_mux          = {},
    input_reg        = {},
    invert           = {},
    pt0_xor          = {},
    pterms           = { 'grp' },
    cluster_steering = { 'invert', 'orm' },
    wide_steering    = { 'cluster_steering' },
    goes             = { 'shared_pt_clk_polarity' },
    power_guard      = { device_predicate = ZE_only },
    -- osctimer         = { device_predicate = ZE_only },
}

writeln('dev = ', fs.compose_path(device:sub(1, 6), device), nl)

for job, config in spairs(jobs) do
    local cmd = job
    local deps = config
    local dep_dev = '$dev'
    if config.device_map then
        local other_dev = config.device_map[device]
        if other_dev then
            cmd = 'convert-' .. job
            deps = { job }
            dep_dev = fs.compose_path(other_dev:sub(1, 6), other_dev)
        elseif other_dev == false then
            cmd = nil
        end
    end
    if config.device_predicate then
        if not config.device_predicate(device) then
            cmd = nil
        end
    end
    if cmd then
        writeln('rule ', cmd)
        writeln('    command = zig-out/bin/', cmd, '.exe $out $in')
        write('build $dev/', job, '.sx: ', cmd)
        for _, dep in ipairs(deps) do
            write(' ', fs.compose_path(dep_dev, dep), '.sx')
        end
        nl()
        nl()
    end
end

write('build build-', device, ': phony ')
for job, config in spairs(jobs) do
    if config.device_map then
        local other_dev = config.device_map[device]
        if other_dev == false then
            job = nil
        end
    end
    if config.device_predicate then
        if not config.device_predicate(device) then
            job = nil
        end
    end
    if job then
        write(' $dev/', job, '.sx')
    end
end
nl()
