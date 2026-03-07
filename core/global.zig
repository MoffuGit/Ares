const std = @import("std");
const GPA = std.heap.GeneralPurposeAllocator(.{});

const EventEmitter = @import("EventEmitter.zig").EventEmitter(GlobalEvents);

pub const Callback = *const fn (event: u8, ptr: ?[*]const u8, len: usize) callconv(.c) void;
const BlockingQueue = @import("datastruct").BlockingQueue;
const MailBox = BlockingQueue(Events, 64);

pub const xev = @import("xev").Dynamic;

pub var state: GlobalState = undefined;

pub const GlobalEvents = union(enum) {
    Nothing,
};

pub const Events = union(enum) {
    settings_update: void,
    theme_update: void,
    worktree_update: void,
};

pub const GlobalState = struct {
    const Self = @This();

    gpa: GPA = .{},
    alloc: std.mem.Allocator,
    events: EventEmitter,
    mailbox: MailBox = .{},
    callback: ?Callback = null,

    pub fn init(self: *Self, callback: ?Callback) void {
        self.* = .{
            .alloc = self.gpa.allocator(),
            .events = EventEmitter.init(self.alloc),
            .callback = callback,
            .mailbox = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.events.deinit();
        if (self.gpa.deinit() == .leak) {
            std.log.debug("WE HAVE LEAKS", .{});
        }
    }
};
