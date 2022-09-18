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

for _, job in ipairs(jobs) do
    writeln('rule ', job)
    writeln('    command = zig-out/bin/', job, '.exe $out')
    writeln('build $dev/', job, '.sx: ', job)
    nl()
end

write('build build-', device, ': phony')
for _, job in ipairs(jobs) do
    write(' $dev/', job, '.sx')
end
nl()
