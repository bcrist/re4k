include 'lci_helper'
include 'lc4032ze'

function write_tt4_32out (variant)
    local pla = make_pla()
    for i = 0, 31 do
        local out = 'out'..i
        pla:pin(out)
        pla:pt('in', out)
    end
    pla:write(variant..'.tt4')
end

function write_lci_32out (device, special_glb, special_mc)
    write_lci_common { device = device }

    writeln '\n[Location Assignments]'
    assign_pin_location('in', device.clk(0))

    local n = 0
    local special_signal = ''
    for _, glb in device.glbs() do
        for _, mc in glb.mcs() do
        if n < 32 then
            local signal = 'out' .. n
            if glb.index == special_glb and mc.index == special_mc then
                special_signal = signal
            end
            assign_pin_location(signal, mc)
            n = n + 1
        end
        end
    end
    nl()

    return special_signal
end

function write_tt4_31in_1out (variant)
    local pla = make_pla()
    pla:pin('out')
    local inputs = {}
    for i = 0, 30 do
        inputs[#inputs+1] = 'in'..i
    end
    pla:pt(inputs, 'out')
    pla:write(variant..'.tt4')
end

function write_lci_31in_1out (device, special_glb, special_mc, out_glb, out_mc)
    if out_glb == nil then
        out_mc = 0
        if special_glb == 0 then
            out_glb = 1
        else
            out_glb = 0
        end
    end

    -- uses and_31in_1out.pla
    write_lci_common { device = device }

    writeln '\n[Location Assignments]'
    local n = 0
    local special_signal = ''
    for _, glb in device.glbs() do
        for _, mc in glb.mcs() do
            if n < 31 then
                local signal = 'in' .. n
                if glb.index == out_glb and mc.index == out_mc then
                    signal = 'out'
                else
                    n = n + 1
                end
                if glb.index == special_glb and mc.index == special_mc then
                    special_signal = signal
                end
                assign_pin_location(signal, mc)
            end
        end
    end
    nl()

    return special_signal
end

function write_lci_input_threshold (device, special_glb, special_mc, variant)
    write_tt4_31in_1out(variant)
    local special_signal = write_lci_31in_1out(device, special_glb, special_mc)
    writeln '\n[IO Types]'
    write_io_type_constraint { signal = special_signal, iostd = variant }
end

function write_lci_input_threshold_clk (device, special_clk, variant)
    write_tt4_31in_1out(variant)
    write_lci_common { device = device }

    writeln '\n[Location Assignments]'
    assign_pin_location('in0', device.clk(special_clk))
    assign_pin_location('out', device.glb(1).mc(15))
    local n = 1
    for _, glb in device.glbs() do
        for _, mc in glb.mcs() do
            if n < 31 then
                local signal = 'in' .. n
                n = n + 1
                assign_pin_location(signal, mc)
            end
        end
    end
    nl()

    writeln '\n[IO Types]'
    write_io_type_constraint { signal = 'in0', iostd = variant }
end

function write_lci_od (device, special_glb, special_mc, variant)
    write_tt4_32out(variant)
    local special_signal = write_lci_32out(device, special_glb, special_mc)
    writeln '\n[IO Types]'
    write_io_type_constraint { signal = special_signal, iostd = variant }
end

function write_lci_pull (device, special_glb, special_mc, variant)
    write_tt4_31in_1out(variant)
    local special_signal = write_lci_31in_1out(device, special_glb, special_mc)
    writeln '\n[Pullup]'
    writeln 'Default=DOWN;'
    writeln(variant, '=', special_signal, ';')
end

function write_lci_pull_clk (device, special_clk, variant)
    write_tt4_31in_1out(variant)
    write_lci_common { device = device }

    writeln '\n[Location Assignments]'
    assign_pin_location('in0', device.clk(special_clk))
    assign_pin_location('out', device.glb(1).mc(15))
    local n = 1
    for _, glb in device.glbs() do
        for _, mc in glb.mcs() do
            if n < 31 then
                local signal = 'in' .. n
                n = n + 1
                assign_pin_location(signal, mc)
            end
        end
    end
    nl()

    writeln '\n[Pullup]'
    writeln 'Default=DOWN;'
    writeln(variant, '=in0;')
end

function write_lci_slew (device, special_glb, special_mc, variant)
    write_tt4_32out(variant)
    local special_signal = write_lci_32out(device, special_glb, special_mc)
    writeln '\n[Slewrate]'
    writeln 'Default=FAST;'
    writeln(variant, '=', special_signal, ';')
end

function write_lci_zerohold (device, variant)
    local pla = make_pla()
    pla:output('out')
    pla:pt('in', 'out')
    pla:write(variant..'.tt4')

    write_lci_common { device = device }
    writeln('Zero_hold_time=', variant, ';')
end

function write_lci_security (device, on_or_off)
    local pla = make_pla()
    pla:output('out')
    pla:pt('in', 'out')
    pla:write(variant..'.tt4')

    write_lci_common { device = device }
    writeln('Security=', on_or_off, ';')
end

function write_lci_bclk (device, special_glb, clk0, clk1, variant)
    local pla = make_pla()
    pla:pt('in0', 'reg0.D')
    pla:pt('in1', 'reg1.D')
    pla:pt('clk0', 'co0')
    pla:pt('clk1', 'co1')
    if variant == 'passthru' then
        pla:pt('clk0', 'reg0.C')
        pla:pt('clk1', 'reg1.C')
    elseif variant == 'invert_both' then
        pla:pt('~clk0', 'reg1.C')
        pla:pt('~clk1', 'reg0.C')
    elseif variant == 'clk0_comp' or variant == 'clk2_comp' then
        pla:pt('clk0', 'reg0.C')
        pla:pt('~clk0', 'reg1.C')
    else
        pla:pt('~clk1', 'reg0.C')
        pla:pt('clk1', 'reg1.C')
    end
    pla:write(variant..'.tt4')

    write_lci_common { device = device }
    writeln '\n[Location Assignments]'
    assign_pin_location('clk0', device.clk(clk0))
    assign_pin_location('clk1', device.clk(clk1))
    assign_pin_location('in0', device.glb(special_glb).mc(0))
    assign_pin_location('in1', device.glb(special_glb).mc(1))
    assign_node_location('co0', device.glb(special_glb).mc(14))
    assign_node_location('co1', device.glb(special_glb).mc(15))
    writeln '\n[Input Registers]'
    writeln 'Default=INREG;'
end

function write_lci_bclk01 (device, special_glb, variant)
    write_lci_bclk(device, special_glb, 0, 1, variant)
end
function write_lci_bclk23 (device, special_glb, variant)
    write_lci_bclk(device, special_glb, 2, 3, variant)
end

function write_tt4_pgdf (variant)
    local pla = make_pla()
    pla:pin('out', 'in0_PG_D', 'in1_PG_D')
    pla:node('in0_PG_Q')
    pla:ext("#$ EXTERNAL PG 3 D'i' E'i' Q'o'")
    pla:ext("#$ INSTANCE I0 PG 3 in0_PG_D PG_E in0_PG_Q")
    pla:pt('in_PG_E', 'PG_E')
    if variant == 'pg' then
        pla:node('in1_PG_Q')
        pla:ext("#$ INSTANCE I1 PG 3 in1_PG_D PG_E in1_PG_Q")
        pla:pt('in1_PG_Q', 'out')
    else
        pla:pt('in1_PG_D', 'out')
    end
    pla:write(variant..'.tt4')
end

function write_lci_pgdf (device, special_glb, special_mc, variant)
    write_tt4_pgdf(variant)
    write_lci_common { device = device }
    writeln '\n[Location Assignments]'
    assign_pin_location('in_PG_E', device.clk(0))
    assign_pin_location('in1_PG_D', device.glb(special_glb).mc(special_mc))
    assign_pin_location('in0_PG_D', device.glb(special_glb).mc((special_mc + 1) % 16))
    assign_pin_location('out', device.glb(special_glb).mc((special_mc + 2) % 16))
end

function write_lci_pgdf_clk (device, special_clk, variant)
    write_tt4_pgdf(variant)
    write_lci_common { device = device }
    local clk = device.clk(special_clk)
    writeln '\n[Location Assignments]'
    assign_pin_location('in1_PG_D', clk)
    assign_pin_location('in_PG_E', device.glb(clk.glb.index or 0).mc(0))
    assign_pin_location('in0_PG_D', device.glb(clk.glb.index or 0).mc(1))
    assign_pin_location('out', device.glb(clk.glb.index or 0).mc(2))
end

function write_tt4_goe01_polarity (variant)
    local pla = make_pla()
    pla:pin('out')
    pla:pt('in', 'out')
    if variant == 'active_low' then
        pla:pt('~oe', 'out.OE')
    else
        pla:pt('oe', 'out.OE')
    end
    pla:write(variant..'.tt4')
end

function write_lci_goe0_polarity (device, variant)
    write_tt4_goe01_polarity(variant)
    write_lci_common { device = device }
    writeln '\n[Location Assignments]'
    assign_pin_location('oe', device.goe(0))
    assign_pin_location('in', device.glb(0).mc(4))
    assign_pin_location('out', device.glb(0).mc(5))
end

function write_lci_goe1_polarity (device, variant)
    write_tt4_goe01_polarity(variant)
    write_lci_common { device = device }
    writeln '\n[Location Assignments]'
    assign_pin_location('oe', device.goe(1))
    assign_pin_location('in', device.glb(0).mc(4))
    assign_pin_location('out', device.glb(0).mc(5))
end

function write_lci_oe_mux (device, special_glb, special_mc, variant)
    local pla = make_pla()

    write_lci_common { device = device }
    writeln '\n[Location Assignments]'

    local glb = device.glb(special_glb)
    local scratch_glb = device.glb((special_glb + 1) % device.num_glbs)

    local scratch_base
    if special_mc < 8 then
        scratch_base = 8
    else
        scratch_base = 1
    end

    pla:pin('out')
    pla:pt('in', 'out')
    assign_pin_location('out', glb.mc(special_mc))

    if variant == 'goe0' then
        pla:pt('goe0', 'out.OE')
        assign_pin_location('goe0', device.goe(0))
        
    elseif variant == 'goe1' then
        pla:pt('goe1', 'out.OE')
        assign_pin_location('goe1', device.goe(1))

    elseif variant == 'goe2' then
        pla:pt('goe2', 'out.OE')
        assign_pin_location('goe2', scratch_glb.mc(1).pin)
        assign_pin_location('goe3', scratch_glb.mc(2).pin)

    elseif variant == 'goe3' then
        pla:pt('goe3', 'out.OE')

        pla:pin('dum1')
        pla:pt({}, {'dum1','dum2'})
        pla:pt('goe2', 'dum1.OE')
        pla:pt('goe2', 'dum2.OE')
        assign_pin_location('dum1', glb.mc(scratch_base + 1).pin)
        assign_pin_location('dum2', glb.mc(scratch_base + 2).pin)
        assign_pin_location('goe2', scratch_glb.mc(1).pin)
        assign_pin_location('goe3', scratch_glb.mc(2).pin)

    elseif variant == 'pt' or variant == 'npt' then
        if variant == 'npt' then
            pla:pt({'in0', 'in1'}, 'out.OE-')
        else
            pla:pt({'in0', 'in1'}, 'out.OE')
        end

        for mc, mci in glb.mcs() do
            if mc ~= special_mc then
                local sig = 'dum'..mc
                pla:pin(sig)
                pla:pt({}, sig)
                if mc < 8 then
                    pla:pt('goe2', sig..'.OE')
                else
                    pla:pt('goe3', sig..'.OE')
                end
                assign_pin_location(sig, mci)
            end
        end
        assign_pin_location('goe2', scratch_glb.mc(1).pin)
        assign_pin_location('goe3', scratch_glb.mc(2).pin)

    elseif variant == 'on' then
        -- nothing

    elseif variant == 'off' then
        pla:output('out.OE')
    
    end

    pla:write(variant..'.tt4')
end

function write_lci_orm (device, special_glb, special_mc, variant)
    local pla = make_pla()
    pla:pin('out0')
    local outputs = {}
    for i = 0, 15 do
        outputs[#outputs+1] = 'out'..i
    end
    pla:pt('in', outputs)
    pla:write(variant..'.tt4')

    write_lci_common { device = device }

    writeln '\n[Location Assignments]'
    assign_pin_location('in', device.clk(0))

    local glb = device.glb(special_glb)

    local mc = special_mc
    if variant ~= 'self' then
        mc = (mc + variant:sub(2)) % 16
    end
    
    local n = 1
    for i = 0, 15 do
        if i ~= mc then
            assign_node_location('out'..n, glb.mc(i))
            n = n + 1
        end
    end

    assign_pin_location('out0', glb.mc(mc), glb.mc(special_mc).pin)
end

function write_lci_reset_init (device, special_glb, special_mc, variant)
    local pla = make_pla()
    pla:pt('in', 'out.D')
    pla:pt('clk', 'out.C')
    pla:write(variant..'.tt4')

    write_lci_common { device = device }

    writeln '\n[Location Assignments]'
    assign_node_location('out', device.glb(special_glb).mc(special_mc))

    writeln '\n[Register Powerup]'
    writeln(variant, ' = out;')
end

function write_lci_ce_mux (device, special_glb, special_mc, variant)
    local pla = make_pla()
    pla:pt({'ce0','ce1'}, 'ceo')
    pla:pt('in', 'out.D')
    pla:pt('in2', 'out2.D')
    pla:pt('in3', 'out3.D')
    pla:pt('in4', 'out4.D')
    pla:pt('clk', { 'out.C', 'out2.C', 'out3.C', 'out4.C' })
    pla:pt('gce', { 'out2.CE', 'out3.CE', 'out4.CE' })
    local sw = {
        always = function()  end,
        npt    = function() pla:pt({ 'ce0', 'ce1' }, 'out.CE-') end,
        pt     = function() pla:pt({ 'ce0', 'ce1' }, 'out.CE') end,
        shared = function() pla:pt('gce', 'out.CE') end,
    }
    sw[variant]()
    pla:write(variant..'.tt4')

    write_lci_common { device = device }

    local scratch_base
    if special_mc < 8 then
        scratch_base = 8
    else
        scratch_base = 1
    end

    writeln '\n[Location Assignments]'
    assign_node_location('out', device.glb(special_glb).mc(special_mc))
    assign_node_location('ceo', device.glb(special_glb))
    assign_node_location('out2', device.glb(special_glb).mc(scratch_base))
    assign_node_location('out3', device.glb(special_glb).mc(scratch_base+1))
    assign_node_location('out4', device.glb(special_glb).mc(scratch_base+2))
end

local function parse_signal_list (device, str)
    str = str:gsub('[ _]', ''):gsub('fbA', 'glb0_mc'):gsub('fbB', 'glb1_mc')

    local signals = {}
    local signals_list = {}
    for signal in str:gmatch('[^,\r\n]+') do
        if signals[signal] == nil then
            
            local pin_number = signal:match('pin(%d+)')
            if pin_number then
                signals[signal] = device.pin(pin_number + 0)
            else
                local glb, mc = signal:match('glb(%d+)_mc(%d+)')
                signals[signal] = device.glb(glb).mc(mc)
            end
            signals_list[#signals_list+1] = signal
        end
    end

    return signals, signals_list
end

function write_lci_pt_test3 (device)
    local all_signals
    local all_signals_list
    all_signals, all_signals_list = parse_signal_list(device, [[
        fb A5, fb B6, fb B15, pin 20, pin 27, pin 44
        fb A3, fb A11, fb A15, pin 4, pin 14, pin 34
        fb A2, fb A9, fb A13, fb B12, pin 19, pin 45
        fb A12, pin 28, pin 31, pin 14, pin 44
        fb A7, fb B7, pin 24, pin 32, pin 44, fb A15
        fb A4, fb A14, fb B3, pin 18, pin 38, pin 4
        fb B10, pin 8, pin 22, pin 40, pin 4, fb B7
        fb A6, fb B1, fb B4, fb B13, pin 10, pin 45
        fb A8, fb B0, pin 33, fb A3, pin 20, pin 45
        fb B11, pin 9, pin 17, pin 47, fb B15, fb A9
        pin 23, pin 26, pin 43, fb A2, fb B3, fb B11
        pin 3, pin 21, fb A11, pin 47, fb A5
        pin 16, pin 27, fb A3, fb B7, pin 31
        fb A10, pin 2, pin 39, pin 14, fb A5, pin 9
        fb A0, fb B9, pin 10, fb B0, fb A8
        fb B5, fb B8, fb B14, pin 19, fb B15, pin 39
        fb B2, pin 34, pin 18, fb B15, fb A7
        fb A1, pin 15, pin 27, fb A11, pin 40
        fb A13, fb A6, pin 17, fb B5, pin 38, pin 3
        pin 7, pin 41, fb A4, fb A8, pin 19, pin 2
        pin 46, pin 28, fb A0, fb B5, pin 18, fb B10
        pin 42, pin 22, pin 7, fb B14
        fb A13, pin 32, pin 41, pin 10
        pin 48, fb B11, pin 2, fb B6
        fb B4, pin 40, fb A4, pin 3, pin 24
        pin 21, fb A6, fb A1, pin 42
        pin 26, pin 42, pin 17, fb A7, fb A12
        fb B1, pin 31, pin 20, pin 38
        fb A14, pin 33, pin 46
        fb B10, pin 48, fb B4, pin 7, pin 23, fb A1
        pin 9, fb A4, pin 32, pin 22
        fb A7, pin 15, fb A2, pin 39, fb B1
        pin 34, pin 24, fb B14, pin 26, fb B12
        fb B13, pin 21, fb A10, pin 41
        fb A9, fb A3, pin 46, pin 8
        pin 43, fb B8, pin 33
]])

    local signals = {}
    local signal_list = {}
    local pick_signal = function (signal)
        if signals[signal] then return end
        for i, sig in ipairs(signal_list) do
            if sig == signal then
                table.remove(all_signals_list, i)
                break
            end
        end
        signal_list[#signal_list+1] = signal
        signals[signal] = all_signals[signal]
    end

    local signal_limit = 36

    while #signal_list < signal_limit do
        local signal = all_signals_list[math.random(#all_signals_list)]
        pick_signal(signal)
    end

    write_lci_common { device = device }
    writeln 'Adjust_input_assignments=On;'

    writeln '\n[Location Assignments]'

    local pla = make_pla()
    for name, info in spairs(signals) do
        if getmetatable(info).class == 'pin' then
            assign_pin_location(name, info)
        else
            pla:node(name)
            pla:pt({}, name)
            assign_node_location(name, info)
        end
    end

    pla:pt(signal_list, 'out')
    assign_node_location('out', device.glb(0))

    pla:write('test.tt4')
end


local gi_map = {
    gi0 = { 'fb A5' },
    gi1 = { 'fb A3' },
    gi2 = { 'fb A2' },
    gi3 = { 'fb A12' },
    gi4 = { 'fb A7' },
    gi5 = { 'fb A4' },
    gi6 = { 'fb B10' },
    gi7 = { 'fb A6' },
    gi8 = { 'fb A8' },
    gi9 = { 'fb B11' },
    gi10 = { 'pin 23' },
    gi11 = { 'pin 3' },
    gi12 = { 'pin 16' },
    gi13 = { 'fb A10' },
    gi14 = { 'fb A0' },
    gi15 = { 'fb B5' },
    gi16 = { 'fb B2' },
    gi17 = { 'fb A1' },
    gi18 = { 'fb A13', 'fb A2' },
    gi19 = { 'pin 7' },
    gi20 = { 'pin 46' },
    gi21 = { 'pin 42' },
    gi22 = { 'pin 32', 'fb A7' },
    gi23 = { 'pin 48' },
    gi24 = { 'fb B4', [[
        fb A6, fb B1, fb B13, pin 10, pin 45, fb A13, pin 17, fb B5, pin 38, pin 3, pin 31,
        pin 20, pin 38, fb A10, fb B11, fb A8, fb B0, pin 33, fb A3, pin 20, pin 45, fb A2, fb A9, fb A13, fb B12, pin 19, pin 45
    ]] },
    gi25 = { 'pin 21', 'pin 3, fb A11, pin 47, fb A5, pin 28, fb A13, fb A6, pin 17, fb B5, pin 38, fb B4, pin 40, fb A4, pin 24, fb B2, fb A3' },
    gi26 = { 'pin 26', 'pin 23' },
    gi27 = { 'fb B1', 'fb A6, fb A13, fb A2, fb B4' },
    gi28 = { 'fb A14', 'fb A4' },
    gi29 = { 'pin 7', [[
        pin 41, fb A4, fb A8, pin 19, pin 2
        pin 42, pin 22, fb B14, fb B3, fb B9
    ]] },
    gi30 = { 'pin 9', 'fb B11, fb A10' },
    gi31 = { 'pin 15', 'fb A1' },
    gi32 = { 'pin 34', 'fb A3, fb B2' },
    gi33 = { 'fb B13', 'fb A6, fb B1, fb B4' },
    gi34 = { 'fb A9', 'fb A2, fb B11, fb A13, fb B12, pin 19, pin 45' },
    gi35 = { 'pin 43', 'pin 23, fb A0' },
}

function write_lci_pt0 (device, glb, mc, gi, variant)
    local gi_data = gi_map['gi'..gi]

    write_lci_common { device = device }

    writeln '\n[Location Assignments]'

    local pla = make_pla()
    for name, info in spairs((parse_signal_list(device, gi_data[1]))) do
        if getmetatable(info).class == 'pin' then
            assign_pin_location(name, info)
        elseif info.glb.index ~= glb or info.index > mc then
            pla:node(name)
            pla:pt({}, name..'.D')
            assign_node_location(name, info)
        end
        if variant:sub(1,1) == 'n' then
            name = '~'..name
        end
        local out_name = 'glb'..glb..'_mc'..mc
        pla:pt(name, out_name..'.D')
        assign_node_location(out_name, device.glb(glb).mc(mc))
    end

    if gi_data[2] ~= nil then
        local other_signals
        local other_signals_list
        other_signals, other_signals_list = parse_signal_list(device, gi_data[2])
        for name, info in spairs(other_signals) do
            if getmetatable(info).class == 'pin' then
                assign_pin_location(name, info)
            elseif info.glb.index ~= glb or info.index > mc then
                pla:node(name)
                pla:pt({}, name..'.D')
                assign_node_location(name, info)
            end
        end
        pla:pt(other_signals_list, 'dummy')
        assign_node_location('dummy', device.glb(glb))
    end

    for xmc_index = 0, mc - 1 do
        local xmc = device.glb(glb).mc(xmc_index)
        local name = 'glb'..glb..'_mc'..xmc_index
        pla:pt('x0', name..'.D')
        pla:pt('x1', name..'.D')
        pla:pt('x2', name..'.D')
        pla:pt('x3', name..'.D')
        pla:pt('x4', name..'.D')
        assign_node_location(name, xmc)
    end

    pla:write(variant..'.tt4')
end


function write_lci_pt1 (device, glb, mc, gi, variant)
    local gi_data = gi_map['gi'..gi]

    write_lci_common { device = device }

    writeln '\n[Location Assignments]'

    local pla = make_pla()
    pla:node('asdf')
    pla:node('fdsa')
    pla:pt({'clk1', 'clk2'}, 'asdf.C')
    pla:pt({'clk1', 'clk2'}, 'fdsa.C')
    pla:pt({}, 'asdf.D')
    pla:pt({}, 'fdsa.D')
    assign_node_location('asdf', device.glb(glb))
    assign_node_location('fdsa', device.glb(glb))

    for name, info in spairs((parse_signal_list(device, gi_data[1]))) do
        if getmetatable(info).class == 'pin' then
            assign_pin_location(name, info)
        elseif info.glb.index ~= glb or info.index ~= mc then
            pla:node(name)
            pla:pt({}, name..'.D')
            assign_node_location(name, info)
        end
        if variant:sub(1,1) == 'n' then
            name = '~'..name
        end
        local out_name = 'glb'..glb..'_mc'..mc
        pla:pt(name, out_name..'.C')
        pla:pt({}, out_name..'.D')
        assign_node_location(out_name, device.glb(glb).mc(mc))
    end

    if gi_data[2] ~= nil then
        local other_signals
        local other_signals_list
        other_signals, other_signals_list = parse_signal_list(device, gi_data[2])
        for name, info in spairs(other_signals) do
            if getmetatable(info).class == 'pin' then
                assign_pin_location(name, info)
            elseif info.glb.index ~= glb or info.index ~= mc then
                pla:node(name)
                pla:pt({}, name..'.D')
                assign_node_location(name, info)
            end
        end
        pla:pt(other_signals_list, 'dummy')
        assign_node_location('dummy', device.glb(glb))
    end

    pla:write(variant..'.tt4')
end

function write_lci_pt2 (device, glb, mc, gi, variant)
    local gi_data = gi_map['gi'..gi]

    write_lci_common { device = device }

    writeln '\n[Location Assignments]'

    local pla = make_pla()
    pla:node('asdf')
    pla:node('fdsa')
    pla:pt({'clk1', 'clk2'}, 'asdf.C')
    pla:pt({'clk1', 'clk2'}, 'fdsa.C')
    pla:pt({}, 'asdf.D')
    pla:pt({}, 'fdsa.D')
    assign_node_location('asdf', device.glb(glb))
    assign_node_location('fdsa', device.glb(glb))

    for name, info in spairs((parse_signal_list(device, gi_data[1]))) do
        if getmetatable(info).class == 'pin' then
            assign_pin_location(name, info)
        elseif info.glb.index ~= glb or info.index ~= mc then
            pla:node(name)
            pla:pt({}, name..'.D')
            assign_node_location(name, info)
        end
        if variant:sub(1,1) == 'n' then
            name = '~'..name
        end
        local out_name = 'glb'..glb..'_mc'..mc
        pla:pt(name, out_name..'.CE')
        pla:pt({}, out_name..'.C')
        pla:pt({}, out_name..'.D')
        assign_node_location(out_name, device.glb(glb).mc(mc))
    end

    if gi_data[2] ~= nil then
        local other_signals
        local other_signals_list
        other_signals, other_signals_list = parse_signal_list(device, gi_data[2])
        for name, info in spairs(other_signals) do
            if getmetatable(info).class == 'pin' then
                assign_pin_location(name, info)
            elseif info.glb.index ~= glb or info.index ~= mc then
                pla:node(name)
                pla:pt({}, name..'.D')
                assign_node_location(name, info)
            end
        end
        pla:pt(other_signals_list, 'dummy')
        assign_node_location('dummy', device.glb(glb))
    end

    pla:write(variant..'.tt4')
end

function write_lci_pt3 (device, glb, mc, gi, variant)
    local gi_data = gi_map['gi'..gi]

    write_lci_common { device = device }

    writeln '\n[Location Assignments]'

    local pla = make_pla()
    pla:node('asdf')
    pla:node('fdsa')
    pla:pt({'clk1', 'clk2'}, 'asdf.C')
    pla:pt({'clk1', 'clk2'}, 'fdsa.C')
    pla:pt({}, 'asdf.D')
    pla:pt({}, 'fdsa.D')
    assign_node_location('asdf', device.glb(glb))
    assign_node_location('fdsa', device.glb(glb))

    for name, info in spairs((parse_signal_list(device, gi_data[1]))) do
        if getmetatable(info).class == 'pin' then
            assign_pin_location(name, info)
        elseif info.glb.index ~= glb or info.index ~= mc then
            pla:node(name)
            pla:pt({}, name..'.D')
            assign_node_location(name, info)
        end
        if variant:sub(1,1) == 'n' then
            name = '~'..name
        end
        local out_name = 'glb'..glb..'_mc'..mc
        pla:pt(name, out_name..'.CLR')
        pla:pt({}, out_name..'.C')
        pla:pt({}, out_name..'.D')
        assign_node_location(out_name, device.glb(glb).mc(mc))
    end

    if gi_data[2] ~= nil then
        local other_signals
        local other_signals_list
        other_signals, other_signals_list = parse_signal_list(device, gi_data[2])
        for name, info in spairs(other_signals) do
            if getmetatable(info).class == 'pin' then
                assign_pin_location(name, info)
            elseif info.glb.index ~= glb or info.index ~= mc then
                pla:node(name)
                pla:pt({}, name..'.D')
                assign_node_location(name, info)
            end
        end
        pla:pt(other_signals_list, 'dummy')
        assign_node_location('dummy', device.glb(glb))
    end

    writeln '\n[Register Powerup]'
    writeln('Default=RESET;')

    pla:write(variant..'.tt4')
end

local gi_map2 = {
    gi3pin14 = 'fb A3',
    gi3pin44 = 'pin 20',
    gi3glb1_mc12 = [[
        fb A2, fb A9, fb A13, fb B12, pin 19, pin 45, pin 23, pin 26, fb A14, pin 33,
        pin 46, pin 23, pin 26, pin 43, fb A2, fb B3, fb B11, fb A4, fb A14, fb B3,
        pin 18, pin 38, pin 4, fb A6, fb B1, fb B4, fb B13, pin 10, pin 45
    ]],
    gi4pin44 = 'pin 20, fb A12',
    gi4glb0_mc15 = 'fb A3',

    -- TODO gi5-35
}

function write_lci_grp (gi, device, glb, variant)
    local gi_signals
    local gi_signal_list
    gi_signals, gi_signal_list = parse_signal_list(device, variant)

    local signal_name = gi_signal_list[1]
    local signal_info = gi_signals[signal_name]

    local extra_signals = gi_map2['gi'..gi..signal_name]

    write_lci_common { device = device }
    writeln '\n[Location Assignments]'
    local pla = make_pla()

    if getmetatable(signal_info).class == 'pin' then
        assign_pin_location(signal_name, signal_info)
    else
        pla:node(signal_name)
        pla:pt({}, signal_name..'.D')
        assign_node_location(signal_name, signal_info)
    end
    
    pla:pt(signal_name, 'out')
    assign_node_location('out', device.glb(glb))

    if extra_signals ~= nil then
        local other_signals
        local other_signals_list
        other_signals, other_signals_list = parse_signal_list(device, extra_signals)
        for name, info in spairs(other_signals) do
            if name ~= signal_name then
                if getmetatable(info).class == 'pin' then
                    assign_pin_location(name, info)
                else
                    pla:node(name)
                    pla:pt({}, name..'.D')
                    assign_node_location(name, info)
                end
            end
        end
        pla:pt(other_signals_list, 'dummy')
        assign_node_location('dummy', device.glb(glb))
    end

    pla:write(variant..'.tt4')
end

write_lci_grp_gi0 = function(...) write_lci_grp(0, ...) end
write_lci_grp_gi1 = function(...) write_lci_grp(1, ...) end
write_lci_grp_gi2 = function(...) write_lci_grp(2, ...) end
write_lci_grp_gi3 = function(...) write_lci_grp(3, ...) end
write_lci_grp_gi4 = function(...) write_lci_grp(4, ...) end
write_lci_grp_gi5 = function(...) write_lci_grp(5, ...) end
write_lci_grp_gi6 = function(...) write_lci_grp(6, ...) end
write_lci_grp_gi7 = function(...) write_lci_grp(7, ...) end
write_lci_grp_gi8 = function(...) write_lci_grp(8, ...) end
write_lci_grp_gi9 = function(...) write_lci_grp(9, ...) end
write_lci_grp_gi10 = function(...) write_lci_grp(10, ...) end
write_lci_grp_gi11 = function(...) write_lci_grp(11, ...) end
write_lci_grp_gi12 = function(...) write_lci_grp(12, ...) end
write_lci_grp_gi13 = function(...) write_lci_grp(13, ...) end
write_lci_grp_gi14 = function(...) write_lci_grp(14, ...) end
write_lci_grp_gi15 = function(...) write_lci_grp(15, ...) end
write_lci_grp_gi16 = function(...) write_lci_grp(16, ...) end
write_lci_grp_gi17 = function(...) write_lci_grp(17, ...) end
write_lci_grp_gi18 = function(...) write_lci_grp(18, ...) end
write_lci_grp_gi19 = function(...) write_lci_grp(19, ...) end
write_lci_grp_gi20 = function(...) write_lci_grp(20, ...) end
write_lci_grp_gi21 = function(...) write_lci_grp(21, ...) end
write_lci_grp_gi22 = function(...) write_lci_grp(22, ...) end
write_lci_grp_gi23 = function(...) write_lci_grp(23, ...) end
write_lci_grp_gi24 = function(...) write_lci_grp(24, ...) end
write_lci_grp_gi25 = function(...) write_lci_grp(25, ...) end
write_lci_grp_gi26 = function(...) write_lci_grp(26, ...) end
write_lci_grp_gi27 = function(...) write_lci_grp(27, ...) end
write_lci_grp_gi28 = function(...) write_lci_grp(28, ...) end
write_lci_grp_gi29 = function(...) write_lci_grp(29, ...) end
write_lci_grp_gi30 = function(...) write_lci_grp(30, ...) end
write_lci_grp_gi31 = function(...) write_lci_grp(31, ...) end
write_lci_grp_gi32 = function(...) write_lci_grp(32, ...) end
write_lci_grp_gi33 = function(...) write_lci_grp(33, ...) end
write_lci_grp_gi34 = function(...) write_lci_grp(34, ...) end
write_lci_grp_gi35 = function(...) write_lci_grp(35, ...) end

function write_lci_ff_type (device, glb, mc, variant)
    local pla = make_pla()
    write_lci_common { device = device }
    writeln '\n[Location Assignments]'

    pla:node('out')
    if variant == 'D' then
        pla:pt('in', 'out.D')
        pla:pt('clk', 'out.C')
    elseif variant == 'T' then
        pla:pt('in', 'out.T')
        pla:pt('clk', 'out.C')
    elseif variant == 'latch' then
        pla:pt('in', 'out.D')
        pla:pt('clk', 'out.LH')
    else
        pla:pt('in', 'out')
    end
    assign_node_location('out', device.glb(glb).mc(mc))

    pla:write(variant..'.tt4')
end

function write_lci_pt2_reset (device, glb, mc, variant)
    local pla = make_pla()
    write_lci_common { device = device }
    writeln '\n[Location Assignments]'

    pla:pt('in', 'out.D')
    if variant == 'pt' then
        pla:pt('as', 'out.AP')
    end
    assign_node_location('out', device.glb(glb).mc(mc))

    pla:write(variant..'.tt4')

    writeln '\n[Register Powerup]'
    writeln('Default = RESET;')
end

function write_lci_pt3_reset (device, glb, mc, variant)
    local pla = make_pla()
    write_lci_common { device = device }
    writeln '\n[Location Assignments]'

    pla:pt('in', 'b.D')
    pla:pt('gas', 'b.AR')
    assign_node_location('b', device.glb(glb).mc((mc+15) % 16))

    pla:pt('in', 'a.D')
    if variant == 'pt' then
        pla:pt('xas', 'a.AR')
    elseif variant == 'shared' then
        pla:pt('gas', 'a.AR')
    end
    assign_node_location('a', device.glb(glb).mc(mc))


    pla:write(variant..'.tt4')

    writeln '\n[Register Powerup]'
    writeln('Default = RESET;')
end

function write_lci_clk_mux (device, glb, mc, variant)
    local pla = make_pla()
    write_lci_common { device = device }
    writeln '\n[Location Assignments]'

    assign_pin_location('clk0', device.clk(0))
    assign_pin_location('clk1', device.clk(1))
    assign_pin_location('clk2', device.clk(2))
    assign_pin_location('clk3', device.clk(3))
    assign_node_location('out', device.glb(glb).mc(mc))

    pla:pt('in', 'out.D')

    local other_glb = 0
    if glb == 0 then other_glb = 1 end
    assign_pin_location('sck', device.glb(other_glb).mc(3))

    pla:pt({}, {'dummy1.D','dummy2.D'})
    pla:pt('sck', 'dummy1.C')
    pla:pt('sck', 'dummy2.C')
    assign_pin_location('dummy1', device.glb(glb))
    assign_pin_location('dummy2', device.glb(glb))

    if variant == 'pt' then
        pla:pt({'a','b'}, 'out.C')
        assign_pin_location('a', device.glb(other_glb).mc(4))
        assign_pin_location('b', device.glb(other_glb).mc(5))
    elseif variant == 'npt' then
        pla:pt({'a','b'}, 'out.C-')
        local other_glb = 0
        if glb == 0 then other_glb = 1 end
        assign_pin_location('a', device.glb(other_glb).mc(4))
        assign_pin_location('b', device.glb(other_glb).mc(5))
    elseif variant == 'shared_pt' then
        pla:pt('sck', 'out.C')
    elseif variant == 'bclk0' then
        pla:pt('clk0', 'out.C')
    elseif variant == 'bclk1' then
        pla:pt('clk1', 'out.C')
    elseif variant == 'bclk2' then
        pla:pt('clk2', 'out.C')
    elseif variant == 'bclk3' then
        pla:pt('clk3', 'out.C')
    end

    pla:write(variant..'.tt4')
end


function write_lci_shared_ptclk_polarity (device, glb, variant)
    local pla = make_pla()
    write_lci_common { device = device }
    writeln '\n[Location Assignments]'

    assign_node_location('out', device.glb(glb).mc(3))

    pla:pt('in', 'out.D')

    local other_glb = 0
    if glb == 0 then other_glb = 1 end
    assign_pin_location('sck1', device.glb(other_glb).mc(3))
    assign_pin_location('sck2', device.glb(other_glb).mc(4))

    if variant == 'invert' then
        pla:pt({'sck1','sck2'}, 'out.C-')
    else
        pla:pt({'sck1','sck2'}, 'out.C')
    end

    pla:write(variant..'.tt4')
end

function write_lci_shared_ptinit_polarity (device, glb, variant)
    local pla = make_pla()
    write_lci_common { device = device }
    writeln '\n[Location Assignments]'

    pla:pt('in', 'out.D')
    if variant == 'invert' then
        pla:pt('as', 'out.AR-')
    else
        pla:pt('as', 'out.AR')
    end
    assign_node_location('out', device.glb(glb).mc(4))

    writeln '\n[Register Powerup]'
    writeln('Default = RESET;')

    pla:write(variant..'.tt4')
end
