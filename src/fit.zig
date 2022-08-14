const std = @import("std");

var temp_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);

pub const DeviceType = enum {
    lc4032ze,
    lc4032v,

    fn convert(self: DeviceType) []const u8 {
        return switch (self) {
            .lc4032ze => "M4E_32_32",
            .lc4032v => "M4S_32_30",
        };
    }
};

pub fn parseEnum(comptime E: type, optional_name: ?[]const u8) ?E {
    if (optional_name) |name| {
        for (std.enums.values(E)) |e| {
            if (std.mem.eql(u8, name, @tagName(e))) {
                return e;
            }
        }
    }
    return null;
}

pub fn main() !void {
    var alloc = temp_alloc.allocator();
    var args = try std.process.ArgIterator.initWithAllocator(alloc);
    _ = args.next() orelse std.os.exit(255);
    var lci_path = args.next() orelse std.os.exit(1);

    var path_iter = std.mem.tokenize(u8, lci_path, "/\\.");
    var device = parseEnum(DeviceType, path_iter.next()) orelse std.os.exit(2);

    if (std.fs.path.dirname(lci_path)) |dir_path| {
        try std.os.chdir(dir_path);
    }

    var base = std.fs.path.basename(lci_path);

    var ext_len = std.fs.path.extension(base).len;

    base = base[0..base.len - ext_len];

    const lci_filename = try std.fmt.allocPrint(alloc, "{s}.lci", .{ base });
    const tt4_filename = try std.fmt.allocPrint(alloc, "{s}.tt4", .{ base });
    const stdout_filename = try std.fmt.allocPrint(alloc, "{s}.stdout", .{ base });
    const stderr_filename = try std.fmt.allocPrint(alloc, "{s}.stderr", .{ base });

    var results = try std.ChildProcess.exec(.{
        .allocator = alloc,
        .argv = &[_][]const u8 {
            "C:\\ispLEVER_Classic2_1\\ispcpld\\bin\\lpf4k.exe",
            "-i", tt4_filename,
            "-lci", lci_filename,
            "-d", device.convert(),
            "-fmt", "PLA",
            //"-html_rpt",
            "-v",
        },
    });

    try std.fs.cwd().writeFile(stdout_filename, results.stdout);
    try std.fs.cwd().writeFile(stderr_filename, results.stderr);

    switch (results.term) {
        .Exited => |code| {
            if (code != 0) {
                try std.io.getStdErr().writer().print("lpf4k returned code {}", .{ code });
                std.os.exit(3);
            }
        },
        .Signal => |s| {
            try std.io.getStdErr().writer().print("lpf4k signalled {}", .{ s });
            std.os.exit(4);
        },
        .Stopped => |s| {
            try std.io.getStdErr().writer().print("lpf4k stopped with {}", .{ s });
            std.os.exit(5);
        },
        .Unknown => |s| {
            try std.io.getStdErr().writer().print("lpf4k terminated unexpectedly with {}", .{ s });
            std.os.exit(6);
        },
    }
}
