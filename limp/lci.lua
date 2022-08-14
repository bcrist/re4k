device = {}
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

write_mc_location_assignment = template [[`signal`=pin,`device.glb[glb].mc_to_pin[mc]`,-,`device.glb[glb].name`,`mc`;`nl]]
write_clk_location_assignment = template [[`signal`=pin,`device.clk_to_pin[clk]`,-,-,-;`nl]]
write_io_type_constraint = template [[`signal`=`iostd`,pin,-,-;`nl]]

function write_lci_32out (device, special_glb, special_mc)
     -- uses buf_1in_32out.pla
     write_lci_common { device = device }

     writeln '\n[Location Assignments]'
     write_clk_location_assignment {
         device = device,
         signal = 'in',
         clk = '0'
     }
     local n = 0
     local special_signal = ''
     for glb, glb_data in spairs(device.glb) do
         for mc in spairs(glb_data.mc_to_pin) do
             local signal = 'out' .. n
             if glb == special_glb and mc == special_mc then
                 special_signal = signal
             end
             write_mc_location_assignment {
                 device = device,
                 signal = signal,
                 glb = glb,
                 mc = mc
             }
             n = n + 1
         end
     end
     nl()

     return special_signal
end

function write_lci_31in_1out (device, special_glb, special_mc, out_glb, out_mc)
    if out_glb == nil then
        out_mc = '0'
        if special_glb == '0' then
            out_glb = '1'
        else
            out_glb = '0'
        end
    end

    -- uses and_31in_1out.pla
    write_lci_common { device = device }
    
    writeln '\n[Location Assignments]'
    local n = 0
    local special_signal = ''
    for glb, glb_data in spairs(device.glb) do
        for mc in spairs(glb_data.mc_to_pin) do
            local signal = 'in' .. n
            if glb == out_glb and mc == out_mc then
                signal = 'out'
            else
                n = n + 1
            end
            if glb == special_glb and mc == special_mc then
                special_signal = signal
            end
            write_mc_location_assignment {
                device = device,
                signal = signal,
                glb = glb,
                mc = mc
            }
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
