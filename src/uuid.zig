const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Uuid = u128;

pub fn new_v4(io: Io) Uuid {
    var uuid: Uuid = undefined;

    const s = std.mem.asBytes(&uuid);
    io.random(s);

    uuid &= 0xffffffffffffff3fff0fffffffffffff;
    uuid |= 0x00000000000000800040000000000000;
    return uuid;
}

pub fn fmt(self: Uuid, alloc: Allocator) ![]u8 {
    return try std.fmt.allocPrint(alloc, "{}", .{self});
}

pub fn parse(buffer: []const u8) ?Uuid {
    return std.fmt.parseInt(Uuid, buffer, 10) catch return null;
}
