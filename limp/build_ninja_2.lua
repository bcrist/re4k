local device = ...
local jobs = {
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
}

writeln('dev = ', fs.compose_path(device:sub(1, 6), device), nl)

grp_devices = {
    LC4032ZE_TQFP48 = true,
    LC4032ZC_TQFP48 = true,
    LC4032x_TQFP48 = true,

    LC4064x_TQFP48 = true,
    LC4064ZC_TQFP48 = true,
    LC4064ZE_TQFP48 = true,
    LC4064ZC_csBGA56 = true,
    LC4064ZE_csBGA64 = true,
    LC4064x_TQFP100 = true,
    LC4064ZC_TQFP100 = true,
    LC4064ZE_TQFP100 = true,

    LC4128x_TQFP100 = true,
    LC4128ZC_TQFP100 = true,
    LC4128ZE_TQFP100 = true,
    LC4128V_TQFP144 = true,
    LC4128ZC_csBGA132 = true,
    LC4128ZE_TQFP144 = true,

    LC4256x_TQFP100 = true,
    LC4256ZC_TQFP100 = true,
    LC4256ZE_TQFP100 = true,
    LC4256ZC_csBGA132 = true,
    LC4256V_TQFP144 = true,
    LC4256ZE_TQFP144 = true,
    LC4256ZE_csBGA144 = true,
}

if grp_devices[device] == true then
    writeln('rule grp')
    writeln('    command = zig-out/bin/grp.exe $out')
    writeln('build $dev/grp.sx: grp')
    nl()
end

for _, job in ipairs(jobs) do
    writeln('rule ', job)
    writeln('    command = zig-out/bin/', job, '.exe $out')
    writeln('build $dev/', job, '.sx: ', job)
    nl()
end

write('build build-', device, ': phony')
if grp_devices[device] == true then
    write(' $dev/grp.sx')
end
for _, job in ipairs(jobs) do
    write(' $dev/', job, '.sx')
end
nl()
