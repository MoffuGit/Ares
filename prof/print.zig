const std = @import("std");

pub fn print(comptime format: []const u8, args: anytype) void {
    var buffer: [4096]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, format, args) catch return;
    writeAllStdout(text);
}

pub fn writeAllStdout(bytes: []const u8) void {
    var written: usize = 0;
    while (written < bytes.len) {
        const amount = std.c.write(std.posix.STDOUT_FILENO, bytes[written..].ptr, bytes.len - written);
        if (amount <= 0) return;
        written += @intCast(amount);
    }
}
