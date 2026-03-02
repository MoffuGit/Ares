const std = @import("std");
const GPA = std.heap.GeneralPurposeAllocator(.{});
const Bus = @import("Bus.zig");
const EventEmitter = @import("EventEmitter.zig").EventEmitter(GlobalEvents);

pub const xev = @import("xev").Dynamic;

pub var state: GlobalState = undefined;

pub const GlobalEvents = union(enum) {
    Nothing,
};

pub const GlobalState = struct {
    const Self = @This();

    gpa: GPA,
    alloc: std.mem.Allocator,
    bus: Bus,
    events: EventEmitter,

    pub fn init(self: *Self, callback: ?Bus.Callback) void {
        self.gpa = .{};
        self.alloc = self.gpa.allocator();
        self.bus = .{ .callback = callback };
        self.bus.startDrain();
        self.events = EventEmitter.init(self.alloc);
    }

    pub fn deinit(self: *Self) void {
        self.bus.stopDrain();
        self.events.deinit();
        if (self.gpa.deinit() == .leak) {
            std.log.debug("WE HAVE LEAKS", .{});
        }
    }
};
