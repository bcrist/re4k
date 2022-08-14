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
//EN_PinGLB = yes;
//EN_PinMacrocell = yes;
//Pin_MC_1to1 = yes;

[Global Constraints]
SPREAD_PLACEMENT=No;
]]

write_mc_location_assignment = template [[`signal`=pin,`mc.pin.number`,-,`mc.glb.name`,`mc.index`;`nl]]
write_clk_location_assignment = template [[`signal`=pin,`clk.number`,-,-,-;`nl]]
write_node_location_assignment = template [[`signal`=node,-,-,`mc.glb.name`,`mc.index`;`nl]]
write_io_type_constraint = template [[`signal`=`iostd`,pin,-,-;`nl]]

function write_lci_32out (device, special_glb, special_mc)
     -- uses buf_1in_32out.pla
     write_lci_common { device = device }

     writeln '\n[Location Assignments]'
     write_clk_location_assignment {
         signal = 'in',
         clk = device.clk(0)
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
    write_clk_location_assignment {
        signal = 'in0',
        clk = device.clk(special_clk)
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
    write_clk_location_assignment {
        signal = 'in0',
        clk = device.clk(special_clk)
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
    write_clk_location_assignment { signal = 'clk0', clk = device.clk(clk0) }
    write_clk_location_assignment { signal = 'clk1', clk = device.clk(clk1) }
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


function write_lci_pgdf (device, special_glb, special_mc, variant)
    write_lci_common { device = device }
    writeln '\n[Location Assignments]'
    write_clk_location_assignment { signal = 'in_PG_E', clk = device.clk(0) }
    write_mc_location_assignment { signal = 'in1_PG_D', mc = device.glb(special_glb).mc(special_mc) }
    write_mc_location_assignment { signal = 'in0_PG_D', mc = device.glb(special_glb).mc((special_mc + 1) % 16) }
    write_mc_location_assignment { signal = 'out', mc = device.glb(special_glb).mc((special_mc + 2) % 16) }
end

function write_lci_pgdf_clk (device, special_clk, variant)
    write_lci_common { device = device }

    local clk = device.clk(special_clk)

    writeln '\n[Location Assignments]'
    write_clk_location_assignment { signal = 'in1_PG_D', clk = clk }
    write_mc_location_assignment { signal = 'in_PG_E', mc = device.glb(clk.glb.index or 0).mc(0) }
    write_mc_location_assignment { signal = 'in0_PG_D', mc = device.glb(clk.glb.index or 0).mc(1) }
    write_mc_location_assignment { signal = 'out', mc = device.glb(clk.glb.index or 0).mc(2) }
end
