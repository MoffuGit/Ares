const std = @import("std");
const GPA = std.heap.GeneralPurposeAllocator(.{});
const App = @import("mod.zig");
const Bus = @import("Bus.zig");

pub const xev = @import("xev").Dynamic;

pub var state: GlobalState = undefined;

pub const GlobalState = struct {
    const Self = @This();

    gpa: GPA,
    alloc: std.mem.Allocator,
    bus: Bus,

    pub fn init(self: *Self, callback: ?Bus.Callback) void {
        self.gpa = .{};
        self.alloc = self.gpa.allocator();
        self.bus = .{ .callback = callback };
        self.bus.startDrain();
    }

    pub fn deinit(self: *Self) void {
        self.bus.stopDrain();
        if (self.gpa.deinit() == .leak) {
            std.log.debug("WE HAVE LEAKS", .{});
        }
    }
};
