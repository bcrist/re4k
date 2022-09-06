local device = ...
local jobs = {
    'zerohold',
    'slew',
    'threshold',
    'pull',
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
