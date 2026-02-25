const std = @import("std");
const GPA = std.heap.GeneralPurposeAllocator(.{});

pub var state: GlobalState = undefined;

pub const GlobalState = struct {
    const Self = @This();

    gpa: GPA,
    alloc: std.mem.Allocator,

    pub fn init(self: *Self) void {
        var gpa: GPA = .{};
        const alloc = gpa.allocator();

        self.* = .{
            .gpa = gpa,
            .alloc = alloc,
        };
    }
};
