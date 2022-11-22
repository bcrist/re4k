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
