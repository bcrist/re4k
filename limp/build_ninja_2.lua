local device = ...

writeln('dev = ', fs.compose_path(device:sub(1, 6), device))
write [[

rule zerohold
    command = zig-out/bin/zerohold.exe $out

rule slew
    command = zig-out/bin/slew.exe $out

build $dev/zerohold.sx: zerohold
build $dev/slew.sx: slew

]]

writeln('build build-', device, ': phony $dev/zerohold.sx $dev/slew.sx')
