include 'lci_helper'
include 'lc4032ze'


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

function write_lci_osctimer (device, variant)
    local pla = make_pla()
    write_lci_common { device = device }

    pla:pt('in', 'dummy')

    if variant ~= 'none' then
        local prop = "#$ PROPERTY LATTICE OSCTIMER osc= "
        local inst = "#$ INSTANCE osc OSCTIMER 4 "
        writeln '\n[OSCTIMER Assignments]'
        writeln 'layer = OFF;'
        write 'OSCTIMER = '
        if variant:match('dynoscdis') then
            write 'osc_dis, '
            pla:pin('osc_dis')
            prop = prop..'osc_dis, '
            inst = inst..'osc_dis '
        else
            write '-, '
            prop = prop..'-, '
            inst = inst..'osc>dis '
        end
        if variant:match('timerres') then
            write 'osc_reset, '
            pla:pin('osc_reset')
            prop = prop..'osc_reset, '
            inst = inst..'osc_reset '
        else
            write '-, '
            prop = prop..'-, '
            inst = inst..'osc>reset '
        end
        if variant:match('oscout') then
            write 'osc_out, '
            pla:node('osc_out')
            prop = prop..'osc_out, '
            inst = inst..'osc_out '
        else
            write '-, '
            prop = prop..'-, '
            inst = inst..'osc>out '
        end
        if variant:match('timerout') then
            write 'osc_tout'
            pla:node('osc_tout')
            prop = prop..'osc_tout'
            inst = inst..'osc_tout'
        else
            write '-'
            prop = prop..'-'
            inst = inst..'osc>tout'
        end
        write ', 128;'

        pla:ext(prop.. ', 128;')
        pla:ext("#$ EXTERNAL OSCTIMER 4 DYNOSCDIS'i' TIMERRES'i' OSCOUT'o' TIMEROUT'o'")
        pla:ext(inst)
    end

    pla:write(variant..'.tt4')
end

function write_lci_osctimer_div (device, variant)
    local pla = make_pla()
    write_lci_common { device = device }

    pla:pt('in', 'dummy')

    writeln '\n[OSCTIMER Assignments]'
    writeln 'layer = OFF;'
    writeln('OSCTIMER = osc_dis, osc_reset, osc_out, osc_tout, ',variant,';')

    pla:pin('osc_dis', 'osc_reset', 'osc_out', 'osc_tout')
    pla:ext("#$ PROPERTY LATTICE OSCTIMER osc= osc_dis, osc_reset, osc_out, osc_tout, "..variant..";")
    pla:ext("#$ EXTERNAL OSCTIMER 4 DYNOSCDIS'i' TIMERRES'i' OSCOUT'o' TIMEROUT'o'")
    pla:ext("#$ INSTANCE osc OSCTIMER 4 osc_dis osc_reset osc_out osc_tout")

    pla:write(variant..'.tt4')
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

function write_lci_goe23_polarity (device, variant)
    local pla = make_pla()

    write_lci_common { device = device }
    writeln '\n[Location Assignments]'

    local glb = device.glb(0)

    pla:pin('o2', 'o3')
    pla:pt('i', {'o2', 'o3'})
    assign_pin_location('o2', glb.mc(2))
    assign_pin_location('o3', glb.mc(3))

    if variant == 'goe2low_goe3low' or variant == 'goe2low_goe3high' then
        pla:pt({'g2a', 'g2b'}, 'o2.OE-')
    else
        pla:pt({'g2a', 'g2b'}, 'o2.OE')
    end
    if variant == 'goe2low_goe3low' or variant == 'goe2high_goe3low' then
        pla:pt({'g3a', 'g3b'}, 'o3.OE-')
    else
        pla:pt({'g3a', 'g3b'}, 'o3.OE')
    end

    pla:write(variant..'.tt4')
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

function write_lci_ptoe_orm (device, variant)
    local pla = make_pla()

    write_lci_common { device = device }
    writeln '\n[Location Assignments]'

    for mc, mci in device.glb(0).mcs() do
        if mc > 0 and mc < 13 then
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
    assign_pin_location('goe2', device.glb(1).mc(1).pin)
    assign_pin_location('goe3', device.glb(1).mc(2).pin)

    if variant == 'test' then
        pla:pin('out')
        pla:pt('in', 'out')
        pla:pt({'in0', 'in1'}, 'out.OE')
        assign_pin_location('out', device.glb(0).mc(13))
    else
        --pla:pin('out')
        pla:pt('in', 'out')
        --pla:pt({'in0', 'in1'}, 'out.OE')
        --assign_pin_location('out', device.glb(0).mc(0))
        assign_node_location('out', device.glb(0).mc(0))
    end
    
    pla:pt({}, 'block')
    assign_node_location('block', device.glb(0).mc(13))

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

function write_lci_clusters (device, variant)
    local pla = make_pla()
    write_lci_common { device = device }
    writeln '\n[Location Assignments]'

    local n = variant + 0
    for i = 1, n do
        local inputs = {
            'i0',
            'i1',
            'i2',
            'i3',
            'i4',
            'i5',
            'i6',
        }

        if i & 1 == 0 then inputs[1] = '~i0' end
        if i & 2 == 0 then inputs[2] = '~i1' end
        if i & 4 == 0 then inputs[3] = '~i2' end
        if i & 8 == 0 then inputs[4] = '~i3' end
        if i & 16 == 0 then inputs[5] = '~i4' end
        if i & 32 == 0 then inputs[6] = '~i5' end
        if i & 64 == 0 then inputs[7] = '~i6' end

        pla:pt(inputs, 'out')
    end

    assign_node_location('out', device.glb(0).mc(1))

    pla:write(variant..'.tt4')
end


function write_lci_xor (device, glb, mc, variant)
    local pla = make_pla()

    write_lci_common { device = device }
    writeln '\n[Location Assignments]'

    for i = 0, mc - 1 do
        local sig = 'd'..i
        assign_node_location(sig, device.glb(glb).mc(i))
        pla:pt('x0', sig)
        pla:pt('x1', sig)
        pla:pt('x2', sig)
        pla:pt('x3', sig)
        pla:pt('x4', sig)
    end

    assign_node_location('out', device.glb(glb).mc(mc))
    pla:pt('in1', 'out.C')

    if variant == 'normal' then
        pla:pt('in1', 'out.D')
        pla:pt('in2', 'out.D')
    elseif variant == 'invert' then
        pla:pt('in1', 'out.D-')
        pla:pt('in2', 'out.D-')
    elseif variant == 'xor_pt0' then
        pla:pt({'in1','in2'}, 'out.D')
    elseif variant == 'xor_npt0' then
        pla:pt({'in1','in2'}, 'out.D-')
    end

    pla:write(variant..'.tt4')
end
