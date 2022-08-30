const std = @import("std");

pub fn ChecksumWriter(comptime SumType: type, comptime Writer: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        inner: Writer,
        checksum: SumType = 0,

        pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) !void {
            var buf: [1024]u8 = undefined;
            const raw = std.fmt.bufPrint(&buf, fmt, args) catch |err| {
                if (err == error.NoSpaceLeft) {
                    const raw = try std.fmt.allocPrint(self.allocator, fmt, args);
                    defer self.allocator.free(raw);
                    return self.writeAll(raw);
                } else {
                    return err;
                }
            };
            return self.writeAll(raw);
        }

        pub fn write(self: *Self, bytes: []const u8) !usize {
            const bytes_written = try self.inner.write(bytes);
            for (bytes[0..bytes_written]) |b| {
                self.checksum +%= b;
            }
            return bytes_written;
        }

        pub fn writeAll(self: *Self, bytes: []const u8) !void {
            var index: usize = 0;
            while (index != bytes.len) {
                index += try self.write(bytes[index..]);
            }
        }

        pub fn writeByte(self: *Self, byte: u8) !void {
            try self.inner.writeByte(byte);
            self.checksum +%= byte;
        }

        pub fn writeByteNTimes(self: *Self, byte: u8, n: usize) !void {
            try self.inner.writeByteNTimes(byte, n);
            self.checksum +%= @truncate(SumType, @as(SumType, byte) *% n);
        }

        pub fn writeIntNative(self: *Self, comptime T: type, value: T) !void {
            var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
            std.mem.writeIntNative(T, &bytes, value);
            return self.writeAll(&bytes);
        }

        pub fn writeIntForeign(self: *Self, comptime T: type, value: T) !void {
            var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
            std.mem.writeIntForeign(T, &bytes, value);
            return self.writeAll(&bytes);
        }

        pub fn writeIntLittle(self: *Self, comptime T: type, value: T) !void {
            var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
            std.mem.writeIntLittle(T, &bytes, value);
            return self.writeAll(&bytes);
        }

        pub fn writeIntBig(self: *Self, comptime T: type, value: T) !void {
            var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
            std.mem.writeIntBig(T, &bytes, value);
            return self.writeAll(&bytes);
        }

        pub fn writeInt(self: *Self, comptime T: type, value: T, endian: std.builtin.Endian) !void {
            var bytes: [(@typeInfo(T).Int.bits + 7) / 8]u8 = undefined;
            std.mem.writeInt(T, &bytes, value, endian);
            return self.writeAll(&bytes);
        }

        pub fn writeStruct(self: *Self, value: anytype) !void {
            // Only extern and packed structs have defined in-memory layout.
            comptime std.debug.assert(@typeInfo(@TypeOf(value)).Struct.layout != .Auto);
            return self.writeAll(std.mem.asBytes(&value));
        }
    };
}

pub fn checksumWriter(comptime SumType: type, allocator: std.mem.Allocator, writer: anytype) ChecksumWriter(SumType, @TypeOf(writer)) {
    return ChecksumWriter(SumType, @TypeOf(writer)) {
        .allocator = allocator,
        .inner = writer,
    };
}
