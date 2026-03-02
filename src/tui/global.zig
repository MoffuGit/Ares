const std = @import("std");
const GPA = std.heap.GeneralPurposeAllocator(.{});
const App = @import("mod.zig");

pub const xev = @import("xev").Dynamic;

pub var state: GlobalState = undefined;

pub const GlobalEvents = union(enum) {
    Nothing,
};

pub const GlobalState = struct {
    const Self = @This();

    gpa: GPA,
    alloc: std.mem.Allocator,

    pub fn init(self: *Self) void {
        self.gpa = .{};
        self.alloc = self.gpa.allocator();
    }

    pub fn deinit(self: *Self) void {
        if (self.gpa.deinit() == .leak) {
            std.log.debug("WE HAVE LEAKS", .{});
        }
    }
};
