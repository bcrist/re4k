const std = @import("std");
const TempAllocator = @import("temp_allocator");

var temp_alloc = TempAllocator.init(0x100_00000);

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


fn GrpSniffer() type {
    
}



pub fn main() !void {
    // var alloc = temp_alloc.allocator();
    // var args = try std.process.ArgIterator.initWithAllocator(alloc);
    // _ = args.next() orelse std.os.exit(255);
    // var lci_path = args.next() orelse std.os.exit(1);

    // var path_iter = std.mem.tokenize(u8, lci_path, "/\\.");
    // var device = parseEnum(DeviceType, path_iter.next()) orelse std.os.exit(2);

    // if (std.fs.path.dirname(lci_path)) |dir_path| {
    //     try std.os.chdir(dir_path);
    // }

    // var base = std.fs.path.basename(lci_path);

    // var ext_len = std.fs.path.extension(base).len;

    // base = base[0..base.len - ext_len];

 
}
