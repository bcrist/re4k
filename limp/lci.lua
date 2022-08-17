include 'lc4032ze'

write_lci_common = template [[
[Revision]
Parent = `device.series`.lci;

[Fitter Report Format]
Detailed = yes;

[Constraint Version]
version = 1.0;

[Device]
Family = `device.family`;
PartNumber = `device.full_part_number`;
Package = `device.package`;
PartType = `device.part_number`;
Speed = `device.speed_grade`;
Operating_condition = `device.temp_grade`;
Status = Production;
Default_Device_Io_Types=LVCMOS33,-;

[Global Constraints]
Spread_Placement=No;
]]

write_mc_location_assignment = template [[`signal`=pin,`mc.pin.number`,-,`mc.glb.name`,`mc.index`;`nl]]
write_mc_pin_location_assignment = template [[`signal`=pin,`pin.number`,-,`mc.glb.name`,`mc.index`;`nl]]
write_pin_location_assignment = template [[`signal`=pin,`pin.number`,-,-,-;`nl]]
write_node_location_assignment = template [[`signal`=node,-,-,`mc.glb.name`,`mc.index`;`nl]]
write_io_type_constraint = template [[`signal`=`iostd`,pin,-,-;`nl]]

function write_lci_32out (device, special_glb, special_mc)
     -- uses buf_1in_32out.pla
     write_lci_common { device = device }

     writeln '\n[Location Assignments]'
     write_pin_location_assignment {
         signal = 'in',
         pin = device.clk(0)
     }
     local n = 0
     local special_signal = ''
     for _, glb in device.glbs() do
         for _, mc in glb.mcs() do
            if n < 32 then
                local signal = 'out' .. n
                if glb.index == special_glb and mc.index == special_mc then
                    special_signal = signal
                end
                write_mc_location_assignment {
                    signal = signal,
                    mc = mc
                }
                n = n + 1
            end
         end
     end
     nl()

     return special_signal
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
                write_mc_location_assignment {
                    signal = signal,
                    mc = mc
                }
            end
        end
    end
    nl()

    return special_signal
end

function write_lci_input_threshold (device, special_glb, special_mc, iostd)
    local special_signal = write_lci_31in_1out(device, special_glb, special_mc)
    writeln '\n[IO Types]'
    write_io_type_constraint { signal = special_signal, iostd = iostd }
end

function write_lci_input_threshold_clk (device, special_clk, iostd)
    -- uses and_31in_1out.pla
    write_lci_common { device = device }

    writeln '\n[Location Assignments]'
    write_pin_location_assignment {
        signal = 'in0',
        pin = device.clk(special_clk)
    }
    write_mc_location_assignment {
        signal = 'out',
        mc = device.glb(1).mc(15)
    }
    local n = 1
    for _, glb in device.glbs() do
        for _, mc in glb.mcs() do
            if n < 31 then
                local signal = 'in' .. n
                n = n + 1
                write_mc_location_assignment {
                    signal = signal,
                    mc = mc
                }
            end
        end
    end
    nl()

    writeln '\n[IO Types]'
    write_io_type_constraint { signal = 'in0', iostd = iostd }
end

function write_lci_od (device, special_glb, special_mc, iostd)
    local special_signal = write_lci_32out(device, special_glb, special_mc)
    writeln '\n[IO Types]'
    write_io_type_constraint { signal = special_signal, iostd = iostd }
end

function write_lci_pull (device, special_glb, special_mc, pull_mode)
    local special_signal = write_lci_31in_1out(device, special_glb, special_mc)
    writeln '\n[Pullup]'
    writeln 'Default=DOWN;'
    writeln(pull_mode, '=', special_signal, ';')
end

function write_lci_pull_clk (device, special_clk, pull_mode)
    -- uses and_31in_1out.pla
    write_lci_common { device = device }

    writeln '\n[Location Assignments]'
    write_pin_location_assignment {
        signal = 'in0',
        pin = device.clk(special_clk)
    }
    write_mc_location_assignment {
        signal = 'out',
        mc = device.glb(1).mc(15)
    }
    local n = 1
    for _, glb in device.glbs() do
        for _, mc in glb.mcs() do
            if n < 31 then
                local signal = 'in' .. n
                n = n + 1
                write_mc_location_assignment {
                    signal = signal,
                    mc = mc
                }
            end
        end
    end
    nl()

    writeln '\n[Pullup]'
    writeln 'Default=DOWN;'
    writeln(pull_mode, '=in0;')
end

function write_lci_slew (device, special_glb, special_mc, special_slew)
    local special_signal = write_lci_32out(device, special_glb, special_mc)
    writeln '\n[Slewrate]'
    writeln 'Default=FAST;'
    writeln(special_slew, '=', special_signal, ';')
end

function write_lci_zerohold (device, yes_or_no)
    write_lci_common { device = device }
    writeln('Zero_hold_time=', yes_or_no, ';')
end

function write_lci_security (device, on_or_off)
    write_lci_common { device = device }
    writeln('Security=', on_or_off, ';')
end

function write_lci_bclk (device, special_glb, clk0, clk1)
    write_lci_common { device = device }
    writeln '\n[Location Assignments]'
    write_pin_location_assignment { signal = 'clk0', pin = device.clk(clk0) }
    write_pin_location_assignment { signal = 'clk1', pin = device.clk(clk1) }
    write_mc_location_assignment { signal = 'in0', mc = device.glb(special_glb).mc(0) }
    write_mc_location_assignment { signal = 'in1', mc = device.glb(special_glb).mc(1) }
    write_node_location_assignment { signal = 'co0', mc = device.glb(special_glb).mc(14) }
    write_node_location_assignment { signal = 'co1', mc = device.glb(special_glb).mc(15) }
    writeln '\n[Input Registers]'
    writeln 'Default=INREG;'
end

function write_lci_bclk01 (device, special_glb)
    write_lci_bclk(device, special_glb, 0, 1)
end
function write_lci_bclk23 (device, special_glb)
    write_lci_bclk(device, special_glb, 2, 3)
end


function write_lci_pgdf (device, special_glb, special_mc)
    write_lci_common { device = device }
    writeln '\n[Location Assignments]'
    write_pin_location_assignment { signal = 'in_PG_E', pin = device.clk(0) }
    write_mc_location_assignment { signal = 'in1_PG_D', mc = device.glb(special_glb).mc(special_mc) }
    write_mc_location_assignment { signal = 'in0_PG_D', mc = device.glb(special_glb).mc((special_mc + 1) % 16) }
    write_mc_location_assignment { signal = 'out', mc = device.glb(special_glb).mc((special_mc + 2) % 16) }
end

function write_lci_pgdf_clk (device, special_clk)
    write_lci_common { device = device }
    local clk = device.clk(special_clk)
    writeln '\n[Location Assignments]'
    write_pin_location_assignment { signal = 'in1_PG_D', pin = clk }
    write_mc_location_assignment { signal = 'in_PG_E', mc = device.glb(clk.glb.index or 0).mc(0) }
    write_mc_location_assignment { signal = 'in0_PG_D', mc = device.glb(clk.glb.index or 0).mc(1) }
    write_mc_location_assignment { signal = 'out', mc = device.glb(clk.glb.index or 0).mc(2) }
end

function write_lci_goe0_polarity (device)
    write_lci_common { device = device }
    writeln '\n[Location Assignments]'
    write_pin_location_assignment { signal = 'oe', pin = device.goe(0) }
    write_mc_location_assignment { signal = 'in', mc = device.glb(0).mc(4) }
    write_mc_location_assignment { signal = 'out', mc = device.glb(0).mc(5) }
end

function write_lci_goe1_polarity (device)
    write_lci_common { device = device }
    writeln '\n[Location Assignments]'
    write_pin_location_assignment { signal = 'oe', pin = device.goe(1) }
    write_mc_location_assignment { signal = 'in', mc = device.glb(0).mc(4) }
    write_mc_location_assignment { signal = 'out', mc = device.glb(0).mc(5) }
end

-- function write_lci_goe23_polarity (device)
--     write_lci_common { device = device }
--     writeln '\n[Location Assignments]'
--     write_mc_location_assignment { signal = 'oe0a', mc = device.glb(1).mc(1) }
--     write_mc_location_assignment { signal = 'oe0b', mc = device.glb(1).mc(2) }
--     write_mc_location_assignment { signal = 'oe1a', mc = device.glb(1).mc(3) }
--     write_mc_location_assignment { signal = 'oe1b', mc = device.glb(1).mc(4) }

--     write_mc_location_assignment { signal = 'in0', mc = device.glb(0).mc(1) }
--     write_mc_location_assignment { signal = 'in1', mc = device.glb(0).mc(2) }
--     write_mc_location_assignment { signal = 'out0', mc = device.glb(0).mc(3) }
--     write_mc_location_assignment { signal = 'out1', mc = device.glb(0).mc(4) }
-- end

function write_lci_oe_mux (device, special_glb, special_mc, variant)
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
        write_pin_location_assignment { signal = 'goe0',  pin = scratch_glb.mc(8).pin }
        write_pin_location_assignment { signal = 'goe1',  pin = scratch_glb.mc(9).pin }
    else
        write_pin_location_assignment { signal = 'goe0', pin = device.goe(0) }
        write_pin_location_assignment { signal = 'goe1', pin = device.goe(1) }
    end
    write_pin_location_assignment { signal = 'goe2', pin = scratch_glb.mc(1).pin }
    write_pin_location_assignment { signal = 'goe3', pin = scratch_glb.mc(2).pin }
    write_pin_location_assignment { signal = 'in0',  pin = scratch_glb.mc(3).pin }
    write_pin_location_assignment { signal = 'in1',  pin = scratch_glb.mc(4).pin }
    write_pin_location_assignment { signal = 'in2',  pin = scratch_glb.mc(5).pin }
    write_pin_location_assignment { signal = 'in3',  pin = scratch_glb.mc(6).pin }
    write_pin_location_assignment { signal = 'in4',  pin = scratch_glb.mc(7).pin }

    write_mc_location_assignment { signal = 'out_goe0', mc = glb.mc(scratch_base) }
    write_mc_location_assignment { signal = 'out_goe1', mc = glb.mc(scratch_base+1) }
    write_mc_location_assignment { signal = 'out_goe2', mc = glb.mc(scratch_base+2) }
    write_mc_location_assignment { signal = 'out_goe3', mc = glb.mc(scratch_base+3) }

    write_mc_location_assignment { signal = 'out', mc = glb.mc(special_mc) }

    writeln '\n[TIMING CONSTRAINTS]'
    writeln 'layer = OFF;'
    writeln 'tPD_0 = 1, goe2, out_goe2;'
    writeln 'tPD_0 = 1, goe3, out_goe3;'
end

function write_lci_orm (device, special_glb, special_mc, variant)
    write_lci_common { device = device }

    writeln '\n[Location Assignments]'
    write_pin_location_assignment { signal = 'in',  pin = device.clk(0) }

    local glb = device.glb(special_glb)

    local mc = special_mc
    if variant ~= 'self' then
        mc = (mc + variant:sub(2)) % 16
    end
    
    local n = 1
    for i = 0, 15 do
        if i ~= mc then
            write_node_location_assignment { signal = 'out'..n, mc = glb.mc(i) }
            n = n + 1
        end
    end

    write_mc_pin_location_assignment { signal = 'out0', mc = glb.mc(mc), pin = glb.mc(special_mc).pin }
end
