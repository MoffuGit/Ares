const std = @import("std");
const GPA = std.heap.GeneralPurposeAllocator(.{});
const Bus = @import("Bus.zig");

pub const xev = @import("xev").Dynamic;

pub var state: GlobalState = undefined;

pub const GlobalState = struct {
    const Self = @This();

    gpa: GPA,
    alloc: std.mem.Allocator,
    bus: Bus,

    pub fn init(self: *Self, callback: ?Bus.JsCallback) void {
        self.gpa = .{};
        self.alloc = self.gpa.allocator();
        self.bus = .{ .callback = callback };
    }
};
