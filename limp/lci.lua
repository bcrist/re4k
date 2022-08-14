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
EN_PinGLB = yes;
EN_PinMacrocell = yes;
Pin_MC_1to1 = yes;
Default_Device_Io_Types=LVCMOS33,-;
]]

write_mc_location_assignment = template [[`signal`=pin,`mc.pin.number`,-,`mc.glb.name`,`mc.index`;`nl]]
write_clk_location_assignment = template [[`signal`=pin,`clk.number`,-,-,-;`nl]]
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
    writeln '\n[Global Constraints]'
    writeln('Zero_hold_time=', yes_or_no, ';')
end
