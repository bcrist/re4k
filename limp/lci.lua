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

    pla:pin('out_goe0', 'out_goe1', 'out_goe2', 'out_goe3', 'out')

    pla:pt({}, { 'out_goe0', 'out_goe1', 'out_goe2', 'out_goe3' })
    pla:pt('goe0', 'out_goe0.OE')
    pla:pt('goe1', 'out_goe1.OE')
    pla:pt('goe2', 'out_goe2.OE')
    pla:pt('goe3', 'out_goe3.OE')

    pla:pt('in0', 'out')
    pla:pt('in1', 'out')
    pla:pt('in2', 'out')
    pla:pt('in3', 'out')

    if variant == 'goe0' then
        pla:pt('goe0', 'out.OE')

    elseif variant == 'goe1' then
        pla:pt('goe1', 'out.OE')

    elseif variant == 'goe2' then
        pla:pt('goe2', 'out.OE')

    elseif variant == 'goe3' then
        pla:pt('goe3', 'out.OE')

    elseif variant == 'pt' then
        pla:pt({'in0', 'in1'}, 'out.OE')

    elseif variant == 'npt' then
        pla:pt({'in0', 'in1'}, 'out.OE-')

    elseif variant == 'on' then
        pla:pt({}, 'out.OE')

    elseif variant == 'off' then
        pla:output('out.OE')
    
    end

    pla:write(variant..'.tt4')


    write_lci_common { device = device }

    local glb = device.glb(special_glb)
    local scratch_glb = device.glb((special_glb + 1) % device.num_glbs)

    local scratch_base
    if special_mc < 8 then
        scratch_base = 8
    else
        scratch_base = 1
    end

    writeln '\n[Location Assignments]'

    if glb.mc(special_mc).pin.type ~= 'IO' then
        assign_pin_location('goe0', scratch_glb.mc(8).pin)
        assign_pin_location('goe1', scratch_glb.mc(9).pin)
    else
        assign_pin_location('goe0', device.goe(0))
        assign_pin_location('goe1', device.goe(1))
    end
    assign_pin_location('goe2', scratch_glb.mc(1).pin)
    assign_pin_location('goe3', scratch_glb.mc(2).pin)
    assign_pin_location('in0', scratch_glb.mc(3).pin)
    assign_pin_location('in1', scratch_glb.mc(4).pin)
    assign_pin_location('in2', scratch_glb.mc(5).pin)
    assign_pin_location('in3', scratch_glb.mc(6).pin)

    assign_pin_location('out_goe0', glb.mc(scratch_base))
    assign_pin_location('out_goe1', glb.mc(scratch_base+1))
    assign_pin_location('out_goe2', glb.mc(scratch_base+2))
    assign_pin_location('out_goe3', glb.mc(scratch_base+3))

    assign_pin_location('out', glb.mc(special_mc))
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
    assign_node_location('out2', device.glb(special_glb).mc(scratch_base))
    assign_node_location('out3', device.glb(special_glb).mc(scratch_base+1))
    assign_node_location('out4', device.glb(special_glb).mc(scratch_base+2))
end
