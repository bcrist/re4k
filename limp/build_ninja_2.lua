local device = ...
local standalone_jobs = {
    'zerohold',
    'slew',
    'threshold',
    'pull',
    'drive',
    'oe_mux',
    'orm',
    'powerup_state',
    'ce_mux',
    'reg_type',
    'pt2_reset',
    'pt3_reset',
    'clk_mux',
    'input_reg',
    'invert',
}
local grp_jobs = {
    'pterms'
}

writeln('dev = ', fs.compose_path(device:sub(1, 6), device), nl)

grp_devices = {
    LC4032x_TQFP48 = true,
    LC4064x_TQFP48 = true,
    LC4064x_TQFP100 = true,
    LC4128V_TQFP144 = true,

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
}

if grp_devices[device] == true then
    writeln('rule grp')
    writeln('    command = zig-out/bin/grp.exe $out')
    writeln('build $dev/grp.sx: grp')
    nl()
else
    local grp_device = grp_devices[device]
    local grp_input = fs.compose_path(device:sub(1, 6), grp_device, "grp.sx")
    writeln('rule convert-grp')
    writeln('    command = zig-out/bin/convert-grp.exe $out $in')
    writeln('build $dev/grp.sx: convert-grp ', grp_input)
    nl()
end

for _, job in ipairs(standalone_jobs) do
    writeln('rule ', job)
    writeln('    command = zig-out/bin/', job, '.exe $out')
    writeln('build $dev/', job, '.sx: ', job)
    nl()
end

for _, job in ipairs(grp_jobs) do
    writeln('rule ', job)
    writeln('    command = zig-out/bin/', job, '.exe $out $in')
    writeln('build $dev/', job, '.sx: ', job, ' $dev/grp.sx')
    nl()
end

write('build build-', device, ': phony $dev/grp.sx')
for _, job in ipairs(standalone_jobs) do
    write(' $dev/', job, '.sx')
end
for _, job in ipairs(grp_jobs) do
    write(' $dev/', job, '.sx')
end
nl()
